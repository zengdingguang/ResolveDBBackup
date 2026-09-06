import Foundation

/// `--run-backup <jobId>` CLI 入口：LaunchAgent 调度时以无 UI 方式执行备份并退出。
public enum BackupCLI {
    public static func run(jobID: String) -> Int32 {
        let store = ConfigStore()
        guard let config = store.loadConfig() else {
            writeError("无法加载配置（请先启动一次 GUI 应用以初始化）")
            return 1
        }
        guard let job = config.jobs.first(where: { $0.id.uuidString == jobID }) else {
            writeError("未找到任务 \(jobID)")
            return 1
        }
        guard let conn = config.connections.first(where: { $0.id == job.connectionId }) else {
            writeError("未找到任务对应的连接")
            return 1
        }

        let password = KeychainService.getString(account: conn.id.uuidString) ?? ""
        let root = AppSettings.effectiveRoot(config.settings.backupRoot)
        let sem = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 1

        Task {
            let result: BackupOutcome
            switch conn.kind {
            case .network:
                result = await BackupRunner.runBackup(
                    connection: conn, root: root,
                    password: password,
                    pgDumpPath: config.settings.pgDumpPath)
            case .local:
                result = await BackupRunner.runLocalBackup(connection: conn, root: root)
            }

            var finalURL = result.fileURL
            if result.success, let url = result.fileURL {
                finalURL = url
                // v1.6.6 时间机器式保留：最近 24 小时内全部保留，超过 24 小时每天保留 1 份
                let folder = URL(fileURLWithPath: root)
                    .appendingPathComponent(conn.name, isDirectory: true)
                RetentionManager.apply24hDaily(folder: folder)
            }

            var history = store.loadHistory()
            let record = BackupRecord(
                id: UUID(), jobId: job.id, connectionName: conn.name, dbname: conn.dbname,
                date: Date(), success: result.success,
                filePath: finalURL?.path,
                sizeBytes: result.success ? result.sizeBytes : nil,
                duration: result.duration, error: result.message)
            history.insert(record, at: 0)
            if history.count > 500 { history = Array(history.prefix(500)) }
            try? store.saveHistory(history)

            if result.success {
                print("备份成功: \(finalURL?.path ?? "") (\(result.sizeBytes) bytes, "
                      + String(format: "%.1f", result.duration) + "s)")
                if config.settings.notifyOnSuccess {
                    await Notifier.notify(title: "ResolveDBBackup · 备份成功",
                                          body: "\(conn.name)：\(finalURL?.lastPathComponent ?? "")")
                }
                exitCode = 0
            } else {
                let msg = result.message ?? "未知错误"
                writeError("备份失败: \(msg)")
                if config.settings.notifyOnFailure {
                    await Notifier.notify(title: "ResolveDBBackup · 备份失败",
                                          body: "\(conn.name)：\(msg)")
                }
                exitCode = 1
            }
            sem.signal()
        }
        sem.wait()
        return exitCode
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("ResolveDBBackup: \(message)\n".utf8))
    }
}
