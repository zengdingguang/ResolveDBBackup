import SwiftUI
import AppKit
import UserNotifications

/// 设置：备份引擎 / 保留策略 / 通知 / 开机自启 / 配置导入导出 / 关于。
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @State private var pgDumpPath: String = ""
    @State private var notifyFailure = true
    @State private var notifySuccess = false
    @State private var launchAtLogin = false
    @State private var feedback = ""
    @State private var notificationAuthorized = true

    var body: some View {
        Form {
            // v1.6.9：打赏区块移到设置页最上方（备份引擎之前）
            Section("打赏") {
                VStack(alignment: .center, spacing: 8) {
                    if let url = Bundle.main.url(forResource: "donation_qr", withExtension: "png"),
                       let img = NSImage(contentsOf: url) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 117, height: 117)
                            .help("微信收款码")
                    }
                    Text("别等数据库炸了才想起我。\n扫码赏点，让我有电继续给你站岗。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section("备份引擎") {
                TextField("pg_dump 路径", text: $pgDumpPath)
                    .textFieldStyle(.roundedBorder)  // 意见：深色输入框，一眼看出可填路径
                    .onSubmit { save() }
                HStack {
                    Button("自动检测") { detectPgDumpPath() }
                        .help("扫描常见安装位置，自动定位 pg_dump")
                    Button("选择…") { choosePgDumpPath() }
                        .help("在 Finder 中选择 pg_dump 可执行文件")
                    Button("恢复默认") {
                        pgDumpPath = ToolPaths.defaultPgDump
                        save()
                    }
                }
                Text("psql / pg_restore 取同目录：\(ToolPaths.psql(for: state.config.settings.pgDumpPath))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("通知") {
                Toggle("备份失败时通知", isOn: $notifyFailure)
                Toggle("备份成功时通知", isOn: $notifySuccess)
                if !notificationAuthorized {
                    HStack {
                        Text("⚠️ 系统通知权限未开启，备份失败/成功时不会弹出通知。")
                            .font(.callout).foregroundStyle(.orange)
                        Spacer()
                        Button("打开通知设置") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            Section("启动") {
                Toggle("开机自启", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        state.setLaunchAtLogin(v)
                    }
            }
            Section("配置") {
                HStack {
                    Button("导出配置 JSON…") { export() }
                    Button("导入配置 JSON…") { importConfig() }
                    // v1.6.5：改名「在 Finder 中显示」
                    Button("在 Finder 中显示") { revealConfigFile() }
                        .help("在 Finder 中显示配置文件，方便查找/拷贝/备份")
                }
                // v1.6.4：说明配置文件是干嘛的（不写自动保存位置）
                Text("配置文件用于保存全部数据库连接、备份任务与各项设置，以后可用「导入配置 JSON」一键恢复之前的全部设置。")
                    .font(.callout).foregroundStyle(.secondary)
                if !feedback.isEmpty {
                    Text(feedback).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("关于") {
                LabeledContent("软件", value: "水螅ResolveBackup \(ToolPaths.appVersion)")
                LabeledContent("作者", value: "调色师 zengdingguang")
                Text("免责声明：本软件按“现状”及“可用”原则提供，作者不对其功能、性能、准确性、完整性、可靠性或适用性作任何明示或默示的担保。用户应自行确认备份结果正确、备份文件完整且可正常还原。在任何情况下，作者均不对因使用或无法使用本软件引起的任何直接、间接、附带、特殊或后果性损害（包括但不限于数据丢失、数据损坏、业务中断、利润损失）承担责任，即使已被告知可能发生此类损害。本软件依赖 PostgreSQL 官方命令行工具（pg_dump/pg_restore/psql）执行备份，作者不对第三方软件的行为、缺陷或变更负责。用户安装、启动或使用本软件，即视为已阅读并同意上述条款。")
                    .font(.body)  // 意见：与作者名称同级字号；明暗度对齐作者项（secondary）
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 460)
        .onAppear {
            load()
            Task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                notificationAuthorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
        }
    }

    private func load() {
        let s = state.config.settings
        pgDumpPath = s.pgDumpPath
        notifyFailure = s.notifyOnFailure
        notifySuccess = s.notifyOnSuccess
        launchAtLogin = state.loginItemEnabled()
    }

    private func save() {
        var s = state.config.settings
        s.pgDumpPath = pgDumpPath
        s.notifyOnFailure = notifyFailure
        s.notifyOnSuccess = notifySuccess
        state.config.settings = s
        state.save()
        feedback = "设置已保存"
    }

    /// v1.6.4：在 Finder 中定位显示配置文件。
    private func revealConfigFile() {
        let url = ConfigStore().configURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            feedback = "配置文件尚未生成"
        }
    }

    /// 意见3：自动检测常见位置的 pg_dump。
    private func detectPgDumpPath() {
        if let p = ToolPaths.detectPgDump() {
            pgDumpPath = p
            save()
            feedback = "已自动检测到 pg_dump：\(p)"
        } else {
            feedback = "未在常见位置找到 pg_dump，请用「选择…」手动指定"
        }
    }

    /// 意见3：Finder 选择 pg_dump 可执行文件。
    private func choosePgDumpPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 pg_dump 可执行文件（通常位于 PostgreSQL 安装目录的 bin 文件夹）"
        if panel.runModal() == .OK, let url = panel.url {
            pgDumpPath = url.path
            save()
            feedback = "已设置 pg_dump：\(url.path)"
        }
    }

    private func export() {
        guard let data = state.exportConfig() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ResolveDBBackup-config.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
            feedback = "已导出到 \(url.path)"
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            if state.importConfig(data: data) {
                load()
                feedback = "已导入 \(url.lastPathComponent)"
            } else {
                feedback = "导入失败：不是有效的配置文件"
            }
        }
    }
}
