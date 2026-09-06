import Foundation

/// 达芬奇 dblist.conf 里的一条注册记录。
struct ResolveDBEntry: Equatable {
    var kind: ConnectionKind
    var name: String
    var host: String = ""
    var port: Int = 5432
    var username: String = "postgres"
    var password: String = ""
    var dbname: String = ""
    var localPath: String = ""
}

/// 扫描达芬奇「本地数据库」（磁盘文件夹 + SQLite，区别于本机/局域网的网络数据库）。
///
/// 获取策略（三层，推荐顺序）：
/// 1. 读达芬奇自己的注册表 `~/Library/Preferences/Blackmagic Design/DaVinci Resolve/dblist.conf`
///    ——无论用户把本地库放磁盘哪里，只要建过/连过就会被登记，路径就在里面；
/// 2. 扫官方默认目录 `.../DaVinci Resolve/Resolve Project Library` 与 `Resolve Project Database`；
/// 3. GUI 手动选择路径（由上层提供）。
enum LocalDBScanner {
    static let resolvePreferencesDir =
        "\(NSHomeDirectory())/Library/Preferences/Blackmagic Design/DaVinci Resolve"
    static let dblistPath = "\(resolvePreferencesDir)/dblist.conf"
    static let resolveSupportDir =
        "\(NSHomeDirectory())/Library/Application Support/Blackmagic Design/DaVinci Resolve"

    /// 官方默认本地库目录（按存在性过滤）。
    static var defaultLocalDirs: [String] {
        [
            "\(resolveSupportDir)/Resolve Project Library",
            "\(resolveSupportDir)/Resolve Project Database"
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// 解析 dblist.conf 文本。网络库行以 `:QPSQL` 结尾，本地库行以 `:DISK` 结尾。
    /// 例：`Local Database:/path:*:::DISK` → 本地；`namehost:host:user:pass:db:QPSQL` → 网络。
    static func parseDblist(_ text: String) -> [ResolveDBEntry] {
        var entries: [ResolveDBEntry] = []
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.components(separatedBy: ":")
            guard let last = parts.last else { continue }
            if last == "QPSQL", parts.count >= 6 {
                let host = parts[1]
                let nameHost = parts[0]
                var name = nameHost
                if host.count < nameHost.count, nameHost.hasSuffix(host) {
                    name = String(nameHost.dropLast(host.count))
                }
                entries.append(ResolveDBEntry(
                    kind: .network, name: name, host: host,
                    username: parts[2], password: parts[3], dbname: parts[4]))
            } else if last == "DISK", parts.count >= 2 {
                entries.append(ResolveDBEntry(kind: .local, name: parts[0], localPath: parts[1]))
            }
        }
        return entries
    }

    static func parseDblistFile(_ path: String) -> [ResolveDBEntry] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return parseDblist(text)
    }

    /// 读 dblist.conf 中的网络库凭据，供局域网/本机扫描额外尝试（比猜 DaVinci 更准）。
    static func networkCredentialEntries() -> [(username: String, password: String, host: String)] {
        parseDblistFile(dblistPath)
            .filter { $0.kind == .network }
            .map { ($0.username, $0.password, $0.host) }
    }

    /// 判断一个路径像不像达芬奇本地库（含 Resolve Projects 子目录，或目录/子目录里有 .db 文件）。
    static func looksLikeLocalDatabase(at path: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
        let projects = "\(path)/Resolve Projects"
        if fm.fileExists(atPath: projects) { return true }
        guard let enumerator = fm.enumerator(atPath: path) else { return false }
        var depth = 0
        for case let file as String in enumerator {
            depth += 1
            if depth > 2000 { return true }
            if file.hasSuffix(".db") { return true }
        }
        return false
    }

    /// 扫描达芬奇本地数据库；existing 用于跳过已添加的 localPath。
    static func scanLocalDatabases(existing: Set<String> = []) async -> [DiscoveredDatabase] {
        var found: [DiscoveredDatabase] = []
        var seenPaths = Set<String>()
        func addIfNew(_ item: DiscoveredDatabase) {
            guard let p = item.localPath else { return }
            let normalized = (p as NSString).standardizingPath
            guard !seenPaths.contains(normalized), !existing.contains("local:\(normalized)") else { return }
            seenPaths.insert(normalized)
            found.append(item)
        }
        // 1. dblist.conf 注册的本地库
        for e in parseDblistFile(dblistPath) where e.kind == .local {
            addIfNew(DiscoveredDatabase(kind: .local, dbname: e.name,
                                       localPath: e.localPath))
        }
        // 2. 官方默认目录（可能未被登记）
        for dir in defaultLocalDirs {
            if looksLikeLocalDatabase(at: dir) {
                let name = "Local Database (default)"
                addIfNew(DiscoveredDatabase(kind: .local, dbname: name, localPath: dir))
            }
        }
        return found
    }
}
