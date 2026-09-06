import Foundation

/// 一条备份历史记录（成功或失败都记）。
struct BackupRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var jobId: UUID
    var connectionName: String
    var dbname: String
    var date: Date
    var success: Bool
    var filePath: String?
    var sizeBytes: Int64?
    var duration: TimeInterval
    var error: String?
}
