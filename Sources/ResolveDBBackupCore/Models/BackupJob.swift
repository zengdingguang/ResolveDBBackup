import Foundation

/// 一个数据库对应的备份任务：路径 / 间隔（秒）/ 保留份数 / 启用开关，彼此独立。
struct BackupJob: Identifiable, Codable, Equatable {
    var id: UUID
    var connectionId: UUID
    /// 备份根目录（用户自定义）；实际落盘在 {backupPath}/{connectionName}/ 下。
    var backupPath: String
    /// 定时间隔（秒），LaunchAgent 的 StartInterval。
    var intervalSecs: Int
    /// 每库保留最近 N 份；0 = 不限制（仅按设置中的天档策略）。
    var keepCount: Int
    var enabled: Bool
    /// 最近一次执行时间（GUI 内更新；CLI 通过记录写入历史）。
    var lastRun: Date?
}
