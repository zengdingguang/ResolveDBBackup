import Foundation

/// 扫描发现的一个数据库候选（网络库 host:port/dbname 唯一；本地库 localPath 唯一）。
struct DiscoveredDatabase: Identifiable, Equatable {
    var kind: ConnectionKind
    var host: String
    var port: Int
    var dbname: String
    var username: String
    var password: String
    var localPath: String?

    init(kind: ConnectionKind = .network, host: String = "", port: Int = 5432,
         dbname: String = "", username: String = "postgres", password: String = "",
         localPath: String? = nil) {
        self.kind = kind
        self.host = host
        self.port = port
        self.dbname = dbname
        self.username = username
        self.password = password
        self.localPath = localPath
    }

    var id: String {
        switch kind {
        case .network: return "\(host):\(port)/\(dbname)"
        case .local: return "local:\(localPath ?? "")"
        }
    }

    /// 界面/日志显示。
    var displayName: String {
        switch kind {
        case .network: return "\(dbname) @ \(host):\(port)"
        case .local: return localPath ?? "（未设置路径）"
        }
    }
}

/// 自动发现本机 PostgreSQL 数据库：
/// 1) 定位本机 PG 工具目录（/Library/PostgreSQL/<ver>/bin、Homebrew、settings 指定）；
/// 2) 探测 127.0.0.1 常见端口（pg_isready）；
/// 3) 用常见默认凭据尝试认证并列出非模板数据库。
enum ConnectionScanner {
    /// 常见 PostgreSQL 端口（含 BMD EDB 安装与多实例）。
    static let defaultPorts = [5432, 5433, 5434, 5435, 5436, 5437, 5438, 5439, 5440, 5441, 5442, 5443]
    static let localHosts = ["127.0.0.1"]
    /// 常见默认凭据：(用户, 密码)。DaVinci 默认 DaVinci；其次 postgres/postgres、空密码（trust）。
    static let defaultCredentials: [(String, String)] = [
        ("postgres", "DaVinci"),
        ("postgres", "postgres"),
        ("postgres", "")
    ]

    /// 本机 PG bin 目录（psql/pg_isready/pg_dump 所在），优先 BMD 安装。
    static func discoverPGToolDirs(preferred: String? = nil) -> [String] {
        var dirs: [String] = []
        var seen = Set<String>()
        func add(_ d: String) {
            guard !seen.contains(d),
                  FileManager.default.fileExists(atPath: "\(d)/psql") else { return }
            seen.insert(d)
            dirs.append(d)
        }
        if let preferred, !preferred.isEmpty { add(preferred) }
        let bmdRoot = "/Library/PostgreSQL"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: bmdRoot) {
            for v in versions.sorted(by: { ($0 as NSString).integerValue > ($1 as NSString).integerValue }) {
                add("\(bmdRoot)/\(v)/bin")
            }
        }
        for d in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/Library/PostgreSQL/bin"] {
            add(d)
        }
        return dirs
    }

    /// 端口是否可达（pg_isready -t 1），失败重试一次以容忍瞬时抖动。
    static func probe(host: String, port: Int, pgIsReady: String) async -> Bool {
        for attempt in 1...2 {
            let r = await ProcessRunner.run(executable: pgIsReady,
                                            arguments: ["-h", host, "-p", String(port), "-t", "1"])
            if r.exitCode == 0 { return true }
            if attempt == 1 { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        return false
    }

    /// 列出某服务器上的非模板数据库；认证失败返回空。
    static func listDatabases(host: String, port: Int, username: String, password: String,
                              psqlPath: String) async -> [String] {
        // 优先连 postgres 维护库；不存在则退化为不带 -d（连用户名同名库）；整体失败重试一次
        let env = ["PGPASSWORD": password, "PGCONNECT_TIMEOUT": "5"]
        let argsBase = ["-h", host, "-p", String(port), "-U", username,
                        "--no-password", "-tAc",
                        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres' ORDER BY datname"]
        for attempt in 1...2 {
            var r = await ProcessRunner.run(executable: psqlPath,
                                            arguments: argsBase + ["-d", "postgres"],
                                            environment: env)
            if r.exitCode != 0 {
                r = await ProcessRunner.run(executable: psqlPath,
                                            arguments: argsBase,
                                            environment: env)
            }
            if r.exitCode == 0 {
                let dbs = r.stdout.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !dbs.isEmpty { return dbs }
            }
            if attempt == 1 { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        return []
    }

    /// 扫描本机所有本地库；existing 用于跳过已添加的 host:port/dbname。
    static func scanLocal(existing: Set<String> = [], preferredToolDir: String? = nil) async -> [DiscoveredDatabase] {
        let dirs = discoverPGToolDirs(preferred: preferredToolDir)
        guard let first = dirs.first else { return [] }
        let psql = "\(first)/psql"
        let pgIsReady = "\(first)/pg_isready"

        var found: [DiscoveredDatabase] = []
        for host in localHosts {
            for port in defaultPorts {
                guard await probe(host: host, port: port, pgIsReady: pgIsReady) else {
                    continue
                }
                for (user, pwd) in defaultCredentials {
                    let dbs = await listDatabases(host: host, port: port,
                                                  username: user, password: pwd,
                                                  psqlPath: psql)
                    if !dbs.isEmpty {
                        for db in dbs {
                            let item = DiscoveredDatabase(host: host, port: port,
                                                          dbname: db, username: user, password: pwd)
                            let key = item.id
                            if !existing.contains(key), !found.contains(item) {
                                found.append(item)
                            }
                        }
                        break // 该端口已用某组凭据成功
                    }
                }
            }
        }
        return found
    }
}
