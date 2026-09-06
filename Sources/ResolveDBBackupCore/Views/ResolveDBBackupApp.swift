import SwiftUI
import AppKit
import Darwin

/// v1.7.4：App 委托——处理 macOS 的 reopen 事件。
/// 已运行的菜单栏 App 被再次双击/打开时，LaunchServices 不会启动新进程，
/// 而是向已有实例发送 reopen 事件；此回调负责弹出主界面。
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopen: (() -> Void)?
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onReopen?()
        return true
    }
}

/// 菜单栏 App 主体：菜单栏状态 + 主管理窗口 + 设置窗口。
/// CLI 分支（--run-backup）由 main.swift 先行处理，不进 GUI。
public struct ResolveDBBackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow

    public init() {}

    /// v1.7.6：菜单栏图标——自定义水螅剪影（白底黑图，与 App 图标一致）。
    /// 用 .renderingMode(.original) 保持原始颜色，不跟随系统明暗变化。
    /// 若图片加载失败则回退到 SF Symbol 磁盘线稿。
    @ViewBuilder
    private func menuBarIcon() -> some View {
        if let url = Bundle.main.url(forResource: "menubar_icon", withExtension: "png"),
           let nsImg = NSImage(contentsOf: url) {
            Image(nsImage: nsImg)
                .renderingMode(.original)
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "externaldrive.badge.checkmark")
        }
    }

    /// v1.6.4：判断本次启动是否应弹出主界面窗口。
    /// 规则：首次安装（无配置文件）→ 总是弹出；开机自启 → 只进菜单栏不弹；
    /// 用户手动打开（双击/右键）→ 弹出主界面，让新用户一眼看到软件已打开。
    ///
    /// 区分「开机自启 / 手动打开」：不能靠 XPC_SERVICE_NAME（已注册开机自启的机器上
    /// 手动打开也会带该变量，实测不可靠）。改用进程启动时间与系统开机时间的差值：
    /// 开机自启的进程在用户登录后极短时间内启动（开机后几分钟内），
    /// 手动打开则远晚于开机时间。
    private func shouldShowMainWindowOnLaunch() -> Bool {
        if !ConfigStore().configExists() { return true }   // 首次安装
        if isLaunchAtLoginStartup() { return false }        // 开机自启
        return true                                         // 手动打开
    }

    /// 进程是否在开机后 180 秒内启动（视为开机自启/登录项启动）。
    private func isLaunchAtLoginStartup() -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
        let start = info.kp_proc.p_starttime
        let uptimeAtLaunch = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return uptimeAtLaunch < 180
    }

    /// v1.7.4：双击弹窗的「打开主窗口」请求文件（放应用支持目录，避免与备份数据混放）。
    private static func openRequestURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("ResolveDBBackup", isDirectory: true)
            .appendingPathComponent(".open_main_request")
    }

    public var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            // v1.7.6：菜单栏图标改为自定义水螅剪影（白底黑图，与 App 图标一致）。
            // 用 .renderingMode(.original) 保持原始颜色，不跟随系统明暗变化。
            // 若图片加载失败则回退到 SF Symbol 磁盘线稿。
            menuBarIcon()
                // v1.6.4：label 启动即显示，onAppear 必然在启动时触发（content 是懒加载的，不能用它）。
                // 延迟 1.5s 等 MenuBarExtra 完全就绪后再 openWindow，避免启动早期打开窗口导致菜单栏图标消失。
                .onAppear {
                    // v1.7.4：双击弹窗——已运行实例被再次打开时，由 reopen 回调弹出主窗口；
                    // 另设单实例兜底：若确实启动新进程则写入请求文件后退出，由既有实例轮询弹窗。
                    appDelegate.onReopen = {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    let pid = getpid()
                    let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.resolvedbbackup.app")
                        .filter { $0.processIdentifier != pid }
                    if !others.isEmpty {
                        let url = Self.openRequestURL()
                        try? FileManager.default.createDirectory(
                            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? Data().write(to: url)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
                        return
                    }
                    // 首个实例：轮询「打开主窗口」请求文件（兜底，覆盖新进程写入的场景）
                    Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { t in
                        let url = Self.openRequestURL()
                        if FileManager.default.fileExists(atPath: url.path) {
                            try? FileManager.default.removeItem(at: url)
                            openWindow(id: "main")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                    if shouldShowMainWindowOnLaunch() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            openWindow(id: "main")
                            // v1.6.5 意见1：手动打开时主窗口显示在最前面，不被其他窗口（如访达）挡住
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
        }
        .menuBarExtraStyle(.menu)

        // v1.6.9：窗口标题栏文字去掉（单空格标题，视觉无文字；空字符串标题会导致窗口不创建）
        Window(" ", id: "main") {
            MainView()
                .environmentObject(state)
                .onAppear {
                    state.syncAllSchedules()
                    // v1.6.5 意见1：主窗口出现时激活到前台、置顶显示
                    NSApp.activate(ignoringOtherApps: true)
                }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
