import XCTest
@testable import ResolveDBBackupCore

final class CommandAssemblyTests: XCTestCase {
    func testPGDumpArguments() throws {
        let conn = DatabaseConnection(id: UUID(), name: "dingguang", host: "127.0.0.1",
                                      port: 5432, dbname: "dingguang",
                                      username: "postgres", isDefault: true)
        let url = URL(fileURLWithPath: "/Users/t/backup/dingguang/dingguang_2026_09_04_08_30.backup")
        let args = BackupRunner.makeArguments(connection: conn, fileURL: url)
        XCTAssertEqual(args, [
            "--host", "127.0.0.1",
            "--port", "5432",
            "--username", "postgres",
            "--dbname", "dingguang",
            "--blobs",
            "--format=custom",
            "--no-password",
            "--file", "/Users/t/backup/dingguang/dingguang_2026_09_04_08_30.backup"
        ])
    }

    func testPathWithSpacesPassedAsSingleArgument() {
        // 含空格的路径应作为单个 argv 元素传递，无需 shell 转义
        let conn = DatabaseConnection(id: UUID(), name: "my lib", host: "127.0.0.1",
                                      port: 5432, dbname: "dingguang",
                                      username: "postgres", isDefault: false)
        let url = URL(fileURLWithPath: "/Users/t/DaVinci Backups/dingguang/x.backup")
        let args = BackupRunner.makeArguments(connection: conn, fileURL: url)
        XCTAssertTrue(args.contains("/Users/t/DaVinci Backups/dingguang/x.backup"))
        XCTAssertEqual(args.last, "/Users/t/DaVinci Backups/dingguang/x.backup")
    }

    func testBackupFolderComposition() {
        let conn = DatabaseConnection(id: UUID(), name: "dingguang", host: "127.0.0.1",
                                      port: 5432, dbname: "dingguang",
                                      username: "postgres", isDefault: true)
        let job = BackupJob(id: UUID(), connectionId: conn.id,
                            backupPath: "/Users/t/DaVinciBackups",
                            intervalSecs: 3600, keepCount: 10, enabled: true)
        let folder = BackupRunner.backupFolder(job: job, connection: conn)
        XCTAssertEqual(folder.path, "/Users/t/DaVinciBackups/dingguang")
    }

    func testToolPathDerivation() {
        XCTAssertEqual(ToolPaths.psql(for: "/Library/PostgreSQL/13/bin/pg_dump"),
                       "/Library/PostgreSQL/13/bin/psql")
        XCTAssertEqual(ToolPaths.pgRestore(for: "/Library/PostgreSQL/13/bin/pg_dump"),
                       "/Library/PostgreSQL/13/bin/pg_restore")
    }
}
