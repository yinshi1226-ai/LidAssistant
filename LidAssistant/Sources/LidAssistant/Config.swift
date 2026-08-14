import Foundation

// MARK: - 配置模型

struct TrafficCfg: Codable {
    /// ps args 里包含任一前缀的进程会被统计网络流量
    var pathPrefixes: [String] = []
    /// 一次采样（两次 nettop 差值）超过该字节数视为“有流量”
    var thresholdBytes: Double = 30_000
    /// 流量出现后把服务状态延长为活跃的秒数（佐证信号，只延不缩）
    var extendSeconds: Double = 15
}

struct JsonlCfg: Codable {
    /// 扫描根目录（支持 ~ 开头）
    var roots: [String] = []
    /// 日志尾部出现这些标记（如 payload:task_complete / last-prompt / turn:ended）即视为任务已结束
    var idleMarkers: [String] = []
}

struct ServiceCfg: Codable {
    var id: String
    var label: String
    var enabled: Bool = true
    /// "dsh" | "jsonl"
    var kind: String = "jsonl"
    var dshBase: String?
    var dshDataDir: String?
    var jsonl: JsonlCfg?
    var traffic: TrafficCfg?
}

struct AppConfig: Codable {
    /// "auto" | "manual"（两种模式二选一）
    var mode: String
    /// 手动模式下的开关：true=合盖不眠 false=合盖休眠
    var manualBlock: Bool
    /// 合盖保持运行期间关闭显示器（黑屏节能）
    var blackScreenOnLidClose: Bool
    /// 任务结束后等待多少分钟进入休眠（可小数）
    var graceMinutes: Double
    /// 轮询间隔（秒）
    var pollIntervalSec: Double
    /// 日志文件 mtime 在多少秒内视为活跃
    var activeWindowSec: Double
    var services: [ServiceCfg]

    init() {
        mode = "auto"
        manualBlock = false
        blackScreenOnLidClose = true
        graceMinutes = 1.0
        pollIntervalSec = 8
        activeWindowSec = 90
        services = AppConfig.defaultServices()
    }

    enum CodingKeys: String, CodingKey {
        case mode, manualBlock, blackScreenOnLidClose, graceMinutes, pollIntervalSec, activeWindowSec, services
    }

    /// 兼容旧版本配置（manual-block / manual-allow → manual + manualBlock）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var m = try c.decodeIfPresent(String.self, forKey: .mode) ?? "auto"
        var mb = try c.decodeIfPresent(Bool.self, forKey: .manualBlock) ?? false
        if m == "manual-block" { m = "manual"; mb = true }
        else if m == "manual-allow" { m = "manual"; mb = false }
        mode = m
        manualBlock = mb
        blackScreenOnLidClose = try c.decodeIfPresent(Bool.self, forKey: .blackScreenOnLidClose) ?? true
        graceMinutes = try c.decodeIfPresent(Double.self, forKey: .graceMinutes) ?? 1.0
        pollIntervalSec = try c.decodeIfPresent(Double.self, forKey: .pollIntervalSec) ?? 8
        activeWindowSec = try c.decodeIfPresent(Double.self, forKey: .activeWindowSec) ?? 90
        services = try c.decodeIfPresent([ServiceCfg].self, forKey: .services) ?? AppConfig.defaultServices()
    }

    static func defaultServices() -> [ServiceCfg] {
        [
            ServiceCfg(
                id: "deepseek",
                label: "DeepSeek",
                kind: "dsh",
                dshBase: "http://127.0.0.1:3080",
                dshDataDir: "~/Documents/DeepSeek-Harness/data",
                jsonl: nil,
                traffic: nil
            ),
            ServiceCfg(
                id: "chatgpt",
                label: "ChatGPT",
                kind: "jsonl",
                jsonl: JsonlCfg(
                    roots: ["~/.codex/sessions", "~/.codex/.chatgpt-projects"],
                    idleMarkers: ["payload:task_complete", "turn:ended"]
                ),
                traffic: TrafficCfg(pathPrefixes: ["/Applications/ChatGPT.app"])
            ),
            ServiceCfg(
                id: "claude",
                label: "Claude",
                kind: "jsonl",
                jsonl: JsonlCfg(
                    roots: ["~/.claude/projects", "~/.claude/sessions"],
                    idleMarkers: ["last-prompt"]
                ),
                traffic: TrafficCfg(pathPrefixes: [
                    "/Applications/Claude.app",
                    "/opt/homebrew/bin/claude",
                    "/usr/local/bin/claude",
                    "/opt/homebrew/Cellar/claude",
                ])
            ),
            ServiceCfg(
                id: "workbuddy",
                label: "WorkBuddy",
                kind: "jsonl",
                jsonl: JsonlCfg(
                    roots: ["~/.workbuddy/projects"],
                    idleMarkers: []
                ),
                traffic: TrafficCfg(pathPrefixes: ["/Applications/WorkBuddy.app"])
            ),
        ]
    }
}

// MARK: - 存取

final class ConfigStore {
    static let shared = ConfigStore()

    var config: AppConfig
    let fileURL: URL
    let dirURL: URL

    private init() {
        dirURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LidAssistant", isDirectory: true)
        fileURL = dirURL.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loaded
        } else {
            config = AppConfig()
            save()
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
