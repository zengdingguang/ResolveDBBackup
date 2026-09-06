import Foundation

/// PostgreSQL 工具路径与备份命名约定。
enum ToolPaths {
    static let defaultPgDump = "/Library/PostgreSQL/13/bin/pg_dump"

    static func psql(for pgDump: String) -> String {
        (pgDump as NSString).deletingLastPathComponent + "/psql"
    }
    static func pgRestore(for pgDump: String) -> String {
        (pgDump as NSString).deletingLastPathComponent + "/pg_restore"
    }

    /// 意见3：自动检测常见安装位置里的 pg_dump。
    /// 扫描顺序：Homebrew（Apple Silicon / Intel）、MacPorts、/usr/bin、EDB 的 /Library/PostgreSQL/<ver>/bin（高版本优先）。
    /// 找不到返回 nil。
    static func detectPgDump() -> String? {
        let fixed = [
            "/opt/homebrew/bin/pg_dump",
            "/usr/local/bin/pg_dump",
            "/opt/local/bin/pg_dump",
            "/usr/bin/pg_dump"
        ]
        for c in fixed where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        let base = "/Library/PostgreSQL"
        if let subs = try? FileManager.default.contentsOfDirectory(atPath: base) {
            let vers = subs.filter { Int($0) != nil }.sorted { Int($0)! > Int($1)! }  // 高版本优先
            for v in vers {
                let p = "\(base)/\(v)/bin/pg_dump"
                if FileManager.default.isExecutableFile(atPath: p) {
                    return p
                }
            }
        }
        return nil
    }

    /// 意见4：当前 App 版本号（读 bundle），如 "v1.6.0 (17)"。
    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "v\(v)" + (b.isEmpty ? "" : " (\(b))")
    }
}

enum BackupNaming {
    /// 时间戳命名：{dbname}_{YYYY_MM_DD_HH_MM}.backup（防覆盖）。
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy_MM_dd_HH_mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
    static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static let backupExtension = "backup"
    /// 本地库快照扩展名（zip 单文件）。
    static let zipExtension = "zip"
    static let snapshotExtensions = [backupExtension, zipExtension]

    static func fileName(dbname: String, date: Date) -> String {
        "\(dbname)_\(dateFormatter.string(from: date)).backup"
    }
    static func zipName(name: String, date: Date) -> String {
        "\(name)_\(dateFormatter.string(from: date)).zip"
    }
}
