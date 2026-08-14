import Foundation

// MARK: - 探测结果模型

enum ProbeState: Equatable {
    case active
    case idle
    case unknown(String)
}

struct ServiceProbeResult {
    var state: ProbeState = .idle
    /// 最近一次观察到活动的距今秒数（nil = 从未观察到）
    var lastActivityAgeSec: Double?
    /// 日志尾部最后识别到的事件标记（诊断用）
    var lastEvent: String = ""
    var error: String?
    var runningCount: Int = 0
    var trafficBytes: UInt64 = 0
}

struct ProbeParams {
    var activeWindowSec: Double
    var trafficThresholdBytes: Double
}

// MARK: - 通用 jsonl 扫描

enum JsonlScanner {
    /// 在 roots 下找最新修改的 .jsonl 文件，返回 (路径, 距今秒数)
    static func newest(in roots: [String]) -> (path: String, age: Double)? {
        var best: (String, Double)? = nil
        for root in roots {
            let expanded = (root as NSString).expandingTildeInPath
            guard let en = FileManager.default.enumerator(atPath: expanded) else { continue }
            for case let file as String in en {
                guard file.hasSuffix(".jsonl") else { continue }
                let p = expanded + "/" + file
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: p),
                      let m = attrs[.modificationDate] as? Date else { continue }
                let age = Date().timeIntervalSince(m)
                if best == nil || age < best!.1 { best = (p, age) }
            }
        }
        return best
    }

    /// 读文件尾部若干行，提取“事件标记”列表（type / payload.type / payload.turn）
    static func tailMarkers(path: String, maxBytes: Int = 16_384) -> [String] {
        guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fh.close() }
        let size: UInt64
        do {
            size = try fh.seekToEnd()
        } catch {
            return []
        }
        let start = max(0, size - UInt64(maxBytes))
        try? fh.seek(toOffset: start)
        let data = fh.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var markers: [String] = []
        for line in text.components(separatedBy: "\n").suffix(30) where !line.isEmpty {
            guard let d = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            if let t = obj["type"] as? String { markers.append(t) }
            if let p = obj["payload"] as? [String: Any] {
                if let t = p["type"] as? String { markers.append("payload:\(t)") }
                if let turn = p["turn"] as? String { markers.append("turn:\(turn)") }
            }
        }
        return markers
    }
}

// MARK: - DeepSeek Harness 探测（权威：session.list API 的 running 字段）

final class DSHProbe {
    func sample(cfg: ServiceCfg, params: ProbeParams) -> ServiceProbeResult {
        var r = ServiceProbeResult()
        let base = cfg.dshBase ?? "http://127.0.0.1:3080"
        guard let url = URL(string: base + "/api/session.list") else {
            r.state = .unknown("地址无效")
            return r
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 2.5
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "type": "client-request",
            "rpcId": "lidassist-\(UUID().uuidString)",
            "method": "session.list",
            "payload": [String: Any](),
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var data: Data?
        var reqError: Error?
        URLSession.shared.dataTask(with: req) { d, _, e in
            data = d
            reqError = e
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)

        if let reqError {
            // API 不可达 → 回退为扫描 DSH 数据目录的最新文件活跃度
            if let dir = cfg.dshDataDir {
                let roots = [(dir as NSString).expandingTildeInPath + "/sessions"]
                if let newest = JsonlScanner.newest(in: roots) {
                    r.lastActivityAgeSec = newest.age
                    r.lastEvent = "文件回退"
                    if newest.age <= params.activeWindowSec {
                        r.state = .active
                        r.runningCount = 1
                    } else {
                        r.state = .idle
                    }
                    r.error = "API 不可达(\(reqError.localizedDescription))，使用数据目录回退"
                    return r
                }
            }
            r.state = .unknown(reqError.localizedDescription)
            r.error = reqError.localizedDescription
            return r
        }
        guard let data,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let value = result["value"] as? [String: Any],
              let items = value["items"] as? [[String: Any]] else {
            r.state = .unknown("响应解析失败")
            return r
        }
        var running = 0
        var newestMs: Double = 0
        for it in items {
            if it["running"] as? Bool == true { running += 1 }
            if let u = it["updatedAt"] as? Double { newestMs = max(newestMs, u) }
        }
        r.runningCount = running
        if newestMs > 0 {
            r.lastActivityAgeSec = max(0, Date().timeIntervalSince1970 - newestMs / 1000.0)
        }
        r.state = running > 0 ? .active : .idle
        r.lastEvent = running > 0 ? "running:\(running)" : "running:0"
        return r
    }
}

// MARK: - jsonl 日志探测（Codex / Claude / WorkBuddy）

final class JsonlProbe {
    func sample(cfg: ServiceCfg, params: ProbeParams) -> ServiceProbeResult {
        var r = ServiceProbeResult()
        guard let jc = cfg.jsonl else {
            r.state = .idle
            return r
        }
        guard let newest = JsonlScanner.newest(in: jc.roots) else {
            r.state = .idle // 没有日志 = 从未运行过任务
            return r
        }
        r.lastActivityAgeSec = newest.age
        let markers = JsonlScanner.tailMarkers(path: newest.path)
        r.lastEvent = markers.last ?? "(空)"
        let hasIdleMarker = jc.idleMarkers.contains { markers.contains($0) }
        if hasIdleMarker {
            r.state = .idle // 任务明确结束，即使日志刚刚写完也判空闲
        } else if newest.age <= params.activeWindowSec {
            r.state = .active
        } else {
            r.state = .idle
        }
        return r
    }
}

// MARK: - 网络流量佐证（nettop 两次采样相减，全服务共享采样）

final class TrafficProbe {
    static let shared = TrafficProbe()

