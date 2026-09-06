import SwiftUI
import AppKit

/// 备份任务：顶部全局备份机制（时间机器式：间隔 + 全局位置），下方每库简化卡片。
struct JobsView: View {
    @EnvironmentObject var state: AppState
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // v1.6.5：全局备份机制设置（位于「立即备份全部」左方/上方）
            GlobalBackupSettingsBar()
                .padding(.horizontal)
                .padding(.top, 10)

            HStack {
                Text("备份任务").font(.title2.bold())
                Spacer()
                Button("＋ 添加任务") { showAdd = true }
            }
            .padding()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(state.config.jobs) { job in
                        if let conn = state.connection(for: job.connectionId) {
                            JobCard(job: job, connection: conn)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddJobView()
        }
    }
}

/// v1.6.6 全局备份机制（时间机器式）：间隔（分钟）+ 全局备份位置，保留规则固定。
struct GlobalBackupSettingsBar: View {
    @EnvironmentObject var state: AppState

    @State private var intervalMin = "10"
    @State private var rootText = ""
    @State private var loaded = false
    @State private var savedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // v1.6.7：标题移到灰框外上方、加大字体，与「备份任务」一致
            Text("全局备份机制").font(.title2.bold())
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    // 第一行：间隔 + 全局备份位置 + 浏览 + 在 Finder 中打开
                    HStack(spacing: 12) {
                        LabeledContent("间隔（分钟）") {
                            TextField("10", text: $intervalMin)
                                .frame(width: 70).textFieldStyle(.roundedBorder)
                        }
                        Text("全局备份位置")
                        TextField("备份根目录", text: $rootText)
                            .textFieldStyle(.roundedBorder)
                        Button("浏览…") { choosePath() }
                            .help("选择全局备份保存目录（建议外接硬盘）")
                        Button("在 Finder 中打开") { openInFinder() }
                            .help("在 Finder 中打开全局备份位置")
                    }
                    // 第二行：保存设置 + 立即备份全部
                    HStack(spacing: 12) {
                        Button("保存设置") { save() }
                        Button("立即备份全部") {
                            Task { await state.backupAll() }
                        }
                        Spacer()
                        if savedFlash {
                            Text("已保存 ✓").font(.callout).foregroundStyle(.green)
                        }
                    }
                    // 第三行：保留规则说明（v1.7.5 三级）
                    Text("最近 24 小时内的备份全部保留；超过 24 小时的每天只保留最后 1 份；超过 1 个月的每月只保留最后 1 份。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(6)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        intervalMin = String(max(state.config.settings.backupIntervalMinutes, 1))
        rootText = state.globalBackupRoot
    }

    private func save() {
        state.config.settings.backupIntervalMinutes = max(Int(intervalMin) ?? 10, 1)
        state.config.settings.backupRoot = rootText.isEmpty ? nil : rootText
        state.save()
        state.syncAllSchedules()
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择全局备份保存目录"
        if panel.runModal() == .OK, let url = panel.url {
            rootText = url.path
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: rootText))
    }
}

/// 每库任务卡片（v1.6.6：去掉下次运行时间，按钮一排：启用→打开路径→立即备份→删除任务）。
struct JobCard: View {
    @EnvironmentObject var state: AppState
    let job: BackupJob
    let connection: DatabaseConnection

    @State private var enabled: Bool

    init(job: BackupJob, connection: DatabaseConnection) {
        self.job = job
        self.connection = connection
        _enabled = State(initialValue: job.enabled)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(connection.name)（\(connection.sourceDescription)）")
                        .font(.headline)
                    Text(connection.kind.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(URL(fileURLWithPath: state.globalBackupRoot)
                            .appendingPathComponent(connection.name, isDirectory: true).path)
                            .font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                HStack(spacing: 12) {
                    Toggle("启用", isOn: $enabled)
                        .onChange(of: enabled) { _, v in
                            state.setJobEnabled(job, enabled: v)
                        }
                    Spacer()
                    if state.busyJobIDs.contains(job.id) {
                        ProgressView().controlSize(.small)
                    }
                    Button("打开路径") { openInFinder() }
                        .help("在 Finder 中打开该数据库的备份保存目录")
                    Button("立即备份") {
                        Task { await state.backupNow(jobID: job.id) }
                    }
                    .disabled(state.busyJobIDs.contains(job.id))
                    Button("删除任务") { state.deleteJob(job) }
                        .foregroundStyle(.red)
                }
            }
            .padding(8)
        }
    }

    /// 打开该库的实际备份目录（{全局备份位置}/{connectionName}，不存在则打开全局根目录）。
    private func openInFinder() {
        let folder = URL(fileURLWithPath: state.globalBackupRoot)
            .appendingPathComponent(connection.name, isDirectory: true)
        let url = FileManager.default.fileExists(atPath: folder.path)
            ? folder : URL(fileURLWithPath: state.globalBackupRoot)
        NSWorkspace.shared.open(url)
    }
}

/// 添加任务：为尚未有任务的连接创建备份任务（v1.6.5 用全局设置，不再填路径/间隔/保留）。
struct AddJobView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedConnectionID: UUID?

    private var candidates: [DatabaseConnection] {
        let used = Set(state.config.jobs.map { $0.connectionId })
        return state.config.connections.filter { !used.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("添加备份任务").font(.headline)
            Form {
                Picker("数据库", selection: $selectedConnectionID) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(candidates) { c in
                        Text("\(c.name)（\(c.sourceDescription)）").tag(UUID?.some(c.id))
                    }
                }
                Text("将使用全局备份位置与全局间隔（\(state.config.settings.backupIntervalMinutes) 分钟）自动创建任务。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("添加") {
                    if let id = selectedConnectionID {
                        state.addJob(connectionID: id)
                    }
                    dismiss()
                }
                .disabled(selectedConnectionID == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear {
            if selectedConnectionID == nil {
                selectedConnectionID = candidates.first?.id
            }
        }
    }
}
