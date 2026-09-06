import Foundation

/// 可选：把密码写入 ~/.pgpass（权限 600），便于 psql/pg_restore 手工操作。
/// 按 (host:port:db:user) 前缀去重合并，不破坏用户已有条目。
enum PgpassManager {
    static var pgpassURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pgpass")
    }

    static func line(for connection: DatabaseConnection, password: String) -> String {
        "\(connection.host):\(connection.port):\(connection.dbname):\(connection.username):\(password)"
    }

    @discardableResult
    static func ensure(entries: [(DatabaseConnection, String)], enabled: Bool) -> Bool {
        let url = pgpassURL
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
        // 去掉属于我们的条目
        lines.removeAll { line in
            entries.contains { item in
                let prefix = "\(item.0.host):\(item.0.port):\(item.0.dbname):\(item.0.username):"
                return line.hasPrefix(prefix)
            }
        }
        if enabled {
            for item in entries {
                lines.append(line(for: item.0, password: item.1))
            }
        }
        let content = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
