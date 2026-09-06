import Foundation
import ServiceManagement
import Darwin

/// 调度：每个启用的 Job 生成/更新一条用户级 LaunchAgent plist，
/// ProgramArguments 指向本 App 的 `--run-backup <jobId>` 入口，StartInterval 取 Job 间隔。
/// 通过 launchctl bootstrap/bootout 管理；开机自启用 SMAppService.mainApp（失败则回退自定义 LaunchAgent）。
final class ScheduleManager {
    static let loginLabel = "com.resolvedbbackup.login"

    let agentDir: URL
    let logDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        agentDir = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        logDir = home.appendingPathComponent("Library/Logs/ResolveDBBackup", isDirectory: true)
    }

    private func label(for jobID: UUID) -> String {
        "com.resolvedbbackup.job.\(jobID.uuidString)"
    }
    private func plistURL(for jobID: UUID) -> URL {
        agentDir.appendingPathComponent("\(label(for: jobID)).plist")
    }

    static var uid: String { "\(getuid())" }

    // MARK: - LaunchAgent 底层命令

    private static func bootstrap(_ plist: URL) -> ProcessResult {
        ProcessRunner.runSync(executable: "/bin/launchctl",
                              arguments: ["bootstrap", "gui/\(uid)", plist.path])
    }
    private static func bootout(label: String) -> ProcessResult {
        ProcessRunner.runSync(executable: "/bin/launchctl",
                              arguments: ["bootout", "gui/\(uid)/\(label)"])
    }

    // MARK: - 任务级调度

    /// v1.6.5 任务级调度：间隔取全局 intervalSeconds（不再按库）。
    func writeJobPlist(job: BackupJob, intervalSeconds: Int, executablePath: String) throws {
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let outLog = logDir.appendingPathComponent("\(job.id.uuidString).out.log").path
        let errLog = logDir.appendingPathComponent("\(job.id.uuidString).err.log").path
        let dict: [String: Any] = [
            "Label": label(for: job.id),
            "ProgramArguments": [executablePath, "--run-backup", job.id.uuidString],
            "StartInterval": max(intervalSeconds, 10),
            "RunAtLoad": false,
            "ProcessType": "Background",
            "StandardOutPath": outLog,
            "StandardErrorPath": errLog
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL(for: job.id), options: .atomic)
    }

    /// 幂等：bootout 旧的再 bootstrap 新的；禁用则卸载并删除 plist。
    func sync(job: BackupJob, intervalSeconds: Int, executablePath: String) {
        let label = label(for: job.id)
        let plist = plistURL(for: job.id)
        _ = Self.bootout(label: label) // 未加载时忽略错误
        if job.enabled {
            do {
                try writeJobPlist(job: job, intervalSeconds: intervalSeconds, executablePath: executablePath)
                let r = Self.bootstrap(plist)
                if r.exitCode != 0 {
                    NSLog("ResolveDBBackup: 加载 LaunchAgent 失败 \(label): \(r.stderr)")
                }
            } catch {
                NSLog("ResolveDBBackup: 写入 plist 失败 \(error.localizedDescription)")
            }
        } else {
            try? FileManager.default.removeItem(at: plist)
        }
    }

    func removeJob(jobID: UUID) {
        _ = Self.bootout(label: label(for: jobID))
        try? FileManager.default.removeItem(at: plistURL(for: jobID))
    }

    /// 为所有任务同步 LaunchAgent（AppState 与 CLI 共用）。
    func syncAll(jobs: [BackupJob], intervalSeconds: Int, executablePath: String) {
        for job in jobs {
            sync(job: job, intervalSeconds: intervalSeconds, executablePath: executablePath)
        }
    }

    // MARK: - 开机自启

    /// 返回给用户的提示信息。
    func setLoginItem(enabled: Bool, executablePath: String) throws -> String {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                return "已启用开机自启（SMAppService，App 位于 /Applications）"
            } catch {
                // 回退：自定义登录 LaunchAgent（RunAtLoad，开机拉起 App 本体）
                let label = Self.loginLabel
                let plist = agentDir.appendingPathComponent("\(label).plist")
                try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
                let dict: [String: Any] = [
                    "Label": label,
                    "ProgramArguments": [executablePath],
                    "RunAtLoad": true,
                    "ProcessType": "Interactive",
                    "StandardOutPath": logDir.appendingPathComponent("login.out.log").path,
                    "StandardErrorPath": logDir.appendingPathComponent("login.err.log").path
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
                try data.write(to: plist, options: .atomic)
                _ = Self.bootout(label: label)
                let r = Self.bootstrap(plist)
                if r.exitCode != 0 {
                    throw NSError(domain: "ResolveDBBackup", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "LaunchAgent 加载失败: \(r.stderr)"])
                }
                return "已启用开机自启（LaunchAgent 方式，App 未安装在 /Applications）"
            }
        } else {
            try? SMAppService.mainApp.unregister()
            _ = Self.bootout(label: Self.loginLabel)
            try? FileManager.default.removeItem(
                at: agentDir.appendingPathComponent("\(Self.loginLabel).plist"))
            return "已关闭开机自启"
        }
    }

    func loginItemEnabled() -> Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(
            atPath: agentDir.appendingPathComponent("\(Self.loginLabel).plist").path)
    }
}
