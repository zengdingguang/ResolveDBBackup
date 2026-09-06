import Foundation

/// 应用配置。连接不再硬编码预设——首次启动/CLI 通过 ConnectionScanner 自动发现本机数据库。
struct AppConfig: Codable, Equatable {
    var schemaVersion: Int = 1
    var connections: [DatabaseConnection] = []
    var jobs: [BackupJob] = []
    var settings = AppSettings()

    init() {}

    /// 旧配置迁移：schemaVersion / 各字段缺省时给默认值，避免旧版本（无 schemaVersion 等字段）
    /// 的配置解码失败而触发"覆盖为空配置"的灾难路径。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        connections = try c.decodeIfPresent([DatabaseConnection].self, forKey: .connections) ?? []
        jobs = try c.decodeIfPresent([BackupJob].self, forKey: .jobs) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }

    /// 空模板（仅默认设置）；连接由自动发现/用户手动添加。
    static func makeDefault() -> AppConfig {
        AppConfig()
    }
}
