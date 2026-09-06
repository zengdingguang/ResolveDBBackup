import Foundation

/// 一次备份执行的结果。
struct BackupOutcome {
    var success: Bool
    var fileURL: URL?
    var sizeBytes: Int64
    var duration: TimeInterval
    var message: String?
}

/// 备份引擎：对单个库执行 `pg_dump -F c --blobs`，退出码 + 文件非空双重校验。
enum BackupRunner {
    /// v1.6.5 备份落盘目录：{全局备份位置}/{connectionName}/（全局统一，不再按库分路径）。
    static func backupFolder(root: String, connection: DatabaseConnection) -> URL {
        URL(fileURLWithPath: root).appendingPathComponent(connection.name, isDirectory: true)
    }

    /// 拼装 pg_dump 参数（数组传递，无需 shell 转义）。
    static func makeArguments(connection: DatabaseConnection, fileURL: URL) -> [String] {
        [
            "--host", connection.host,
            "--port", String(connection.port),
            "--username", connection.username,
            "--dbname", connection.dbname,
            "--blobs",
            "--format=custom",
            "--no-password",
            "--file", fileURL.path
        ]
    }

    /// 生成不覆盖的备份文件路径：`{name}_{yyyy_MM_dd_HH_mm}.{ext}`，
    /// 若同分钟已存在则追加 `_2`、`_3`…后缀（保证 60s 等短间隔也不覆盖），后缀在扩展名前。
    static func resolveUniqueFileURL(folder: URL, name: String, date: Date, ext: String) -> URL {
        let formatter = BackupNaming.dateFormatter
        let base = "\(name)_\(formatter.string(from: date)).\(ext)"
        let stem = (base as NSString).deletingPathExtension
        let url = folder.appendingPathComponent(base)
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        var n = 2
        while true {
            let candidate = folder.appendingPathComponent("\(stem)_\(n).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func resolveUniqueFileURL(folder: URL, dbname: String, date: Date) -> URL {
        resolveUniqueFileURL(folder: folder, name: dbname, date: date, ext: BackupNaming.backupExtension)
    }

    /// 本地库快照唯一路径：`{name}_{ts}.zip`。
    static func resolveUniqueZipURL(folder: URL, name: String, date: Date) -> URL {
        resolveUniqueFileURL(folder: folder, name: name, date: date, ext: BackupNaming.zipExtension)
    }

    static func runBackup(
        connection: DatabaseConnection,
        root: String,
        password: String,
        pgDumpPath: String,
        now: Date = Date()
    ) async -> BackupOutcome {
        let folder = backupFolder(root: root, connection: connection)
        let fileURL = resolveUniqueFileURL(folder: folder, dbname: connection.dbname, date: now)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return BackupOutcome(
                success: false, fileURL: fileURL, sizeBytes: 0, duration: 0,
                message: "无法创建备份目录 \(folder.path): \(error.localizedDescription)")
        }

        let start = Date()
        let result = await ProcessRunner.run(
            executable: pgDumpPath,
            arguments: makeArguments(connection: connection, fileURL: fileURL),
            environment: ["PGPASSWORD": password, "PGCONNECT_TIMEOUT": "10"])
        let duration = Date().timeIntervalSince(start)
        let size = fileSize(at: fileURL)

        if result.exitCode == 0, size > 0 {
            return BackupOutcome(success: true, fileURL: fileURL, sizeBytes: Int64(size), duration: duration, message: nil)
        }

        var msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty { msg = result.errorDescription ?? "pg_dump 退出码 \(result.exitCode)" }
        if size > 0 {
            msg = "pg_dump 异常退出（\(result.exitCode)），已生成部分文件: \(msg)"
        }
        // 失败时清理不完整/零字节残留，避免污染保留策略与还原
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return BackupOutcome(success: false, fileURL: fileURL, sizeBytes: Int64(size), duration: duration, message: msg)
    }

    /// 测试连接：psql SELECT 1（验证可达 + 认证 + 库存在）。返回 (是否成功, 详情)。
    static func testConnection(
        connection: DatabaseConnection,
        password: String,
        pgDumpPath: String
    ) async -> (ok: Bool, message: String) {
        let psql = ToolPaths.psql(for: pgDumpPath)
        let result = await ProcessRunner.run(
            executable: psql,
            arguments: [
                "--host", connection.host,
                "--port", String(connection.port),
                "--username", connection.username,
                "--dbname", connection.dbname,
                "--no-password",
                "-tAc", "SELECT 1"
            ],
            environment: ["PGPASSWORD": password, "PGCONNECT_TIMEOUT": "8"])
        if result.exitCode == 0, result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
            return (true, "连接成功（\(connection.host):\(connection.port)/\(connection.dbname)）")
        }
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = err.isEmpty ? (out.isEmpty ? (result.errorDescription ?? "未知错误") : out) : err
        return (false, "连接失败: \(detail)")
    }

    /// 本地库路径校验（存在 + 像达芬奇本地库）。
    static func validateLocalPath(_ path: String) -> (ok: Bool, message: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return (false, "路径不存在: \(path)")
        }
        guard isDir.boolValue else {
            return (false, "不是文件夹: \(path)")
        }
        if LocalDBScanner.looksLikeLocalDatabase(at: path) {
            return (true, "本地库有效（\(path)）")
        }
        return (false, "该文件夹不像达芬奇本地库（未发现 Resolve Projects 或 .db 文件）")
    }

    // MARK: - 本地数据库备份（整文件夹压缩快照）

    /// 备份达芬奇本地数据库：把整个源文件夹用 `ditto` 压缩为单文件快照
    /// `{backupPath}/{connectionName}/{name}_{ts}.zip`。退出码 + 文件非空双重校验。
    static func runLocalBackup(
        connection: DatabaseConnection,
        root: String,
        now: Date = Date()
    ) async -> BackupOutcome {
        guard let src = connection.localPath, !src.isEmpty else {
            return BackupOutcome(success: false, fileURL: nil, sizeBytes: 0, duration: 0,
                                 message: "本地库源路径为空")
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue else {
            return BackupOutcome(success: false, fileURL: nil, sizeBytes: 0, duration: 0,
                                 message: "本地库源路径不存在或不是文件夹: \(src)")
        }
        let folder = backupFolder(root: root, connection: connection)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return BackupOutcome(success: false, fileURL: nil, sizeBytes: 0, duration: 0,
                                 message: "无法创建备份目录 \(folder.path): \(error.localizedDescription)")
        }
        let zipURL = resolveUniqueZipURL(folder: folder, name: connection.name, date: now)
        // 用系统自带 ditto 压缩整个文件夹（保留权限/元数据），产物为单文件 zip 快照
        let start = Date()
        let result = await ProcessRunner.run(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent",
                        src, zipURL.path])
        let duration = Date().timeIntervalSince(start)
        let size = fileSize(at: zipURL)

        if result.exitCode == 0, size > 0 {
            return BackupOutcome(success: true, fileURL: zipURL, sizeBytes: Int64(size),
                                 duration: duration, message: nil)
        }
        var msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty { msg = result.errorDescription ?? "ditto 退出码 \(result.exitCode)" }
        if size > 0 { msg = "ditto 异常退出（\(result.exitCode)），已生成部分文件: \(msg)" }
        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }
        return BackupOutcome(success: false, fileURL: zipURL, sizeBytes: Int64(size),
                             duration: duration, message: msg)
    }

    private static func fileSize(at url: URL) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }
}
