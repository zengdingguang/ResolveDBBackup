import Foundation
import SwiftUI
import Network

/// 应用核心状态：连接管理、备份任务、历史、调度协调。@MainActor 上运行。
@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig
    @Published var history: [BackupRecord]
    @Published var busyJobIDs: Set<UUID> = []
    @Published var statusMessage: String?
    /// 最近一次本机扫描结果（GUI 选择导入用）。
    @Published var discoveredResults: [DiscoveredDatabase] = []
    @Published var isScanning = false
    /// v1.6.7 连接状态灯：key=连接 id，value=true=在线（本地库恒 true）。
    @Published var connectionStatuses: [UUID: Bool] = [:]

    private let store = ConfigStore()
    private let schedule = ScheduleManager()
    /// v1.6.7 系统网络监听（网线/Wi-Fi 断开即时置红）。
    private var pathMonitor: NWPathMonitor?
    /// v1.6.7 定时轻量探测（每 60s SELECT 1 确认数据库可达）。
    private var statusTimer: Timer?

    init() {
        if let loaded = store.loadConfig() {
            config = loaded
            history = store.loadHistory()
        } else if !store.configExists() {
            // 首次启动：写模板
            let template = AppConfig.makeDefault()
            try? store.saveConfig(template)
            config = template
            history = []
        } else {
            // 配置文件存在但解码失败：绝不覆盖用户配置（避免数据丢失）；
            // 以空配置运行，待用户处理或由扫描重新发现。
            print("⚠️ 配置解码失败，已保留原文件：\(store.configURL.path)")
            config = AppConfig.makeDefault()
            history = []
        }
        // 启动：同步调度 + 请求通知权限 + 同步开机自启 + 启动状态灯监测。
        // 注意：不自动扫描数据库（v1.6.3，避免一打开就弹钥匙串授权窗）；也不批量预读
        // 钥匙串密码（逐个读会触发多个授权弹窗，v1.4.1 修复）。
        Task { @MainActor in
            self.syncAllSchedules()
            await Notifier.requestAuthorization()
            self.syncLaunchAtLogin()
            self.startStatusMonitoring()
        }
    }

    /// v1.7.6：AppState 销毁时清理 Timer 和网络监听，避免资源泄漏。
    deinit {
        statusTimer?.invalidate()
        pathMonitor?.cancel()
    }

    // MARK: - 连接状态监测（v1.6.7）

    /// 启动连接状态灯：NWPathMonitor 监听本机网络（断网即时置红），
    /// 每 60s 定时轻量探测（SELECT 1）确认数据库真实可达。几乎不占内存/连接数。
    private func startStatusMonitoring() {
        // 网络监听：本机断网 → 所有网络库置红；网络恢复 → 立即刷新
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .unsatisfied {
                    for conn in self.config.connections where conn.kind == .network {
                        self.connectionStatuses[conn.id] = false
                    }
                } else {
                    await self.refreshAllConnectionStatuses()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.resolvedbbackup.pathmonitor"))
        pathMonitor = monitor

        // 定时探测：每 60 秒对所有网络库跑一次 SELECT 1
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAllConnectionStatuses() }
        }
        statusTimer = timer

        // 初始刷新
        Task { @MainActor in await refreshAllConnectionStatuses() }
    }

    /// 刷新全部连接状态。本地库恒在线；网络库轻量探测（并发执行，避免多个
    /// 不可达库串行等待超时拖慢反馈）。v1.6.7 优化。
    func refreshAllConnectionStatuses() async {
        let conns = config.connections
        let pgPath = config.settings.pgDumpPath
        // 先在主线程统一取密码（Keychain 读取不弹窗），避免在并发闭包里访问 MainActor
        let pw: [UUID: String] = Dictionary(uniqueKeysWithValues: conns.map { ($0.id, password(for: $0.id)) })
        var results: [(UUID, Bool)] = []
        await withTaskGroup(of: (UUID, Bool).self) { group in
            for conn in conns {
                group.addTask {
                    switch conn.kind {
                    case .local:
                        return (conn.id, true)
                    case .network:
                        let pass = pw[conn.id] ?? ""
                        let (ok, _) = await BackupRunner.testConnection(
                            connection: conn, password: pass, pgDumpPath: pgPath)
                        return (conn.id, ok)
                    }
                }
            }
            for await r in group {
                results.append(r)
            }
        }
        for (id, ok) in results {
            connectionStatuses[id] = ok
        }
    }

    /// 意见6：开机自启默认开启——settings 默认 true，缺登录项时自动注册。
    private func syncLaunchAtLogin() {
        if config.settings.launchAtLogin, !schedule.loginItemEnabled() {
            setLaunchAtLogin(true)
        }
    }

    // MARK: - 访问器

    func connection(for id: UUID) -> DatabaseConnection? {
        config.connections.first { $0.id == id }
    }
    func password(for connectionID: UUID) -> String {
        KeychainService.getString(account: connectionID.uuidString) ?? ""
    }
    /// v1.6.5 全局备份间隔（分钟）。
    var globalIntervalSecs: Int {
        max(config.settings.backupIntervalMinutes, 1) * 60
    }
    /// v1.6.5 全局备份位置实际值。
    var globalBackupRoot: String {
        AppSettings.effectiveRoot(config.settings.backupRoot)
    }
    /// pg_dump 所在 bin 目录（psql/pg_isready 同目录）。
    private var pgToolDir: String {
        (config.settings.pgDumpPath as NSString).deletingLastPathComponent
    }
    func nextRun(for job: BackupJob) -> Date? {
        guard job.enabled else { return nil }
        if let last = job.lastRun { return last.addingTimeInterval(TimeInterval(globalIntervalSecs)) }
        return Date().addingTimeInterval(TimeInterval(globalIntervalSecs))
    }
    func save() {
        try? store.saveConfig(config)
        autoSaveConfigSnapshot()
    }

    /// 把配置 JSON 实时同步到全局备份根目录（建议外接硬盘），
    /// 用户每次改动配置后该文件自动更新，便于换机/恢复。
    private func autoSaveConfigSnapshot() {
        let root = globalBackupRoot
        let dir = URL(fileURLWithPath: root, isDirectory: true)
        let file = dir.appendingPathComponent("ResolveDBBackup-config.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = exportConfig() {
                try data.write(to: file, options: .atomic)
            }
        } catch {
            // 外接盘未挂载/无权限等场景静默跳过，不影响主配置保存
        }
    }
    var executablePath: String {
        Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
    }

    // MARK: - 连接管理

    @discardableResult
    func addConnection(name: String, host: String, port: Int, dbname: String,
                       username: String, password: String,
                       kind: ConnectionKind = .network, localPath: String? = nil) -> DatabaseConnection {
        let c = DatabaseConnection(id: UUID(), name: name, host: host, port: port,
                                   dbname: dbname, username: username,
                                   isDefault: config.connections.isEmpty,
                                   kind: kind, localPath: localPath)
        if kind == .network {
            try? KeychainService.setString(password, account: c.id.uuidString)
        }
        config.connections.append(c)
        save()
        return c
    }

    /// 手动添加本地数据库（路径形式）。
    @discardableResult
    func addLocalDatabase(name: String, path: String) -> DatabaseConnection {
        addConnection(name: name, host: "", port: 5432, dbname: "",
                      username: "postgres", password: "", kind: .local, localPath: path)
    }

    func updateConnection(_ c: DatabaseConnection, password: String?) {
        if let idx = config.connections.firstIndex(where: { $0.id == c.id }) {
            config.connections[idx] = c
        }
        if let password, !password.isEmpty {
            try? KeychainService.setString(password, account: c.id.uuidString)
        }
        save()
        syncAllSchedules()
    }

    func deleteConnection(_ c: DatabaseConnection) {
        if let job = config.jobs.first(where: { $0.connectionId == c.id }) {
            schedule.removeJob(jobID: job.id)
            config.jobs.removeAll { $0.id == job.id }
        }
        config.connections.removeAll { $0.id == c.id }
        KeychainService.delete(account: c.id.uuidString)
        save()
        syncAllSchedules()
    }

    func testConnection(_ c: DatabaseConnection) async -> String {
        switch c.kind {
        case .network:
            let r = await BackupRunner.testConnection(
                connection: c,
                password: password(for: c.id),
                pgDumpPath: config.settings.pgDumpPath)
            return r.message
        case .local:
            return BackupRunner.validateLocalPath(c.localPath ?? "").message
        }
    }

    // MARK: - 自动发现

    private func existingKeys() -> Set<String> {
        Set(config.connections.map(ConnectionImporter.dedupKey))
    }

    private func runScan(_ work: () async -> [DiscoveredDatabase]) async -> [DiscoveredDatabase] {
        isScanning = true
        defer { isScanning = false }
        let found = await work()
        discoveredResults = found
        return found
    }

    /// 扫描本机 PostgreSQL（本机网络数据库）。
    func scanLocalNetworkNow() async -> [DiscoveredDatabase] {
        await runScan {
            await ConnectionScanner.scanLocal(existing: existingKeys(), preferredToolDir: pgToolDir)
        }
    }

    /// 扫描局域网网络数据库：默认自动全扫本机 /24 网段 + 手动追加 IP/CIDR。
    func scanLANNow(includeSubnet: Bool = true, manualTargets: [String] = []) async -> [DiscoveredDatabase] {
        var targets: [String] = []
        if includeSubnet {
            for subnet in LANScanner.localSubnets() {
                targets.append(contentsOf: LANScanner.subnetHosts(subnet))
            }
        }
        targets.append(contentsOf: LANScanner.expandTargets(manualTargets))
        targets = Array(Set(targets)).sorted()
        let extraCreds = LocalDBScanner.networkCredentialEntries().map { ($0.username, $0.password) }
        return await runScan {
            await LANScanner.scanLAN(targets: targets, existing: existingKeys(),
                                     preferredToolDir: pgToolDir, extraCredentials: extraCreds)
        }
    }

    /// 扫描达芬奇本地数据库（读 dblist.conf + 官方默认目录）。
    func scanLocalDatabasesNow() async -> [DiscoveredDatabase] {
        await runScan {
            await LocalDBScanner.scanLocalDatabases(existing: existingKeys())
        }
    }

    /// v1.6.3：自动扫描 = 本机共享数据库 + 达芬奇本地数据库（不扫局域网，避免大范围网络探测）。
    /// 由连接页「自动扫描数据库」按钮手动触发。
    func scanAutoNow() async -> [DiscoveredDatabase] {
        await runScan {
            let network = await ConnectionScanner.scanLocal(existing: existingKeys(),
                                                            preferredToolDir: pgToolDir)
            let locals = await LocalDBScanner.scanLocalDatabases(existing: existingKeys())
            return network + locals
        }
    }

    /// 把扫描结果导入为连接（可选创建默认任务）。返回新增连接数。
    @discardableResult
    func addDiscovered(_ items: [DiscoveredDatabase], createJobs: Bool) -> Int {
        let added = ConnectionImporter.applyDiscovered(items, to: &config, createJobs: createJobs,
                                                       globalDefault: globalBackupRoot,
                                                       intervalSeconds: globalIntervalSecs)
        if added > 0 {
            save()
            syncAllSchedules()
            statusMessage = "已添加 \(added) 个连接" + (createJobs ? "（含默认备份任务）" : "")
        } else {
            statusMessage = "所选数据库已在列表中"
        }
        return added
    }

    // MARK: - 任务管理

    /// v1.6.5 添加任务：用全局备份位置与全局间隔创建（不再按库填路径/间隔）。
    func addJob(connectionID: UUID) {
        guard !config.jobs.contains(where: { $0.connectionId == connectionID }) else { return }
        let job = BackupJob(id: UUID(), connectionId: connectionID,
                            backupPath: globalBackupRoot,
                            intervalSecs: globalIntervalSecs,
                            keepCount: 100,
                            enabled: true)
        config.jobs.append(job)
        save()
        syncAllSchedules()
    }

    func updateJob(_ job: BackupJob) {
        if let idx = config.jobs.firstIndex(where: { $0.id == job.id }) {
            config.jobs[idx] = job
        }
        save()
        syncAllSchedules()
    }

    func setJobEnabled(_ job: BackupJob, enabled: Bool) {
        var updated = job
        updated.enabled = enabled
        updateJob(updated)
    }

    func deleteJob(_ job: BackupJob) {
        schedule.removeJob(jobID: job.id)
        config.jobs.removeAll { $0.id == job.id }
        save()
        syncAllSchedules()
    }

    // MARK: - 备份执行

    func backupNow(jobID: UUID) async {
        guard let job = config.jobs.first(where: { $0.id == jobID }) else { return }
        guard let conn = connection(for: job.connectionId) else { return }
        guard !busyJobIDs.contains(jobID) else { return }
        busyJobIDs.insert(jobID)
        defer { busyJobIDs.remove(jobID) }

        let outcome: BackupOutcome
        switch conn.kind {
        case .network:
            outcome = await BackupRunner.runBackup(
                connection: conn, root: globalBackupRoot,
                password: password(for: conn.id),
                pgDumpPath: config.settings.pgDumpPath)
        case .local:
            outcome = await BackupRunner.runLocalBackup(connection: conn, root: globalBackupRoot)
        }

        var finalFileURL = outcome.fileURL
        if outcome.success, let url = outcome.fileURL {
            finalFileURL = url
            // v1.6.6 时间机器式保留：最近 24 小时内全部保留，超过 24 小时每天保留 1 份
            let folder = URL(fileURLWithPath: globalBackupRoot)
                .appendingPathComponent(conn.name, isDirectory: true)
            RetentionManager.apply24hDaily(folder: folder)
        }

        let record = BackupRecord(
            id: UUID(), jobId: job.id, connectionName: conn.name, dbname: conn.dbname,
            date: Date(), success: outcome.success,
            filePath: finalFileURL?.path,
            sizeBytes: outcome.success ? outcome.sizeBytes : nil,
            duration: outcome.duration, error: outcome.message)
        history.insert(record, at: 0)
        if history.count > 500 { history = Array(history.prefix(500)) }
        if let idx = config.jobs.firstIndex(where: { $0.id == job.id }) {
            config.jobs[idx].lastRun = Date()
        }
        save()

        if outcome.success {
            statusMessage = "\(conn.name)：备份成功 \(finalFileURL?.lastPathComponent ?? "")"
            if config.settings.notifyOnSuccess {
                await Notifier.notify(title: "水螅ResolveBackup · 备份成功",
                                      body: "\(conn.name)：\(finalFileURL?.lastPathComponent ?? "")")
            }
        } else {
            statusMessage = "\(conn.name)：备份失败 - \(outcome.message ?? "未知错误")"
            if config.settings.notifyOnFailure {
                await Notifier.notify(title: "水螅ResolveBackup · 备份失败",
                                      body: "\(conn.name)：\(outcome.message ?? "未知错误")")
            }
        }
    }

    /// 全部启用任务并行执行；单库失败不阻断其他库。
    /// v1.7.6：限制最多同时 4 个备份任务，避免过多 pg_dump 进程导致系统资源紧张。
    func backupAll() async {
        let jobs = config.jobs.filter { $0.enabled }
        let maxConcurrent = min(4, max(jobs.count, 1))
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            for job in jobs {
                if active >= maxConcurrent {
                    await group.next()
                    active -= 1
                }
                group.addTask { await self.backupNow(jobID: job.id) }
                active += 1
            }
        }
    }

    // MARK: - 调度

    func syncAllSchedules() {
        schedule.syncAll(jobs: config.jobs, intervalSeconds: globalIntervalSecs,
                         executablePath: executablePath)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        config.settings.launchAtLogin = enabled
        save()
        do {
            statusMessage = try schedule.setLoginItem(enabled: enabled, executablePath: executablePath)
        } catch {
            statusMessage = "开机自启设置失败：\(error.localizedDescription)"
        }
    }

    func loginItemEnabled() -> Bool {
        config.settings.launchAtLogin || schedule.loginItemEnabled()
    }

    // MARK: - 导入/导出

    func exportConfig() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(config)
    }

    func importConfig(data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cfg = try? decoder.decode(AppConfig.self, from: data) else { return false }
        config = cfg
        save()
        syncAllSchedules()
        return true
    }
}
