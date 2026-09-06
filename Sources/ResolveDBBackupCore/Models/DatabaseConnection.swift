import Foundation

/// 数据库类型：network = 达芬奇网络数据库（PostgreSQL，本机或局域网）；local = 达芬奇本地数据库（磁盘文件夹 + SQLite）。
enum ConnectionKind: String, Codable {
    case network
    case local

    var displayName: String {
        switch self {
        case .network: return "网络数据库"
        case .local: return "本地数据库"
        }
    }
}

/// 一条数据库连接。网络库用 host/port/dbname/username；本地库用 localPath（文件夹）。
struct DatabaseConnection: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var dbname: String
    var username: String
    var isDefault: Bool
    /// 连接类型；旧配置无此字段时默认 .network。
    var kind: ConnectionKind = .network
    /// 本地库源路径（kind == .local 时使用）。
    var localPath: String? = nil

    init(id: UUID, name: String, host: String = "", port: Int = 5432, dbname: String = "",
         username: String = "postgres", isDefault: Bool = false,
         kind: ConnectionKind = .network, localPath: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.dbname = dbname
        self.username = username
        self.isDefault = isDefault
        self.kind = kind
        self.localPath = localPath
    }

    /// 旧配置迁移：kind/localPath 缺省时给默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 5432
        dbname = try c.decodeIfPresent(String.self, forKey: .dbname) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? "postgres"
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        kind = try c.decodeIfPresent(ConnectionKind.self, forKey: .kind) ?? .network
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath)
    }

    /// 界面/日志用的"来源"描述。
    var sourceDescription: String {
        switch kind {
        case .network: return "\(host):\(port)/\(dbname)"
        case .local: return localPath ?? "（未设置路径）"
        }
    }

    /// 意见1：网络库是否指向本机（本机共享）——localhost / 127.* / 本机任一网卡 IP。
    /// 用于连接列表三分类：本地数据库 / 本机共享数据库 / 局域网共享数据库。
    var isLocalShared: Bool {
        guard kind == .network else { return false }
        if host == "localhost" || host.hasPrefix("127.") { return true }
        return NetworkInterfaces.list().contains { $0.ip == host }
    }

    static func == (lhs: DatabaseConnection, rhs: DatabaseConnection) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.host == rhs.host
            && lhs.port == rhs.port
            && lhs.dbname == rhs.dbname
            && lhs.username == rhs.username
            && lhs.isDefault == rhs.isDefault
            && lhs.kind == rhs.kind
            && lhs.localPath == rhs.localPath
    }
}
