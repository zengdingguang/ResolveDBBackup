// ResolveDBBackup 单元测试运行器（不依赖 XCTest，可在仅有 Command Line Tools 的机器上运行）。
// 用法: swift run ResolveDBBackupSelfTests
import Foundation
@testable import ResolveDBBackupCore

// MARK: - 迷你断言

private var passed = 0
private var failed = 0
private var currentSuite = ""

private func suite(_ name: String) {
    currentSuite = name
    print("\n== \(name) ==")
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String,
                   file: String = #filePath, line: Int = #line) {
    if condition() {
        passed += 1
    } else {
        failed += 1
        print("  ✗ [\(currentSuite)] \(message)  (\(URL(fileURLWithPath: file).lastPathComponent):\(line))")
    }
}

private func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String,
                                      file: String = #filePath, line: Int = #line) {
    check(a == b, "\(message)（期望 \(b)，实际 \(a)）", file: file, line: line)
}

private func checkContains(_ haystack: [String], _ needle: String, _ message: String,
                           file: String = #filePath, line: Int = #line) {
    check(haystack.contains(needle), "\(message)（缺少 \(needle)）", file: file, line: line)
}

// MARK: - 命令拼装

suite("命令拼装")
do {
    let conn = DatabaseConnection(id: UUID(), name: "dingguang", host: "127.0.0.1",
                                  port: 5432, dbname: "dingguang", username: "postgres", isDefault: true)
    let url = URL(fileURLWithPath: "/Users/t/backup/dingguang/dingguang_2026_09_04_08_30.backup")
    let args = BackupRunner.makeArguments(connection: conn, fileURL: url)
    checkEqual(args, [
        "--host", "127.0.0.1", "--port", "5432", "--username", "postgres",
        "--dbname", "dingguang", "--blobs", "--format=custom", "--no-password",
        "--file", "/Users/t/backup/dingguang/dingguang_2026_09_04_08_30.backup"
    ], "pg_dump 参数拼装")
    checkEqual(args.last, "/Users/t/backup/dingguang/dingguang_2026_09_04_08_30.backup", "file 参数在最后")

    // 含空格的路径作为单个 argv 传递，无需 shell 转义
    let conn2 = DatabaseConnection(id: UUID(), name: "my lib", host: "127.0.0.1",
                                   port: 5432, dbname: "dingguang", username: "postgres", isDefault: false)
    let url2 = URL(fileURLWithPath: "/Users/t/DaVinci Backups/dingguang/x.backup")
    checkEqual(BackupRunner.makeArguments(connection: conn2, fileURL: url2).last,
               "/Users/t/DaVinci Backups/dingguang/x.backup", "含空格路径单参数")

    checkEqual(BackupRunner.backupFolder(root: "/Users/t/DaVinciBackups", connection: conn).path,
               "/Users/t/DaVinciBackups/dingguang", "备份目录 {全局根}/{connectionName}")

    checkEqual(ToolPaths.psql(for: "/Library/PostgreSQL/13/bin/pg_dump"),
               "/Library/PostgreSQL/13/bin/psql", "psql 同目录推导")
    checkEqual(ToolPaths.pgRestore(for: "/Library/PostgreSQL/13/bin/pg_dump"),
               "/Library/PostgreSQL/13/bin/pg_restore", "pg_restore 同目录推导")
}

// MARK: - 保留策略

