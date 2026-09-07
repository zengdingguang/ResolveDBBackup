import SwiftUI
import AppKit

/// 菜单栏下拉：各库状态 + 立即备份全部 / 打开管理面板 / 退出。
/// v1.7.7：恢复 v1.7.4 样式——软件名/数据库行/状态消息用普通 Text，
/// menu 样式下系统自动渲染为灰色、不可点击；按钮保持可点击。
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. 软件名称（普通 Text，menu 下自动置灰，不可点击）
            Text("水螅ResolveBackup \(ToolPaths.appVersion)")
                .font(.headline)

            // 2. 立即备份全部
            Button("立即备份全部") {
                Task { await state.backupAll() }
            }

            // 3. 打开管理面板
            Button("打开管理面板…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            // 4. 已连接的数据库列表（三种类型全部显示，普通 Text 自动置灰）
            ForEach(state.config.connections) { conn in
                statusRow(conn: conn)
            }

            if let msg = state.statusMessage, !msg.isEmpty {
                Text(msg).font(.callout)
            }

            Divider()

            // 5. 退出
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusRow(conn: DatabaseConnection) -> some View {
        let job = state.config.jobs.first(where: { $0.connectionId == conn.id })
        let iconName: String = {
            if let job = job, state.busyJobIDs.contains(job.id) {
                return "arrow.triangle.2.circlepath"
            }
            if let job = job {
                return job.enabled ? "externaldrive.badge.checkmark" : "externaldrive"
            }
            return "externaldrive.badge.plus"
        }()
        // 普通 HStack + Text，menu 样式下系统自动置灰，不可点击
        HStack {
            Image(systemName: iconName)
            Text("\(conn.name) · \(conn.sourceDescription)")
                .font(.callout)
            Spacer()
            if let last = job?.lastRun {
                Text("\(last, style: .relative) 前")
                    .font(.caption2)
            } else if job == nil {
                Text("未备份")
                    .font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }
}
