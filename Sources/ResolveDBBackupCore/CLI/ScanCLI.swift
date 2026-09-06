import Foundation

/// `--scan-local` / `--scan-localdb` / `--scan-lan <targets>`：只打印发现结果，不改动配置（诊断/分发前检查用）。
/// `--scan-lan-import <targets>`：扫描局域网并把结果导入配置（含默认任务），便于 headless 恢复。
/// `--ensure-jobs`：为所有缺任务的连接补齐默认任务（幂等修复）。
public enum ScanCLI {
    public static func run() -> Int32 {
        let args = CommandLine.arguments
        if args.contains("--scan-localdb") {
            return runLocalDB()
        }
        if args.contains("--ensure-jobs") {
            return runEnsureJobs()
        }
        if let i = args.firstIndex(of: "--scan-lan-import"), i + 1 < args.count {
            return runLANImport(targetsText: args[i + 1])
        }
        if let i = args.firstIndex(of: "--scan-lan"), i + 1 < args.count {
            return runLAN(targetsText: args[i + 1])
        }
        return runNetworkLocal()
    }

    static func toolDir() -> String {
        let store = ConfigStore()
        if let cfg = store.loadConfig() {
            return (cfg.settings.pgDumpPath as NSString).deletingLastPathComponent
        }
        return (ToolPaths.defaultPgDump as NSString).deletingLastPathComponent
    }

    static func runNetworkLocal() -> Int32 {
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 1
        Task {
            let found = await ConnectionScanner.scanLocal(preferredToolDir: toolDir())
            if found.isEmpty {
                print("未在本机发现 PostgreSQL（网络）数据库")
            } else {
                print("发现 \(found.count) 个本机网络数据库：")
                for f in found { print("  - \(f.id)（用户 \(f.username)）") }
                code = 0
            }
            sem.signal()
        }
        sem.wait()
        return code
    }

    static func runLocalDB() -> Int32 {
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 1
        Task {
            let found = await LocalDBScanner.scanLocalDatabases()
            if found.isEmpty {
                print("未发现达芬奇本地数据库（检查 dblist.conf 与默认目录）")
            } else {
                print("发现 \(found.count) 个达芬奇本地数据库：")
                for f in found { print("  - \(f.id)") }
                code = 0
            }
            sem.signal()
        }
        sem.wait()
        return code
    }

    static func runLAN(targetsText: String) -> Int32 {
        let targets = targetsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let expanded = LANScanner.expandTargets(targets)
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 1
        Task {
            let extra = LocalDBScanner.networkCredentialEntries().map { ($0.username, $0.password) }
            let found = await LANScanner.scanLAN(targets: expanded, preferredToolDir: toolDir(),
                                                 extraCredentials: extra)
            if found.isEmpty {
                print("目标 \(targets.joined(separator: ", ")) 未发现可达的 PostgreSQL 数据库")
            } else {
                print("发现 \(found.count) 个局域网数据库：")
                for f in found { print("  - \(f.id)（用户 \(f.username)）") }
                code = 0
            }
            sem.signal()
        }
        sem.wait()
        return code
    }

    static func runLANImport(targetsText: String) -> Int32 {
        let store = ConfigStore()
        var config = store.loadConfig() ?? AppConfig.makeDefault()
        let targets = targetsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let expanded = LANScanner.expandTargets(targets)
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 1
        Task {
            let toolDir = (config.settings.pgDumpPath as NSString).deletingLastPathComponent
            let extra = LocalDBScanner.networkCredentialEntries().map { ($0.username, $0.password) }
            let found = await LANScanner.scanLAN(targets: expanded, preferredToolDir: toolDir,
                                                 extraCredentials: extra)
            if found.isEmpty {
                print("目标 \(targets.joined(separator: ", ")) 未发现可达的 PostgreSQL 数据库，未做改动")
            } else {
                let added = ConnectionImporter.applyDiscovered(found, to: &config, createJobs: true,
                                                               globalDefault: AppSettings.effectiveRoot(config.settings.backupRoot))
                try? store.saveConfig(config)
                ScheduleManager().syncAll(jobs: config.jobs, intervalSeconds: max(config.settings.backupIntervalMinutes, 1) * 60, executablePath: CommandLine.arguments[0])
                print("已导入 \(added) 个局域网连接（含默认备份任务）：")
                for c in config.connections where c.kind == .network && !c.host.hasPrefix("127.") {
                    print("  - [\(c.kind.displayName)] \(c.name) @ \(c.sourceDescription)")
                }
                code = 0
            }
            sem.signal()
        }
        sem.wait()
        return code
    }

    static func runEnsureJobs() -> Int32 {
        let store = ConfigStore()
        guard var config = store.loadConfig() else {
            print("未找到配置，无法修复")
            return 1
        }
        var added = 0
        for conn in config.connections where !config.jobs.contains(where: { $0.connectionId == conn.id }) {
            config.jobs.append(ConnectionImporter.defaultJob(connectionID: conn.id,
                                                             globalDefault: AppSettings.effectiveRoot(config.settings.backupRoot),
                                                             intervalSeconds: max(config.settings.backupIntervalMinutes, 1) * 60))
            added += 1
        }
        try? store.saveConfig(config)
        ScheduleManager().syncAll(jobs: config.jobs, intervalSeconds: max(config.settings.backupIntervalMinutes, 1) * 60, executablePath: CommandLine.arguments[0])
        print(added > 0 ? "已补齐 \(added) 个缺失任务" : "所有连接均有任务，无需修复")
        return 0
    }
}
