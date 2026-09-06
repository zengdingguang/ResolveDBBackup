import Foundation

/// 应用全局设置。
struct AppSettings: Codable, Equatable {
    /// pg_dump 绝对路径（可覆盖，默认 BMD PG13）。
    var pgDumpPath: String = "/Library/PostgreSQL/13/bin/pg_dump"
    var retention = RetentionPolicy()
    /// 开机自启（用户级 LaunchAgent / SMAppService）。v1.4 起默认开启。
    var launchAtLogin: Bool = true
    /// v1.6.6 全局备份位置：所有库统一存到这里，内部按库名分层。
    /// 兼容旧字段 defaultBackupPath（解码时回退）。
    var backupRoot: String? = nil
    var notifyOnFailure: Bool = true
    var notifyOnSuccess: Bool = false
    /// 同步密码到 ~/.pgpass（权限 600）。
    var syncToPgpass: Bool = false

    // MARK: - 全局备份机制（v1.6.6：时间机器式，仅用 backupIntervalMinutes）
    /// 分钟级备份间隔（分钟），默认 10。
    var backupIntervalMinutes: Int = 10
    /// 兼容保留字段（v1.6.5 达芬奇三层用，v1.6.6 起不再使用）。
    var hourlyRetentionHours: Int = 1
    /// 兼容保留字段（v1.6.5 达芬奇三层用，v1.6.6 起不再使用）。
    var dailyRetentionDays: Int = 1

    init() {}

    // 手动 CodingKeys：包含已移除的旧字段 defaultBackupPath，用于解码兼容。
    private enum CodingKeys: String, CodingKey {
        case pgDumpPath, retention, launchAtLogin, backupRoot, defaultBackupPath,
             notifyOnFailure, notifyOnSuccess, syncToPgpass,
             backupIntervalMinutes, hourlyRetentionHours, dailyRetentionDays
    }

    /// 全局备份位置的实际值（未设置时的兜底目录）。
    static func effectiveRoot(_ root: String?) -> String {
        root ?? "\(NSHomeDirectory())/DaVinci Database Auto Backup"
    }

    /// 旧配置容错：字段缺省给默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pgDumpPath = try c.decodeIfPresent(String.self, forKey: .pgDumpPath)
            ?? "/Library/PostgreSQL/13/bin/pg_dump"
        retention = try c.decodeIfPresent(RetentionPolicy.self, forKey: .retention) ?? RetentionPolicy()
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        // v1.6.5：优先新字段 backupRoot，回退旧字段 defaultBackupPath
        if let root = try c.decodeIfPresent(String.self, forKey: .backupRoot) {
            backupRoot = root
        } else {
            backupRoot = try c.decodeIfPresent(String.self, forKey: .defaultBackupPath)
        }
        notifyOnFailure = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFailure) ?? true
        notifyOnSuccess = try c.decodeIfPresent(Bool.self, forKey: .notifyOnSuccess) ?? false
        syncToPgpass = try c.decodeIfPresent(Bool.self, forKey: .syncToPgpass) ?? false
        backupIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .backupIntervalMinutes) ?? 10
        hourlyRetentionHours = try c.decodeIfPresent(Int.self, forKey: .hourlyRetentionHours) ?? 1
        dailyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .dailyRetentionDays) ?? 1
    }

    /// 编码（defaultBackupPath 为兼容旧配置的只读字段，不写出）。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pgDumpPath, forKey: .pgDumpPath)
        try c.encode(retention, forKey: .retention)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encodeIfPresent(backupRoot, forKey: .backupRoot)
        try c.encode(notifyOnFailure, forKey: .notifyOnFailure)
        try c.encode(notifyOnSuccess, forKey: .notifyOnSuccess)
        try c.encode(syncToPgpass, forKey: .syncToPgpass)
        try c.encode(backupIntervalMinutes, forKey: .backupIntervalMinutes)
        try c.encode(hourlyRetentionHours, forKey: .hourlyRetentionHours)
        try c.encode(dailyRetentionDays, forKey: .dailyRetentionDays)
    }
}
