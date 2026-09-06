import Foundation

/// 一次子进程执行的输出。
struct ProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var errorDescription: String?
}

/// 子进程输出的并发安全累积缓冲。
private final class PipeBuffer {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    func read() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// 基于 Process 的进程执行器：异步（async）与同步（runSync）两种形态，
/// 参数以数组传递（不经 shell，天然无注入/转义问题），PGPASSWORD 通过环境变量临时注入。
enum ProcessRunner {
    static func run(executable: String, arguments: [String], environment: [String: String]? = nil) async -> ProcessResult {
        await withCheckedContinuation { cont in
            launch(executable: executable, arguments: arguments, environment: environment) { result in
                cont.resume(returning: result)
            }
        }
    }

    static func runSync(executable: String, arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval = 30) -> ProcessResult {
        var result = ProcessResult(exitCode: -1, stdout: "", stderr: "", errorDescription: "执行超时")
        let sem = DispatchSemaphore(value: 0)
        launch(executable: executable, arguments: arguments, environment: environment) { r in
            result = r
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
        return result
    }

    private static func launch(executable: String, arguments: [String], environment: [String: String]?, completion: @escaping (ProcessResult) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        if let environment { env.merge(environment) { _, new in new } }
        process.environment = env

        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { outBuffer.append(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { errBuffer.append(data) }
        }

        process.terminationHandler = { p in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let out = String(data: outBuffer.read(), encoding: .utf8) ?? ""
            let err = String(data: errBuffer.read(), encoding: .utf8) ?? ""
            completion(ProcessResult(exitCode: p.terminationStatus, stdout: out, stderr: err))
        }

        do {
            try process.run()
        } catch {
            completion(ProcessResult(exitCode: -1, stdout: "", stderr: "", errorDescription: "无法启动进程: \(error.localizedDescription)"))
        }
    }
}