suite("保留策略（时间机器式：24h 内全留 / 超 24h 每天 1 份）")
do {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("selftest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    func makeFile(_ name: String, hoursAgo: Double, bytes: Int = 1) throws {
        let url = folder.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0x78, count: bytes))
        let date = Date().addingTimeInterval(-hoursAgo * 3600)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
    func keptNames(_ result: (kept: [URL], deleted: [URL])) -> Set<String> {
        Set(result.kept.map { $0.lastPathComponent })
    }

    // 1) 24 小时内全保留；超过 24 小时按天每天 1 份（该天最后一份）
    try makeFile("f1_20m.backup", hoursAgo: 0.2)  // 24h 内 → 保留
    try makeFile("f2_5h.backup", hoursAgo: 5)     // 24h 内 → 保留
    try makeFile("f3_10h.backup", hoursAgo: 10)   // 24h 内 → 保留
    try makeFile("f4_30h.backup", hoursAgo: 30)   // 昨天 → 该天最后一份（保留）
    try makeFile("f5_34h.backup", hoursAgo: 34)   // 昨天同天、更早 → 删除
    try makeFile("f6_50h.backup", hoursAgo: 50)   // 前天 → 保留
    try makeFile("f7_80h.backup", hoursAgo: 80)   // 3 天前 → 保留（每天 1 份）
    var r = RetentionManager.apply24hDaily(folder: folder)
    checkEqual(r.kept.count, 6, "保留 6 份（24h 内 3 + 每天 3）")
    check(keptNames(r).contains("f1_20m.backup"), "24h 内保留")
    check(keptNames(r).contains("f2_5h.backup"), "24h 内保留(2)")
    check(keptNames(r).contains("f3_10h.backup"), "24h 内保留(3)")
    check(keptNames(r).contains("f4_30h.backup"), "昨天保留该天最后一份")
    check(!keptNames(r).contains("f5_34h.backup"), "昨天同天更早的被清理")
    check(keptNames(r).contains("f6_50h.backup"), "前天保留")
    check(keptNames(r).contains("f7_80h.backup"), "3 天前保留（每天 1 份）")

    // 2) 空目录
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    r = RetentionManager.apply24hDaily(folder: folder)
    check(r.kept.isEmpty && r.deleted.isEmpty, "空目录无操作")

    // 3) 0 字节残留清理（即使 24h 窗口内）
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try makeFile("good_10m.backup", hoursAgo: 0.1, bytes: 5)
    let zeroURL = folder.appendingPathComponent("broken.backup")
    FileManager.default.createFile(atPath: zeroURL.path, contents: Data())
    r = RetentionManager.apply24hDaily(folder: folder)
    checkEqual(r.kept.count, 1, "0 字节文件被清理")
    check(!FileManager.default.fileExists(atPath: zeroURL.path), "0 字节文件已删除")

    // 默认任务（全局间隔 10 分钟 → 600s；保留 100 份字段兼容保留）
    let djob = ConnectionImporter.defaultJob(connectionID: UUID())
    checkEqual(djob.keepCount, 100, "默认任务保留 100 份（字段兼容）")
    check(djob.backupPath.contains("DaVinci Database Auto Backup"), "默认根目录为 DaVinci Database Auto Backup")

    // 5) 按月归档（字段保留兼容）
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var arch = RetentionPolicy(); arch.monthlyArchive = true
    let file = folder.appendingPathComponent("db_2026_09_04_08_30.backup")
    FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
    let moved = RetentionManager.archiveIfNeeded(fileURL: file, policy: arch)
    check(moved.path != file.path && moved.path.contains("2026-09"), "归档移动到 YYYY-MM 子目录")
    check(FileManager.default.fileExists(atPath: moved.path), "归档后文件存在")

    // 6) 命名格式
    let fmt = BackupNaming.dateFormatter
    fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
    let date = fmt.date(from: "2026_09_04_08_30")!
    checkEqual(BackupNaming.fileName(dbname: "dingguang", date: date),
               "dingguang_2026_09_04_08_30.backup", "时间戳文件名")

    // 7) 0 字节残留文件始终被清理（即使策略全关闭）
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let zero = folder.appendingPathComponent("db_zero.backup")
    FileManager.default.createFile(atPath: zero.path, contents: Data())
    let good = folder.appendingPathComponent("db_good.backup")
    FileManager.default.createFile(atPath: good.path, contents: Data("x".utf8))
    r = RetentionManager.apply24hDaily(folder: folder)
    check(!FileManager.default.fileExists(atPath: zero.path), "0 字节残留被清理")
    check(FileManager.default.fileExists(atPath: good.path), "正常文件保留")
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let first = BackupRunner.resolveUniqueFileURL(folder: folder, dbname: "dingguang", date: date)
    FileManager.default.createFile(atPath: first.path, contents: Data("1".utf8))
    let second = BackupRunner.resolveUniqueFileURL(folder: folder, dbname: "dingguang", date: date)
    checkEqual(second.lastPathComponent, "dingguang_2026_09_04_08_30_2.backup", "冲突追加 _2 后缀")
    FileManager.default.createFile(atPath: second.path, contents: Data("2".utf8))
    let third = BackupRunner.resolveUniqueFileURL(folder: folder, dbname: "dingguang", date: date)
    checkEqual(third.lastPathComponent, "dingguang_2026_09_04_08_30_3.backup", "冲突追加 _3 后缀")
}

