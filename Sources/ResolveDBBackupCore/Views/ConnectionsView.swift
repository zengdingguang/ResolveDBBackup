import SwiftUI
import AppKit

/// 连接管理：网络数据库（本机/局域网）与达芬奇本地数据库分区块管理。
/// 三类扫描：本机网络库 / 局域网网络库（默认全扫网段 + 手动追加）/ 本地数据库。
struct ConnectionsView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: DatabaseConnection?
    @State private var showAddLocal = false
    @State private var showAddLocalShared = false
    @State private var showAddLanShared = false
    @State private var showScanAuto = false        // v1.6.3：自动扫描（本机共享+本地）
    @State private var showScanLocal = false      // 本机网络库
    @State private var showScanLAN = false        // 局域网网络库
    @State private var showScanResolve = false    // 达芬奇本地库
    @State private var testResults: [UUID: String] = [:]
    @State private var testing: Set<UUID> = []

    private var localConns: [DatabaseConnection] {
        state.config.connections.filter { $0.kind == .local }
    }
    /// 意见1：网络库再分两类——本机共享（指向本机）/ 局域网共享（指向其他主机）。
    private var localSharedConns: [DatabaseConnection] {
        state.config.connections.filter { $0.kind == .network && $0.isLocalShared }
    }
    private var lanSharedConns: [DatabaseConnection] {
        state.config.connections.filter { $0.kind == .network && !$0.isLocalShared }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("数据库连接").font(.title2.bold())
                Spacer()
                // v1.6.3：启动不再自动扫描，改为用户手动点「自动扫描数据库」触发（本机共享+本地，不扫局域网）
                Button("自动扫描数据库") { showScanAuto = true }
                    .help("同时扫描本机共享数据库与达芬奇本地数据库（不含局域网，避免长时间等待）")
                Button("扫描本地数据库") { showScanResolve = true }
                    .help("扫描达芬奇本地数据库（磁盘文件夹，读 dblist.conf 注册表）")
                Button("扫描本机共享数据库") { showScanLocal = true }
                    .help("扫描本机 127.0.0.1 上的 PostgreSQL（网络）数据库")
                Button("扫描局域网共享数据库") { showScanLAN = true }
                    .help("扫描局域网内的 PostgreSQL 数据库（默认全扫本机网段，可手动追加 IP/网段）")
                Menu {
                    Button("添加本地数据库…") { showAddLocal = true }
                    Button("添加本机共享数据库…") { showAddLocalShared = true }
                    Button("添加局域网共享数据库…") { showAddLanShared = true }
                } label: {
                    // v1.6.3：修复"＋"文本与 plus 图标重复的双加号；改名为「手动添加」
                    Label("手动添加", systemImage: "plus")
                }
            }
            .padding()

            if state.config.connections.isEmpty {
                ContentUnavailableView(
                    "还没有数据库连接",
                    systemImage: "externaldrive",
                    description: Text("点击上方扫描按钮自动发现数据库，或手动添加连接。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !localConns.isEmpty {
                        Section {
                            ForEach(localConns) { conn in
                                row(for: conn)
                            }
                        } header: {
                            Text("本地数据库（达芬奇磁盘库）")
                                .padding(.top, 16)  // 意见：加大三类 Section 间距
                        }
                    }
                    if !localSharedConns.isEmpty {
                        Section {
                            ForEach(localSharedConns) { conn in
                                row(for: conn)
                            }
                        } header: {
                            Text("本机共享数据库（PostgreSQL）")
                                .padding(.top, 16)
                        }
                    }
                    if !lanSharedConns.isEmpty {
                        Section {
                            ForEach(lanSharedConns) { conn in
                                row(for: conn)
                            }
                        } header: {
                            Text("局域网共享数据库（PostgreSQL）")
                                .padding(.top, 16)
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { conn in
            ConnectionEditorView(connection: conn) { updated, password in
                state.updateConnection(updated, password: password)
            }
        }
        .sheet(isPresented: $showAddLocal) {
            ConnectionEditorView(connection: nil, kind: .local) { newConn, _ in
                state.addLocalDatabase(name: newConn.name, path: newConn.localPath ?? "")
            }
        }
        .sheet(isPresented: $showAddLocalShared) {
            ConnectionEditorView(connection: nil, kind: .network,
                                 title: "添加本机共享数据库") { newConn, password in
                state.addConnection(name: newConn.name, host: newConn.host, port: newConn.port,
                                    dbname: newConn.dbname, username: newConn.username,
                                    password: password ?? "DaVinci", kind: .network)
            }
        }
        .sheet(isPresented: $showAddLanShared) {
            ConnectionEditorView(connection: nil, kind: .network,
                                 title: "添加局域网共享数据库",
                                 autoHostFromInterface: true) { newConn, password in
                state.addConnection(name: newConn.name, host: newConn.host, port: newConn.port,
                                    dbname: newConn.dbname, username: newConn.username,
                                    password: password ?? "DaVinci", kind: .network)
            }
        }
        .sheet(isPresented: $showScanAuto) {
            ScanResultsView(title: "自动扫描数据库") {
                await state.scanAutoNow()
            }
        }
        .sheet(isPresented: $showScanLocal) {
            ScanResultsView(title: "扫描本机共享数据库") {
                await state.scanLocalNetworkNow()
            }
        }
        .sheet(isPresented: $showScanLAN) {
            LANScanView()
        }
        .sheet(isPresented: $showScanResolve) {
            ScanResultsView(title: "扫描达芬奇本地数据库") {
                await state.scanLocalDatabasesNow()
            }
        }
    }

    private func row(for conn: DatabaseConnection) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conn.name).font(.headline)
                    Text(conn.kind.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    if conn.isDefault {
                        Text("默认")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text(conn.sourceDescription)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let r = testResults[conn.id] {
                Text(r)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(r.hasPrefix("连接成功") || r.hasPrefix("本地库有效")
                                     ? Color.green : Color.red)
            }
            if testing.contains(conn.id) {
                ProgressView().controlSize(.small)
            }
            // v1.6.7 状态灯：连接中=绿、断开/失联=红、未探测=灰；本地库恒绿
            Circle()
                .fill(statusColor(for: conn))
                .frame(width: 10, height: 10)
                .help(statusHelp(for: conn))
            Button("连接测试") {
                Task {
                    testing.insert(conn.id)
                    testResults[conn.id] = await state.testConnection(conn)
                    testing.remove(conn.id)
                }
            }
            Button("编辑") { editing = conn }
            Button("移除") { state.deleteConnection(conn) }
                .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }

    /// v1.6.7 状态灯颜色。
    private func statusColor(for conn: DatabaseConnection) -> Color {
        if conn.kind == .local { return .green }
        switch state.connectionStatuses[conn.id] {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .gray
        }
    }

    /// v1.6.7 状态灯提示。
    private func statusHelp(for conn: DatabaseConnection) -> String {
        if conn.kind == .local { return "本地数据库（磁盘库）" }
        switch state.connectionStatuses[conn.id] {
        case .some(true): return "连接正常"
        case .some(false): return "已断开 / 失联"
        case .none: return "状态未知（等待探测）"
        }
    }
}

/// 通用扫描结果：勾选导入。scanner 由调用方指定（本机网络库 / 本地库）。
struct ScanResultsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let title: String
    let scanner: () async -> [DiscoveredDatabase]
    @State private var selected: Set<String> = []
    @State private var createJobs = true
    @State private var scanning = false

    private var results: [DiscoveredDatabase] { state.discoveredResults }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if scanning { ProgressView().controlSize(.small) }
                // v1.7.0：重新扫描按钮与「添加所选」同款（accent 蓝圆角、默认大小）
                Button("重新扫描") { Task { await runScan() } }
                    .buttonStyle(.borderedProminent)
            }
            DiscoverResultList(results: results, selected: $selected)
            if !results.isEmpty {
                Toggle("为新增连接创建默认备份任务（按全局备份机制）", isOn: $createJobs)
            }
            HStack {
                Button("全选") { selected = Set(results.map(\.id)) }
                    .disabled(results.isEmpty)
                Button("全不选") { selected.removeAll() }
                    .disabled(results.isEmpty)
                Spacer()
                Button("取消") { dismiss() }
                Button(results.isEmpty ? "关闭" : "添加所选（\(selected.count)）") {
                    if !selected.isEmpty {
                        let items = results.filter { selected.contains($0.id) }
                        state.addDiscovered(items, createJobs: createJobs)
                    }
                    dismiss()
                }
                .disabled(results.isEmpty)
                .keyboardShortcut(.defaultAction)
                // v1.7.0：与「重新扫描」同款蓝色圆角
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 560, height: results.isEmpty ? 300 : 480)
        .onAppear {
            if results.isEmpty { Task { await runScan() } }
            selected = Set(results.map(\.id))
        }
    }

    private func runScan() async {
        scanning = true
        let found = await scanner()
        selected = Set(found.map(\.id))
        scanning = false
    }
}

