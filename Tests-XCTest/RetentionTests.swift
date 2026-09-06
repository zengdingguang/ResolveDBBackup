import XCTest
@testable import ResolveDBBackupCore

final class RetentionTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("retention-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// 创建带指定修改时间的 .backup 文件，返回 [文件名: 相对天数前]。
    @discardableResult
    private func makeFiles(named names: [String], daysAgo: [Double]) throws -> [URL] {
        var urls: [URL] = []
        for (name, days) in zip(names, daysAgo) {
            let url = folder.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            let date = Date().addingTimeInterval(-days * 86400)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            urls.append(url)
        }
        return urls
    }

    private func names(_ urls: [URL]) -> Set<String> {
        Set(urls.map { $0.lastPathComponent })
    }

    func testKeepRecentOnly() throws {
        // 10 份文件，keepCount=3，其余档位全 0 → 只保留最新 3 份
        let names = (1...10).map { String(format: "db_%02d.backup", $0) }
        let days: [Double] = (1...10).map { Double($0) } // 1~10 天前，旧→新排序
        try makeFiles(named: names, daysAgo: days)
        let policy = RetentionPolicy() // 全 0
        let result = RetentionManager.apply(folder: folder, keepCount: 3, policy: policy)
        XCTAssertEqual(result.kept.count, 3)
        // 最新的是 1 天前那个
        XCTAssertTrue(result.kept.map { $0.lastPathComponent }.contains("db_01.backup"))
        XCTAssertEqual(result.deleted.count, 7)
    }

    func testKeepRecentZeroWithTierPolicy() throws {
        // keepCount=0（不启用最近 N），7 天档保留 2 份
        let names = (1...10).map { String(format: "db_%02d.backup", $0) }
        let days: [Double] = (1...10).map { Double($0) }
        try makeFiles(named: names, daysAgo: days)
        var policy = RetentionPolicy()
        policy.keepDays7 = 2
        let result = RetentionManager.apply(folder: folder, keepCount: 0, policy: policy)
        // 7 天内文件 = 前 7 个（1..7 天前），保留最新 2 个
        XCTAssertEqual(result.kept.count, 2)
        XCTAssertTrue(names(result.kept).contains("db_01.backup"))
        XCTAssertTrue(names(result.kept).contains("db_02.backup"))
        XCTAssertEqual(result.deleted.count, 8)
    }

    func testKeepRecentPlusDayTier() throws {
        // keepCount=2 且 30 天档保留 2 → 共 4 份
        let names = (1...10).map { String(format: "db_%02d.backup", $0) }
        let days: [Double] = (1...10).map { Double($0) }
        try makeFiles(named: names, daysAgo: days)
        var policy = RetentionPolicy()
        policy.keepDays30 = 2
        let result = RetentionManager.apply(folder: folder, keepCount: 2, policy: policy)
        // 最近 2 份（db_01, db_02）+ 30 天内剩余里的最新 2 份（db_03, db_04）
        XCTAssertEqual(result.kept.count, 4)
        XCTAssertEqual(result.deleted.count, 6)
        XCTAssertTrue(names(result.kept).contains("db_01.backup"))
        XCTAssertTrue(names(result.kept).contains("db_04.backup"))
    }

    func testAllDisabledKeepsEverything() throws {
        let names = (1...5).map { String(format: "db_%02d.backup", $0) }
        try makeFiles(named: names, daysAgo: (1...5).map { Double($0) })
        let result = RetentionManager.apply(folder: folder, keepCount: 0, policy: RetentionPolicy())
        XCTAssertEqual(result.kept.count, 5)
        XCTAssertEqual(result.deleted.count, 0)
    }

    func testEmptyFolder() {
        let result = RetentionManager.apply(folder: folder, keepCount: 3, policy: RetentionPolicy())
        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertTrue(result.deleted.isEmpty)
    }

    func testMonthlyArchiveMovesFile() throws {
        var policy = RetentionPolicy()
        policy.monthlyArchive = true
        let file = folder.appendingPathComponent("db_2026_09_04_08_30.backup")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        let moved = RetentionManager.archiveIfNeeded(fileURL: file, policy: policy)
        XCTAssertNotEqual(moved.path, file.path)
        XCTAssertTrue(moved.path.contains("2026-09"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }

    func testNamingFormatter() {
        let fmt = BackupNaming.dateFormatter
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let date = fmt.date(from: "2026_09_04_08_30")!
        XCTAssertEqual(BackupNaming.fileName(dbname: "dingguang", date: date),
                       "dingguang_2026_09_04_08_30.backup")
    }
}