// MARK: - 配置序列化

suite("配置序列化")
do {
    let config = AppConfig.makeDefault()
    checkEqual(config.connections.count, 0, "默认模板无硬编码连接（改为自动发现）")
    checkEqual(config.jobs.count, 0, "默认模板无硬编码任务")
    checkEqual(config.settings.pgDumpPath, "/Library/PostgreSQL/13/bin/pg_dump", "默认 pg_dump 路径")
    checkEqual(config.settings.retention.monthlyArchive, false, "默认按月归档关闭")

    // round-trip
    var cfg = config
    cfg.settings.notifyOnSuccess = true
    cfg.settings.retention.keepDays30 = 5
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(cfg)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(AppConfig.self, from: data)
    checkEqual(decoded, cfg, "配置 round-trip")
    checkEqual(decoded.settings.retention.keepDays30, 5, "round-trip 保留天数")

    // job 带 lastRun round-trip
    var job = BackupJob(id: UUID(), connectionId: UUID(), backupPath: "/Users/t/DaVinciBackups",
                        intervalSecs: 1800, keepCount: 5, enabled: false)
    job.lastRun = Date(timeIntervalSince1970: 1_700_000_000)
    let jData = try encoder.encode(job)
    let jDecoded = try decoder.decode(BackupJob.self, from: jData)
    checkEqual(jDecoded, job, "任务 round-trip（含 lastRun）")
    checkEqual(jDecoded.lastRun, job.lastRun, "lastRun 保留")

    // 记录 round-trip（日期取整秒，ISO8601 无损）
    let record = BackupRecord(id: UUID(), jobId: UUID(), connectionName: "dingguang",
                              dbname: "dingguang", date: Date(timeIntervalSince1970: 1_700_000_123),
                              success: false, filePath: nil, sizeBytes: nil,
                              duration: 12.5, error: "connection refused")
    let rData = try encoder.encode(record)
    let rDecoded = try decoder.decode(BackupRecord.self, from: rData)
    checkEqual(rDecoded, record, "记录 round-trip")

    // pgpass 行格式
    let conn = DatabaseConnection(id: UUID(), name: "dingguang", host: "127.0.0.1",
                                  port: 5432, dbname: "dingguang", username: "postgres", isDefault: true)
    checkEqual(PgpassManager.line(for: conn, password: "DaVinci"),
               "127.0.0.1:5432:dingguang:postgres:DaVinci", "pgpass 行格式")
}

// MARK: - dblist 解析

suite("dblist 解析")
do {
    let sample = """
    Local Database:/Users/macstudio/Library/Application Support/Blackmagic Design/DaVinci Resolve/Resolve Project Library:*:::DISK
    2025X192.168.3.99:192.168.3.99:postgres:DaVinci:2025X:QPSQL
    dingguang127.0.0.1:127.0.0.1:postgres:DaVinci:dingguang:QPSQL

    # 注释行应跳过
    """
    let entries = LocalDBScanner.parseDblist(sample)
    checkEqual(entries.count, 3, "解析出 3 条")
    let locals = entries.filter { $0.kind == .local }
    let nets = entries.filter { $0.kind == .network }
    checkEqual(locals.count, 1, "1 条本地库")
    checkEqual(locals[0].name, "Local Database", "本地库名")
    check(locals[0].localPath.hasSuffix("Resolve Project Library"), "本地库路径")
    checkEqual(nets.count, 2, "2 条网络库")
    checkEqual(nets[0].name, "2025X", "网络库名（去掉 host 后缀）")
    checkEqual(nets[0].host, "192.168.3.99", "网络库 host")
    checkEqual(nets[0].username, "postgres", "网络库用户")
    checkEqual(nets[0].password, "DaVinci", "网络库密码（dblist 明文）")
    checkEqual(nets[0].dbname, "2025X", "网络库 dbname")
    checkEqual(nets[1].name, "dingguang", "第二网络库名")
    checkEqual(nets[1].host, "127.0.0.1", "第二网络库 host")
}

