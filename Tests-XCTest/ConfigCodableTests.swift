import XCTest
@testable import ResolveDBBackupCore

final class ConfigCodableTests: XCTestCase {
    func testDefaultConfigHasTwoConnectionsAndJobs() {
        let config = AppConfig.makeDefault()
        XCTAssertEqual(config.connections.count, 2)
        XCTAssertEqual(config.jobs.count, 2)
        XCTAssertEqual(config.connections.map { $0.name }.sorted(), ["2025X", "dingguang"])
        XCTAssertEqual(config.connections[0].host, "127.0.0.1")
        XCTAssertEqual(config.connections[1].host, "192.168.3.99")
        XCTAssertTrue(config.connections.contains { $0.isDefault })
        XCTAssertEqual(config.settings.pgDumpPath, "/Library/PostgreSQL/13/bin/pg_dump")
        XCTAssertEqual(config.jobs[0].intervalSecs, 3600)
        XCTAssertEqual(config.jobs[0].keepCount, 10)
        // 每库独立任务：job 的 connectionId 一一对应
        let connIDs = Set(config.connections.map { $0.id })
        XCTAssertEqual(Set(config.jobs.map { $0.connectionId }), connIDs)
    }

    func testConfigRoundTrip() throws {
        var config = AppConfig.makeDefault()
        config.settings.notifyOnSuccess = true
        config.settings.retention.keepDays30 = 5

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.settings.retention.keepDays30, 5)
        XCTAssertEqual(decoded.connections.count, 2)
        XCTAssertEqual(decoded.jobs.count, 2)
    }

    func testJobRoundTripWithLastRun() throws {
        var job = BackupJob(id: UUID(), connectionId: UUID(),
                            backupPath: "/Users/t/DaVinciBackups",
                            intervalSecs: 1800, keepCount: 5, enabled: false)
        job.lastRun = Date(timeIntervalSince1970: 1_700_000_000)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(job)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupJob.self, from: data)
        XCTAssertEqual(decoded, job)
        XCTAssertEqual(decoded.lastRun, job.lastRun)
        XCTAssertFalse(decoded.enabled)
    }

    func testBackupRecordRoundTrip() throws {
        let record = BackupRecord(id: UUID(), jobId: UUID(), connectionName: "dingguang",
                                  dbname: "dingguang", date: Date(),
                                  success: false, filePath: nil, sizeBytes: nil,
                                  duration: 12.5, error: "connection refused")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertFalse(decoded.success)
        XCTAssertNil(decoded.filePath)
    }

    func testPgpassLineFormat() {
        let conn = DatabaseConnection(id: UUID(), name: "dingguang", host: "127.0.0.1",
                                      port: 5432, dbname: "dingguang",
                                      username: "postgres", isDefault: true)
        XCTAssertEqual(PgpassManager.line(for: conn, password: "DaVinci"),
                       "127.0.0.1:5432:dingguang:postgres:DaVinci")
    }
}
