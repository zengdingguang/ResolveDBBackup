import Foundation
import ResolveDBBackupCore

// v1.7.6：全局异常捕获——崩溃时写入日志，方便排查闪退原因。
NSSetUncaughtExceptionHandler { exception in
    let log = """
    === 水螅ResolveBackup 崩溃日志 ===
    时间: \(Date())
    异常: \(exception.name.rawValue)
    原因: \(exception.reason ?? "未知")
    调用栈:
    \(exception.callStackSymbols.joined(separator: "\n"))
    ================================
    """
    let logDir = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Logs/ResolveDBBackup", isDirectory: true)
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logURL = logDir.appendingPathComponent("crash.log")
    if let data = log.data(using: .utf8) {
        try? data.write(to: logURL, options: .atomic)
    }
}

// 双入口：CLI（LaunchAgent 定时触发）优先，否则启动 GUI。
let arguments = CommandLine.arguments
if arguments.contains("--seed-config") {
    exit(SeedCLI.run())
}
if arguments.contains("--scan-local") || arguments.contains("--scan-localdb")
    || arguments.contains("--scan-lan") || arguments.contains("--scan-lan-import")
    || arguments.contains("--ensure-jobs") {
    exit(ScanCLI.run())
}
if let i = arguments.firstIndex(of: "--run-backup"), i + 1 < arguments.count {
    exit(BackupCLI.run(jobID: arguments[i + 1]))
}
ResolveDBBackupApp.main()