// MARK: - 局域网 IP 展开

suite("局域网 IP 展开")
do {
    checkEqual(LANScanner.isIPv4("192.168.3.99"), true, "合法 IPv4")
    checkEqual(LANScanner.isIPv4("192.168.3.999"), false, "越界 IP 非法")
    checkEqual(LANScanner.isIPv4("abc"), false, "非 IP 非法")
    checkEqual(LANScanner.subnet24(of: "192.168.3.55"), "192.168.3.0/24", "/24 推导")
    checkEqual(LANScanner.subnetHosts("192.168.3.0/24").count, 254, "/24 主机数")
    checkEqual(LANScanner.subnetHosts("192.168.3.0/24").first, "192.168.3.1", "/24 首主机")
    checkEqual(LANScanner.subnetHosts("192.168.3.0/24").last, "192.168.3.254", "/24 末主机")
    checkEqual(LANScanner.expandTargets(["192.168.3.99"]), ["192.168.3.99"], "单 IP 展开")
    let cidr = LANScanner.cidrHosts("192.168.3.0/24")
    checkEqual(cidr?.count, 254, "CIDR /24 展开")
    check(cidr?.contains("192.168.3.99") == true, "CIDR 含目标主机")
    checkEqual(LANScanner.cidrHosts("10.0.0.0/30")?.count, 2, "CIDR /30 展开 2 台可用")
    checkEqual(LANScanner.cidrHosts("192.168.0.0/8"), nil, "过大网段拒绝")
    checkEqual(LANScanner.cidrHosts("bad/24"), nil, "非法 CIDR")
    checkEqual(LANScanner.expandTargets(["192.168.1.1", "192.168.2.0/30"]),
               ["192.168.1.1", "192.168.2.1", "192.168.2.2"], "混合展开去重排序")
}

// MARK: - 本地库快照命名与保留

