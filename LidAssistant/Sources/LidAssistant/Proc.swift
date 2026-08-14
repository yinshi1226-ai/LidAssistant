import Foundation

/// 安全的子进程执行器：
/// - 输出写入临时文件而非管道，避免管道缓冲满导致子进程阻塞 → waitUntilExit 死锁；
/// - 带超时，超时后 SIGTERM 终止，防止任何探测卡死监控循环。
enum Proc {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ path: String, _ args: [String], timeout: Double = 10) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args

        let tmpDir = FileManager.default.temporaryDirectory
        let outURL = tmpDir.appendingPathComponent("lidassist-out-\(UUID().uuidString)")
        let errURL = tmpDir.appendingPathComponent("lidassist-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)

        guard let outFH = FileHandle(forWritingAtPath: outURL.path),
              let errFH = FileHandle(forWritingAtPath: errURL.path) else {
            return Result(status: -1, stdout: "", stderr: "无法创建临时文件")
        }
        p.standardOutput = outFH
        p.standardError = errFH

        do {
            try p.run()
        } catch {
            outFH.closeFile()
            errFH.closeFile()
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
            return Result(status: -1, stdout: "", stderr: "启动失败: \(error)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if p.isRunning {
            p.terminate()
        }
        p.waitUntilExit()

        outFH.closeFile()
        errFH.closeFile()
        let out = (try? Data(contentsOf: outURL)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let err = (try? Data(contentsOf: errURL)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        try? FileManager.default.removeItem(at: outURL)
        try? FileManager.default.removeItem(at: errURL)
        return Result(status: p.terminationStatus, stdout: out, stderr: err)
    }
}
