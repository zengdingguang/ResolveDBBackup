import SwiftUI
import AppKit

/// 备份历史/日志。
struct HistoryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("备份历史").font(.title2.bold())
                Spacer()
                Text("共 \(state.history.count) 条").font(.callout).foregroundStyle(.secondary)
            }
            .padding()

            Table(state.history) {
                TableColumn("时间") { r in
                    Text(r.date, style: .date) + Text(" ") + Text(r.date, style: .time)
                }
                TableColumn("连接") { r in Text(r.connectionName) }
                TableColumn("库") { r in Text(r.dbname) }
                TableColumn("状态") { r in
                    Text(r.success ? "成功" : "失败")
                        .foregroundStyle(r.success ? Color.green : Color.red)
                }
                TableColumn("大小") { r in
                    Text(r.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                }
                TableColumn("耗时") { r in Text(String(format: "%.1fs", r.duration)) }
                TableColumn("文件") { r in
                    if let p = r.filePath {
                        Text(p).font(.caption2)
                            .contextMenu {
                                Button("在 Finder 中显示") { openInFinder(p) }
                            }
                    } else {
                        Text("—").font(.caption2)
                    }
                }
                TableColumn("错误") { r in
                    Text(r.error ?? "—").font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    /// 意见7：历史「文件」列右键 → 在 Finder 中打开该备份所在的文件夹（并选中文件）。
    /// 意见2：文件/文件夹已被移动或删除时给用户明确提示，不能无反馈。
    private func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        // 文件本身不存在：尝试打开其所在文件夹并提示
        let parent = url.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
            showAlert("找不到备份文件",
                      "该备份文件已不存在或已被移动：\n\(path)\n\n已为你打开其所在文件夹，可查看其他备份。")
        } else {
            showAlert("找不到备份位置",
                      "该备份文件及其所在文件夹均已不存在或被移动：\n\(path)")
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
