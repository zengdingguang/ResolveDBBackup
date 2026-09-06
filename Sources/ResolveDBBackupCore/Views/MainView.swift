import SwiftUI

/// 主管理窗口：连接 / 备份任务 / 历史 / 设置。
/// v1.6.8：软件名 + 版本号置于窗口最上方，四个选项卡在软件名下方（自定义胶囊按钮行，
/// 替代系统 TabView tab bar，保证软件名一定在 tab 之上）。
struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: MainTab = .connections

    enum MainTab: Hashable {
        case connections, jobs, history, settings
        var title: String {
            switch self {
            case .connections: return "连接"
            case .jobs: return "备份任务"
            case .history: return "历史"
            case .settings: return "设置"
            }
        }
        var icon: String {
            switch self {
            case .connections: return "externaldrive"
            case .jobs: return "clock.arrow.circlepath"
            case .history: return "list.bullet.rectangle"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 软件名 + 版本号：窗口最上方
            Text("水螅ResolveBackup \(ToolPaths.appVersion)")
                .font(.title2.weight(.bold))
                .padding(.top, 14)
                .padding(.bottom, 8)
            // 四个选项卡：软件名下方
            HStack(spacing: 10) {
                ForEach([MainTab.connections, .jobs, .history, .settings], id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.bottom, 8)
            Divider()
            // 内容区
            Group {
                switch selection {
                case .connections: ConnectionsView()
                case .jobs: JobsView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            Divider()
            // v1.7.0：作者靠左；右侧「使用问题反馈」邮箱
            HStack {
                Text("作者：调色师 zengdingguang")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("使用问题反馈：402481025@qq.com")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                Text(tab.title)
            }
            .font(.title3.weight(isSelected ? .bold : .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }
}