/// 局域网扫描面板：默认全扫网段 + 手动追加 IP/CIDR。
struct LANScanView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var includeSubnet = true
    @State private var manualTargets = ""
    @State private var createJobs = true
    @State private var selected: Set<String> = []
    @State private var scanning = false
    @State private var scanned = false
    @State private var scanTask: Task<Void, Never>?

    private var results: [DiscoveredDatabase] { state.discoveredResults }
    private var subnetsText: String {
        let s = LANScanner.localSubnets()
        return s.isEmpty ? "（未检测到网段）" : s.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("扫描局域网共享数据库").font(.headline)
                Spacer()
                if scanning { ProgressView().controlSize(.small) }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("自动全扫本机所在网段：\(subnetsText)", isOn: $includeSubnet)
                    TextField("手动追加 IP 或网段（逗号分隔，如 192.168.3.99, 192.168.3.0/24）",
                              text: $manualTargets)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("局域网库密码默认尝试 DaVinci / postgres / dblist.conf 登记密码")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        // v1.7.0：开始扫描按钮与「添加所选」同款（accent 蓝圆角、默认大小）
                        Button(scanning ? "扫描中…" : "开始扫描") { startScan() }
                            .buttonStyle(.borderedProminent)
                            .disabled(scanning)
                        Button("停止扫描") { stopScan() }
                            .disabled(!scanning)
                    }
                }
                .padding(8)
            }

            if scanned {
                DiscoverResultList(results: results, selected: $selected)
                Toggle("为新增连接创建默认备份任务（按全局备份机制）", isOn: $createJobs)
            } else {
                // v1.7.6：局域网全扫较慢，提示预计几分钟+可改用手动添加；字号调大到 title3
                Label("局域网扫描较慢，预计需要几分钟。如已知目标主机 IP，可返回主界面手动添加。", systemImage: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            }
            HStack {
                if scanned {
                    Button("全选") { selected = Set(results.map(\.id)) }
                        .disabled(results.isEmpty)
                    Button("全不选") { selected.removeAll() }
                        .disabled(results.isEmpty)
                }
                Spacer()
                Button("关闭窗口") { dismiss() }
                if scanned {
                    Button("添加所选（\(selected.count)）") {
                        if !selected.isEmpty {
                            let items = results.filter { selected.contains($0.id) }
                            state.addDiscovered(items, createJobs: createJobs)
                        }
                        dismiss()
                    }
                    .disabled(results.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    // v1.7.0：与「重新扫描」同款蓝色圆角
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 620, height: 520)
        .onDisappear { scanTask?.cancel(); scanTask = nil }
    }

    private func startScan() {
        scanTask?.cancel()
        scanning = true
        scanned = false
        let manual = manualTargets.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        scanTask = Task {
            let found = await state.scanLANNow(includeSubnet: includeSubnet, manualTargets: manual)
            guard !Task.isCancelled else { return }
            scanned = true
            selected = Set(found.map(\.id))
            scanning = false
        }
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        scanning = false
        scanned = true // 展示已扫描到的部分结果，可改输入后重新扫描
    }
}

/// 扫描结果列表（勾选），网络库/本地库统一展示。
struct DiscoverResultList: View {
    let results: [DiscoveredDatabase]
    @Binding var selected: Set<String>

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView(
                "未发现数据库",
                systemImage: "externaldrive.badge.xmark",
                description: Text("请确认服务已启动、路径正确，或改用其他扫描方式。"))
                .frame(height: 200)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("发现 \(results.count) 个数据库，勾选要添加的：")
                    .font(.callout).foregroundStyle(.secondary)
                List(results) { item in
                    HStack {
                        Image(systemName: selected.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selected.contains(item.id) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.baseName).font(.body)
                                Text(item.kind.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            Text(item.displayName)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selected.contains(item.id) { selected.remove(item.id) }
                        else { selected.insert(item.id) }
                    }
                }
                .frame(height: 260)
            }
        }
    }
}

