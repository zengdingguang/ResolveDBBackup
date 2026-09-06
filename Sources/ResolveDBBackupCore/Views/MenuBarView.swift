import SwiftUI
import AppKit

/// 菜单栏下拉：各库状态 + 立即备份全部 / 打开管理面板 / 退出。
/// v1.7.6：软件名/数据库行用 Button 包装——menu 样式下普通 Text 会被系统置灰，
/// Button（.plain 样式）的文字始终是亮白色。
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. 软件名称（Button 包装强制亮色）
            Button(action: {}) {
                Text("水螅ResolveBackup \(ToolPaths.appVersion)")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(false)

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

            // 4. 已连接的数据库列表（三种类型全部显示）
            ForEach(state.config.connections) { conn in
                statusRow(conn: conn)
            }

            if let msg = state.statusMessage, !msg.isEmpty {
                Button(action: {}) {
                    Text(msg).font(.callout)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(false)
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
        // Button 包装强制亮色（menu 样式下普通 Text 会被系统置灰）
        Button(action: {}) {
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
        }
        .buttonStyle(.plain)
        .allowsHitTesting(false)
        .padding(.vertical, 2)
    }
}