    private var pidCache: (Date, [String: Set<Int32>])?
    private let queue = DispatchQueue(label: "lidassist.traffic", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var latest: [String: GroupResult] = [:]

    struct GroupResult {
        var bytes: UInt64 = 0
        var active: Bool = false
    }

    /// 最近一次采样结果（无锁读，供监控主循环直接使用）
    var latestResults: [String: GroupResult] {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    /// 在独立队列上每 20 秒采样一次；不占用监控主循环，避免拖慢模式切换
    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 20, leeway: .seconds(2))
        t.setEventHandler { [weak self] in
            self?.sampleOnce()
        }
        timer = t
        t.resume()
    }

    private func sampleOnce() {
        let cfg = ConfigStore.shared.config
        let groups: [(key: String, prefixes: [String], threshold: Double)] = cfg.services.compactMap { s in
            guard s.enabled, let tc = s.traffic, !tc.pathPrefixes.isEmpty else { return nil }
            return (s.id, tc.pathPrefixes, tc.thresholdBytes)
        }
        let res = sampleAll(groups: groups)
        lock.lock()
        latest = res
        lock.unlock()
    }

    private func nettopSample() -> [Int32: (UInt64, UInt64)] {
        let r = Proc.run("/usr/bin/nettop", ["-P", "-L", "1", "-J", "bytes_in,bytes_out"], timeout: 8)
        var map: [Int32: (UInt64, UInt64)] = [:]
        for line in r.stdout.components(separatedBy: "\n") {
            let parts = line.split(separator: ",")
            guard parts.count >= 3 else { continue }
            let namePid = parts[0].trimmingCharacters(in: .whitespaces)
            guard let dot = namePid.lastIndex(of: ".") else { continue }
            guard let pid = Int32(namePid[namePid.index(after: dot)...]) else { continue }
            guard let inB = UInt64(parts[1].trimmingCharacters(in: .whitespaces)),
                  let outB = UInt64(parts[2].trimmingCharacters(in: .whitespaces)) else { continue }
            map[pid] = (inB, outB)
        }
        return map
    }

    /// 一次 ps 扫描 + 两次 nettop 采样，为所有服务统计各自匹配进程的流量增量
    func sampleAll(groups: [(key: String, prefixes: [String], threshold: Double)]) -> [String: GroupResult] {
        guard !groups.isEmpty else { return [:] }
        var out: [String: GroupResult] = [:]

        // 1) ps 一次拿到全部前缀 → pid 映射（缓存 10 秒）
        let now = Date()
        let allPrefixes = groups.flatMap { $0.prefixes }
        var pidByPrefix: [String: Set<Int32>] = [:]
        if let c = pidCache, now.timeIntervalSince(c.0) < 10 {
            pidByPrefix = c.1
        } else {
            var sets: [String: Set<Int32>] = [:]
            let r = Proc.run("/bin/ps", ["-axo", "pid=,args="], timeout: 8)
            for line in r.stdout.components(separatedBy: "\n") {
                guard let sp = line.firstIndex(of: " ") else { continue }
                let pidText = line[..<sp].trimmingCharacters(in: .whitespaces)
                guard let pid = Int32(pidText) else { continue }
                let args = String(line[line.index(after: sp)...])
                for prefix in allPrefixes where args.contains(prefix) {
                    sets[prefix, default: []].insert(pid)
                }
            }
            pidByPrefix = sets
            pidCache = (now, sets)
        }

        // 2) nettop 两次采样相减（计数器为累计值）
        let s1 = nettopSample()
        Thread.sleep(forTimeInterval: 1.0)
        let s2 = nettopSample()

        // 3) 按服务汇总
        for g in groups {
            let pids = Set(g.prefixes.flatMap { Array(pidByPrefix[$0] ?? []) })
            var total: UInt64 = 0
            for pid in pids {
                guard let a = s1[pid], let b = s2[pid] else { continue }
                let din = b.0 >= a.0 ? b.0 - a.0 : 0
                let dout = b.1 >= a.1 ? b.1 - a.1 : 0
                total += din + dout
            }
            out[g.key] = GroupResult(bytes: total, active: total >= UInt64(g.threshold))
        }
        return out
    }
}