suite("本地库快照")
do {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("rdb_snapshot_test_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let date = BackupNaming.dateFormatter.date(from: "2026_09_04_08_30") ?? Date()
    let z1 = BackupRunner.resolveUniqueZipURL(folder: folder, name: "Local Database", date: date)
    checkEqual(z1.lastPathComponent, "Local Database_2026_09_04_08_30.zip", "zip 命名")
    FileManager.default.createFile(atPath: z1.path, contents: Data("1".utf8))
    let z2 = BackupRunner.resolveUniqueZipURL(folder: folder, name: "Local Database", date: date)
    checkEqual(z2.lastPathComponent, "Local Database_2026_09_04_08_30_2.zip", "zip 冲突加 _2")
    FileManager.default.createFile(atPath: z2.path, contents: Data("2".utf8))

    // RetentionManager 同时处理 .backup 与 .zip
    let backupURL = folder.appendingPathComponent("db_2026_09_04_08_31.backup")
    FileManager.default.createFile(atPath: backupURL.path, contents: Data("b".utf8))
    let files = RetentionManager.backupFiles(in: folder)
    checkEqual(files.count, 3, "backup+zip 都被识别")
    let keep = RetentionManager.apply24hDaily(folder: folder)
    checkEqual(keep.kept.count, 3, "24h 内全部保留")
}

// MARK: - 旧配置迁移

suite("旧配置迁移")
do {
    // v1.0/v1.1 旧格式（真实落盘格式）：含 schemaVersion，连接无 kind/localPath 字段
    let oldJSON = """
    {"schemaVersion":1,"connections":[{"id":"11111111-1111-1111-1111-111111111111","name":"2025X","host":"192.168.3.99","port":5432,"dbname":"2025X","username":"postgres","isDefault":true},{"id":"22222222-2222-2222-2222-222222222222","name":"dingguang","host":"127.0.0.1","port":5432,"dbname":"dingguang","username":"postgres","isDefault":false}],
    "jobs":[{"id":"33333333-3333-3333-3333-333333333333","connectionId":"11111111-1111-1111-1111-111111111111","backupPath":"/Users/t/DaVinciBackups","intervalSecs":3600,"keepCount":10,"enabled":true}],
    "settings":{"pgDumpPath":"/Library/PostgreSQL/13/bin/pg_dump","retention":{"keepDays7":0,"keepDays30":0,"keepDays90":0,"monthlyArchive":false},"launchAtLogin":false,"notifyOnFailure":true,"notifyOnSuccess":false,"syncToPgpass":false}}
    """
    let data = oldJSON.data(using: .utf8)!
    do {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let cfg = try decoder.decode(AppConfig.self, from: data)
        checkEqual(cfg.connections.count, 2, "旧配置解码连接数")
        checkEqual(cfg.connections[0].kind, .network, "旧连接默认 network")
        checkEqual(cfg.connections[0].name, "2025X", "旧连接 2025X 保留")
        checkEqual(cfg.jobs.count, 1, "旧配置解码任务数")
        checkEqual(cfg.settings.pgDumpPath, "/Library/PostgreSQL/13/bin/pg_dump", "旧配置设置保留")
        checkEqual(cfg.settings.backupIntervalMinutes, 10, "旧配置回退全局间隔 10 分钟")
        checkEqual(cfg.settings.hourlyRetentionHours, 1, "旧配置回退小时保留 1")
        checkEqual(cfg.settings.dailyRetentionDays, 1, "旧配置回退天保留 1")
    } catch {
        failed += 1
        print("  ✗ [旧配置迁移] 解码失败: \(error)")
    }

    // 无 schemaVersion 的配置（更早版本）也应能解码
    let oldNoVer = """
    {"connections":[{"id":"44444444-4444-4444-4444-444444444444","name":"dingguang","host":"127.0.0.1","port":5432,"dbname":"dingguang","username":"postgres","isDefault":true}],
    "jobs":[],"settings":{"pgDumpPath":"/Library/PostgreSQL/13/bin/pg_dump","retention":{},"launchAtLogin":false,"notifyOnFailure":true,"notifyOnSuccess":false,"syncToPgpass":false}}
    """
    do {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let cfg2 = try decoder.decode(AppConfig.self, from: oldNoVer.data(using: .utf8)!)
        checkEqual(cfg2.connections.count, 1, "无 schemaVersion 配置解码")
        checkEqual(cfg2.connections[0].kind, .network, "无 schemaVersion 连接默认 network")
    } catch {
        failed += 1
        print("  ✗ [旧配置迁移] 无 schemaVersion 解码失败: \(error)")
    }
}

// MARK: - 自动发现导入

suite("自动发现导入")
do {
    // 唯一命名
    checkEqual(ConnectionImporter.uniqueName(base: "dingguang", existing: []), "dingguang", "无冲突原名")
    checkEqual(ConnectionImporter.uniqueName(base: "dingguang", existing: ["dingguang"]), "dingguang (2)", "重名加 (2)")
    checkEqual(ConnectionImporter.uniqueName(base: "dingguang", existing: ["dingguang", "dingguang (2)"]),
               "dingguang (3)", "重名递增")

    // 默认任务（v1.6.5 全局间隔 10 分钟 → 600s）
    let job = ConnectionImporter.defaultJob(connectionID: UUID())
    checkEqual(job.intervalSecs, 600, "默认任务间隔 600s（全局 10 分钟）")
    checkEqual(job.keepCount, 100, "默认任务保留 100 份")
    check(job.enabled, "默认任务启用")

    // 导入：去重 + 命名 + 建任务 + isDefault
    var cfg = AppConfig.makeDefault()
    let existing = DatabaseConnection(id: UUID(), name: "dingguang", host: "127.0.0.1",
                                      port: 5432, dbname: "dingguang", username: "postgres",
                                      isDefault: true)
    cfg.connections.append(existing)
    // 预置一个会与其冲突的 keychain 条目以保持命名可测（实际导入会写 keychain）
    let items = [
        DiscoveredDatabase(host: "127.0.0.1", port: 5432, dbname: "dingguang",
                           username: "postgres", password: "DaVinci"),  // 已存在 → 跳过
        DiscoveredDatabase(host: "127.0.0.1", port: 5432, dbname: "cee",
                           username: "postgres", password: "DaVinci"),
        DiscoveredDatabase(host: "127.0.0.1", port: 5432, dbname: "cee",
                           username: "postgres", password: "DaVinci"),  // 与上重复（同 id）→ 跳过
        DiscoveredDatabase(host: "192.168.3.99", port: 5432, dbname: "dingguang",
                           username: "postgres", password: "DaVinci"),  // 同库名不同主机 → 命名加后缀
    ]
    let added = ConnectionImporter.applyDiscovered(items, to: &cfg, createJobs: true)
    checkEqual(added, 2, "只新增 2 个（去重）")
    checkEqual(cfg.connections.count, 3, "连接总数 3")
    checkEqual(cfg.jobs.count, 2, "新增 2 个默认任务")
    checkEqual(cfg.connections.map(\.name), ["dingguang", "cee", "dingguang (2)"], "命名正确")
    check(cfg.connections[2].isDefault == false, "后续连接非默认")
    // 每个新导入连接都有默认任务（旧连接 dingguang 无任务）
    let importedIDs = Set(cfg.connections.filter { $0.name != "dingguang" }.map(\.id))
    checkEqual(Set(cfg.jobs.map(\.connectionId)), importedIDs, "每个新连接都有默认任务")

    // 清理测试写入的 keychain（按导入时生成的连接 id）
    for c in cfg.connections where c.name != "dingguang" {
        KeychainService.delete(account: c.id.uuidString)
    }

    // 本地库导入
    var cfg2 = AppConfig.makeDefault()
    let localItems = [
        DiscoveredDatabase(kind: .local, dbname: "Local Database",
                           localPath: "/Users/t/Resolve Project Library")
    ]
    let addedLocal = ConnectionImporter.applyDiscovered(localItems, to: &cfg2, createJobs: true)
    checkEqual(addedLocal, 1, "本地库导入 1 个")
    checkEqual(cfg2.connections.count, 1, "本地库连接数")
    checkEqual(cfg2.connections[0].kind, .local, "kind 为 local")
    checkEqual(cfg2.connections[0].localPath, "/Users/t/Resolve Project Library", "localPath 保留")
    checkEqual(cfg2.connections[0].dbname, "", "本地库 dbname 为空")
    checkEqual(cfg2.jobs.count, 1, "本地库默认任务")
    let againLocal = ConnectionImporter.applyDiscovered(localItems, to: &cfg2, createJobs: true)
    checkEqual(againLocal, 0, "本地库重复导入跳过")
}

suite("本机网卡枚举（意见4）")
do {
    let ifaces = NetworkInterfaces.list()
    check(!ifaces.isEmpty, "能枚举到至少一个网络接口")
    if let first = ifaces.first {
        check(!first.ip.isEmpty && first.ip.contains("."), "首个接口有 IPv4 地址")
        check(!first.name.isEmpty, "首个接口有名称")
    }
}

// MARK: - 汇总

print("\n========================")
print("通过 \(passed) 项，失败 \(failed) 项")
if failed > 0 {
    print("存在失败断言")
    exit(1)
} else {
    print("全部单元测试通过")
    exit(0)
}
