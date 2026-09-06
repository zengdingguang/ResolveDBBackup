import Foundation

/// `--seed-config` 头less 初始化：空配置 + 自动扫描本机数据库并添加（含默认任务）。
/// GUI 首启也会自动做同样的事；此入口便于纯 CLI / LaunchAgent 场景与自动化测试。
public enum SeedCLI {
    public static func run() -> Int32 {
        let store = ConfigStore()
        if store.loadConfig() != nil {
            print("配置已存在，跳过初始化")
            return 0
        }
        var config = AppConfig.makeDefault()
        try? store.saveConfig(config)

        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task {
            let toolDir = (config.settings.pgDumpPath as NSString).deletingLastPathComponent
            let network = await ConnectionScanner.scanLocal(preferredToolDir: toolDir)
            let locals = await LocalDBScanner.scanLocalDatabases()
            let found = network + locals
            if found.isEmpty {
                print("未发现数据库；可在 GUI 中用扫描功能或手动添加连接")
            } else {
                let added = ConnectionImporter.applyDiscovered(found, to: &config, createJobs: true,
                                                               globalDefault: AppSettings.effectiveRoot(config.settings.backupRoot))
                try? store.saveConfig(config)
                print("自动发现并添加 \(added) 个数据库连接（网络库 + 本地库）：")
                for c in config.connections {
                    print("  - [\(c.kind.displayName)] \(c.name) @ \(c.sourceDescription)")
                }
            }
            code = 0
            sem.signal()
        }
        sem.wait()
        return code
    }
}
