import Foundation

/// 简单文件日志：~/Library/Application Support/LidAssistant/lidassistant.log（滚动截断 1MB）
final class Log {
    static let shared = Log()

    private let queue = DispatchQueue(label: "lidassist.log")
    private var handle: FileHandle?
    private let maxBytes: UInt64 = 1_000_000
    let path: String

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LidAssistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("lidassistant.log").path
        if FileManager.default.fileExists(atPath: path) {
            handle = FileHandle(forWritingAtPath: path)
            handle?.seekToEndOfFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: nil)
            handle = FileHandle(forWritingAtPath: path)
        }
    }

    func log(_ level: String, _ msg: String) {
        let line = "[\(Self.formatter.string(from: Date()))] [\(level)] \(msg)\n"
        queue.async { [weak self] in
            guard let self, let h = self.handle else { return }
            if let data = line.data(using: .utf8) {
                h.write(data)
                if h.offsetInFile > self.maxBytes {
                    h.truncateFile(atOffset: 0)
                    h.seekToEndOfFile()
                }
            }
        }
    }

    func info(_ m: String) { log("INFO", m) }
    func warn(_ m: String) { log("WARN", m) }
    func error(_ m: String) { log("ERROR", m) }

    /// 读日志尾部若干行（诊断用）
    func tail(_ maxBytes: Int = 40_000) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "(无日志)" }
        let sub = data.suffix(maxBytes)
        return String(data: sub, encoding: .utf8) ?? "(编码错误)"
    }
}
