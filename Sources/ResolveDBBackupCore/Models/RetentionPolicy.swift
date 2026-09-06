import Foundation

/// 全局保留策略（天档分层）。0 = 该档不启用。
struct RetentionPolicy: Codable, Equatable {
    /// 近 7 天内保留的份数（在“每库最近 N 份”之外追加）。
    var keepDays7: Int = 0
    /// 近 30 天内保留的份数。
    var keepDays30: Int = 0
    /// 近 90 天内保留的份数。
    var keepDays90: Int = 0
    /// 是否按 {backupPath}/{connectionName}/YYYY-MM/ 按月归档。
    var monthlyArchive: Bool = false

    init() {}

    init(keepDays7: Int, keepDays30: Int, keepDays90: Int, monthlyArchive: Bool) {
        self.keepDays7 = keepDays7
        self.keepDays30 = keepDays30
        self.keepDays90 = keepDays90
        self.monthlyArchive = monthlyArchive
    }

    /// 旧配置容错：字段缺省给默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepDays7 = try c.decodeIfPresent(Int.self, forKey: .keepDays7) ?? 0
        keepDays30 = try c.decodeIfPresent(Int.self, forKey: .keepDays30) ?? 0
        keepDays90 = try c.decodeIfPresent(Int.self, forKey: .keepDays90) ?? 0
        monthlyArchive = try c.decodeIfPresent(Bool.self, forKey: .monthlyArchive) ?? false
    }
}
