import Foundation

/// 把扫描结果导入配置：按 kind 去重（网络库 host:port/dbname；本地库 localPath）、唯一命名、
/// 网络库写 Keychain 密码、可选创建默认任务。AppState（GUI）与 SeedCLI（头less）共用。
enum ConnectionImporter {
    static func uniqueName(base: String, existing: [String]) -> String {
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }

    /// v1.6.5 默认任务：全局备份位置 + 全局间隔（intervalSeconds）。
    static func defaultJob(connectionID: UUID, backupPath: String? = nil,
                           globalDefault: String? = nil,
                           intervalSeconds: Int = 600) -> BackupJob {
        let base = backupPath
            ?? globalDefault
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("DaVinci Database Auto Backup").path
        return BackupJob(id: UUID(), connectionId: connectionID, backupPath: base,
                         intervalSecs: max(intervalSeconds, 10), keepCount: 100, enabled: true)
    }

    /// 连接的 kind 感知去重键（网络：host:port/dbname；本地：local:path）。
    static func dedupKey(of conn: DatabaseConnection) -> String {
        switch conn.kind {
        case .network: return "\(conn.host):\(conn.port)/\(conn.dbname)"
        case .local: return "local:\(conn.localPath ?? "")"
        }
    }

    /// 把扫描结果写入 config（就地修改）。返回实际新增的连接数。
    @discardableResult
    static func applyDiscovered(_ items: [DiscoveredDatabase], to config: inout AppConfig,
                                createJobs: Bool, globalDefault: String? = nil,
                                intervalSeconds: Int = 600) -> Int {
        var added = 0
        for item in items {
            if config.connections.contains(where: { dedupKey(of: $0) == item.id }) { continue }
            let name = uniqueName(base: item.baseName, existing: config.connections.map(\.name))
            let conn: DatabaseConnection
            switch item.kind {
            case .network:
                conn = DatabaseConnection(id: UUID(), name: name, host: item.host,
                                          port: item.port, dbname: item.dbname,
                                          username: item.username, isDefault: config.connections.isEmpty,
                                          kind: .network)
                try? KeychainService.setString(item.password, account: conn.id.uuidString)
            case .local:
                conn = DatabaseConnection(id: UUID(), name: name,
                                          isDefault: config.connections.isEmpty,
                                          kind: .local, localPath: item.localPath)
            }
            config.connections.append(conn)
            if createJobs {
                config.jobs.append(defaultJob(connectionID: conn.id, globalDefault: globalDefault,
                                              intervalSeconds: intervalSeconds))
            }
            added += 1
        }
        return added
    }
}

extension DiscoveredDatabase {
    /// 导入连接时用的显示名（网络库用 dbname，本地库用注册名）。
    var baseName: String {
        switch kind {
        case .network: return dbname
        case .local: return dbname.isEmpty ? (localPath as NSString?)?.lastPathComponent ?? "Local" : dbname
        }
    }
}