/// 连接编辑表单（新增/编辑共用；网络库含主机端口，本地库仅名称+路径）。
struct ConnectionEditorView: View {
    var connection: DatabaseConnection?
    var kind: ConnectionKind = .network
    /// 自定义新增标题（本机共享/局域网共享/本地）；nil 时按 kind 推导。
    var title: String? = nil
    /// 局域网共享：自动获取本机网卡 IP 填入主机（用户改最后一位指向局域网）。
    var autoHostFromInterface: Bool = false
    var onSave: (DatabaseConnection, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var portText: String
    @State private var dbname: String
    @State private var username: String
    @State private var password: String
    @State private var localPath: String
    /// 本机网卡列表与当前选中（局域网共享时自动填主机 IP）。
    @State private var interfaces: [NetworkInterface] = []
    @State private var selectedInterface: String?

    init(connection: DatabaseConnection?, kind: ConnectionKind = .network,
         title: String? = nil, autoHostFromInterface: Bool = false,
         onSave: @escaping (DatabaseConnection, String?) -> Void) {
        self.connection = connection
        self.kind = connection?.kind ?? kind
        self.title = title
        self.autoHostFromInterface = autoHostFromInterface
        self.onSave = onSave
        _name = State(initialValue: connection?.name ?? "")
        // 局域网共享：自动获取本机网卡 IP 填入主机（用户只需改最后一位指向局域网其他主机）
        let ifaces = NetworkInterfaces.list()
        _interfaces = State(initialValue: ifaces)
        if connection == nil, self.kind == .network, autoHostFromInterface, let first = ifaces.first {
            _selectedInterface = State(initialValue: first.name)
            _host = State(initialValue: first.ip)
        } else {
            _selectedInterface = State(initialValue: nil)
            _host = State(initialValue: connection?.host ?? "127.0.0.1")
        }
        _portText = State(initialValue: connection.map { String($0.port) } ?? "5432")
        _dbname = State(initialValue: connection?.dbname ?? "")
        _username = State(initialValue: connection?.username ?? "postgres")
        // 新增网络连接：密码默认预填 DaVinci（客户可改/清空）
        _password = State(initialValue: (connection == nil && self.kind == .network) ? "DaVinci" : "")
        // v1.6.4：添加本地数据库时默认填达芬奇官方本地库目录（不置空），客户可点「浏览」改别处
        _localPath = State(initialValue: connection?.localPath
                           ?? LocalDBScanner.defaultLocalDirs.first
                           ?? "\(LocalDBScanner.resolveSupportDir)/Resolve Project Library")
    }

    private var isNetwork: Bool { self.kind == .network }

    var body: some View {
        VStack(spacing: 12) {
            Text(connection == nil
                 ? (title ?? (isNetwork ? "添加网络数据库" : "添加本地数据库"))
                 : "编辑连接")
                .font(.headline)
            Form {
                TextField("名称", text: $name)
                if isNetwork {
                    if autoHostFromInterface, !interfaces.isEmpty {
                        Picker("本机网卡", selection: $selectedInterface) {
                            ForEach(interfaces, id: \.name) { i in
                                Text("\(i.type)（\(i.name)）· \(i.ip)").tag(i.name as String?)
                            }
                        }
                        .onChange(of: selectedInterface) { _, newName in
                            guard let newName, let i = interfaces.first(where: { $0.name == newName }) else { return }
                            host = i.ip
                        }
                    }
                    // v1.6.4：主机字段括号提示；v1.7.3：本机共享去掉括号说明，
                    // 局域网共享保留精简版；v1.7.4：再精简到一行（避免换行）
                    TextField(autoHostFromInterface ? "主机（改末位指向局域网主机）" : "主机",
                              text: $host)
                    TextField("端口", text: $portText)
                    TextField("数据库", text: $dbname)
                    TextField("用户名", text: $username)
                    SecureField(connection == nil ? "密码（默认 DaVinci）" : "密码（留空则不修改）",
                                text: $password)
                } else {
                    HStack {
                        TextField("本地库路径（文件夹）", text: $localPath)
                        Button("浏览…") { chooseFolder() }
                    }
                    Text("达芬奇本地库 = 磁盘上的文件夹（含 User.db / 项目 Project.db）。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") { save() }
                    .disabled(name.isEmpty || (isNetwork
                                              ? (host.isEmpty || dbname.isEmpty)
                                              : localPath.isEmpty))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480)
    }

    private func save() {
        let c = DatabaseConnection(
            id: connection?.id ?? UUID(),
            name: name, host: isNetwork ? host : "", port: Int(portText) ?? 5432,
            dbname: isNetwork ? dbname : "", username: isNetwork ? username : "postgres",
            isDefault: connection?.isDefault ?? false,
            kind: kind, localPath: isNetwork ? nil : localPath)
        // 新增：始终用当前密码（默认 DaVinci）；编辑：留空 = 不修改
        let passwordOut: String? = connection == nil ? password : (password.isEmpty ? nil : password)
        onSave(c, passwordOut)
        dismiss()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择达芬奇本地数据库文件夹（Resolve Project Library 或含 .db 的文件夹）"
        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.path
        }
    }
}
