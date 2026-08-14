import Foundation
import AppKit

// MARK: - 快照模型（供 UI 展示）

struct ServiceStatus {
    let id: String
    let label: String
    var enabled: Bool = true
    var state: ProbeState = .idle
    var lastActivityAgeSec: Double?
    var lastEvent: String = ""
    var error: String?
    var runningCount: Int = 0
    var trafficBytes: UInt64 = 0

    var stateText: String {
        if !enabled { return "已停用" }
        switch state {
        case .active: return runningCount > 1 ? "运行中(\(runningCount))" : "运行中"
        case .idle: return "空闲"
        case .unknown(let e): return "不可用: \(e)"
        }
    }

    var ageText: String {
        guard let age = lastActivityAgeSec else { return "无记录" }
        if age < 10 { return "刚刚" }
        if age < 60 { return "\(Int(age)) 秒前" }
        if age < 3600 { return "\(Int(age / 60)) 分钟前" }
        if age < 86400 { return "\(Int(age / 3600)) 小时前" }
        return "\(Int(age / 86400)) 天前"
    }
}

struct Snapshot {
    var mode: String
    var manualBlock: Bool
    var services: [ServiceStatus]
    var tasksActive: Bool
    var idleSince: Date?
    var graceSec: Double
    var hidIdleSec: Double?
    var lidClosed: Bool?
    var externalHold: Bool
    var held: Bool
    var sudoOk: Bool
    var lastAutoSleepAt: Date?
    /// 检测到外接屏幕：程序停用，不做任何干预
    var externalDisplay: Bool
}

// MARK: - 监控状态机

final class TaskMonitor {
    private let queue = DispatchQueue(label: "lidassist.monitor", qos: .utility)
    private let holdQueue = DispatchQueue(label: "lidassist.hold") // 快速队列：保持/释放立即生效
    private var timer: DispatchSourceTimer?
    private var lidTimer: DispatchSourceTimer?
    var onUpdate: ((Snapshot) -> Void)?

    let dryRun: Bool

    private var idleSince: Date?
    private var slept = false
    private var heldByUs = false
    private var trafficExtendUntil = Date.distantPast
    private var lastSnapshot: Snapshot?
    private var cycleCount = 0
    private var lastCountdownStatus = ""
    private var lastLid: Bool?
    private var externalPresent = false
    private var lastExternal: Bool?
    private var lastAutoSleepAt: Date?

    private let dshProbe = DSHProbe()
    private let jsonlProbe = JsonlProbe()

    init(dryRun: Bool) {
        self.dryRun = dryRun
        let ts = UserDefaults.standard.double(forKey: "lastAutoSleepAt")
        lastAutoSleepAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.slept = false
                self.idleSince = nil
                self.trafficExtendUntil = .distantPast
                Log.shared.info("系统已唤醒，重新武装监控")
            }
        }
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { _ in
            Log.shared.info("系统进入休眠")
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: ConfigStore.shared.config.pollIntervalSec, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in
            self?.cycle()
        }
        timer = t
        t.resume()

        // 合盖状态快速轮询（1 秒）：合盖瞬间立刻进入自动逻辑，防止系统休眠抢跑
        let lidT = DispatchSource.makeTimerSource(queue: queue)
        lidT.schedule(deadline: .now() + 0.5, repeating: 1.0, leeway: .milliseconds(200))
        lidT.setEventHandler { [weak self] in
            self?.lidTick()
        }
        lidTimer = lidT
        lidT.resume()

        // 流量佐证在独立队列上运行，不占用本监控队列
        TrafficProbe.shared.start()
        Log.shared.info("监控启动（dryRun=\(dryRun)）")
    }

    /// 合盖状态/外接屏变化：
    /// - 检测到外接屏：程序停用，立即释放一切干预
    /// - 合上（无外接屏）：自动模式重计宽限并立即处理；保持清醒时把内置屏亮度调到最低（黑屏节能）
    /// - 打开（无外接屏）：恢复内置屏亮度；自动模式立即处理
    private func lidTick() {
        let cfg = ConfigStore.shared.config
        let lid = SleepController.shared.lidClosed() ?? false
        let ext = BrightnessController.shared.hasExternalDisplay()

        if let prev = lastExternal, prev != ext {
            lastExternal = ext
            Log.shared.info(ext ? "检测到外接屏幕，程序停用（不做任何干预）" : "外接屏已移除，恢复工作")
            idleSince = nil
            lastCountdownStatus = ""
            if !ext { BrightnessController.shared.restore() }
            cycle()
            return
        }
        lastExternal = ext
        if ext { return } // 停用状态：不干预

        if let prev = lastLid, prev != lid {
            Log.shared.info("合盖状态变化：\(lid ? "已合盖" : "已开盖")")
            if lid {
                if cfg.mode == "auto" {
                    idleSince = nil
                    lastCountdownStatus = ""
                }
                let keepingAwake = cfg.mode == "auto" || (cfg.mode == "manual" && cfg.manualBlock)
                if cfg.blackScreenOnLidClose && keepingAwake {
                    Log.shared.info("合盖黑屏：准备把内置屏亮度调到最低（显示器不休眠）")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                        if SleepController.shared.lidClosed() == true,
                           !BrightnessController.shared.hasExternalDisplay() {
                            BrightnessController.shared.dimBuiltin()
                        }
                    }
                }
                if cfg.mode == "auto" { cycle() }
            } else {
                BrightnessController.shared.restore()
                if cfg.mode == "auto" { cycle() }
            }
        }
        lastLid = lid
    }

    /// 用户点击“立即休眠”
    func sleepNowUserRequested() {
        queue.async { [weak self] in
            guard let self else { return }
            Log.shared.info("用户手动请求立即休眠")
            self.slept = true
            self.ensureHold(false)
            if !self.dryRun {
                SleepController.shared.sleepNow()
            }
        }
    }

    /// 模式/开关切换后：开关状态走快速队列立即生效（不等探测），随后再完整刷新
    func applyModeNow() {
        let cfg = ConfigStore.shared.config
        queue.async { [weak self] in
            guard let self else { return }
            self.idleSince = nil
            self.slept = false
            self.cycle()
        }
        // 快速生效：手动模式按当前开关、自动模式先保持（下一轮检测会按任务状态校正）
        holdQueue.async { [weak self] in
            self?.setHold(cfg.mode == "manual" ? cfg.manualBlock : true)
        }
    }

    // MARK: - 主循环

    private func cycle() {
        let cycleStart = Date()
        let cfg = ConfigStore.shared.config
        let params = ProbeParams(
            activeWindowSec: cfg.activeWindowSec,
            trafficThresholdBytes: 10_000
        )

        var statuses: [ServiceStatus] = []
        var tasksActive = false
        var effectiveActive = false
        var external = false
        var lid: Bool?
        var hidIdle: Double?
        let grace = max(1, cfg.graceMinutes * 60)

        // 外接屏检测：存在则程序停用，不做任何干预
        let ext = BrightnessController.shared.hasExternalDisplay()
        externalPresent = ext

        if ext {
            // 停用：释放保持、不探测、不强制休眠，完全跟随系统
            if idleSince != nil {
                idleSince = nil
                lastCountdownStatus = ""
            }
            ensureHold(false)
            statuses = cfg.services.map { ServiceStatus(id: $0.id, label: $0.label, enabled: false) }
            lid = SleepController.shared.lidClosed()
        } else {
            // 第一遍：权威状态探测（DSH API / jsonl 日志）
            for s in cfg.services {
                var st = ServiceStatus(id: s.id, label: s.label, enabled: s.enabled)
                guard s.enabled else {
                    statuses.append(st)
                    continue
                }
                let base: ServiceProbeResult
                switch s.kind {
                case "dsh":
                    base = dshProbe.sample(cfg: s, params: params)
                default:
                    base = jsonlProbe.sample(cfg: s, params: params)
                }
                st.state = base.state
                st.lastActivityAgeSec = base.lastActivityAgeSec
                st.lastEvent = base.lastEvent
                st.error = base.error
                st.runningCount = base.runningCount
                if base.state == .active { tasksActive = true }
                statuses.append(st)
            }

            // 第二遍：流量佐证——读独立队列采样的最新结果（不阻塞主循环）
            // 仅当该服务近期（10 分钟内）有过日志活动时才接受流量佐证，避免后台同步噪声长期阻止休眠
            if !tasksActive {
                let trafficResults = TrafficProbe.shared.latestResults
                for i in statuses.indices {
                    guard let tr = trafficResults[statuses[i].id] else { continue }
                    statuses[i].trafficBytes = tr.bytes
                    let recent = (statuses[i].lastActivityAgeSec ?? .infinity) < 600
                    if tr.active, recent, let tc = cfg.services.first(where: { $0.id == statuses[i].id })?.traffic {
                        trafficExtendUntil = Date().addingTimeInterval(tc.extendSeconds)
                        if !statuses[i].lastEvent.contains("+流量") {
                            statuses[i].lastEvent += " +流量\(tr.bytes)B"
                        }
                    }
                }
            }

            effectiveActive = tasksActive || Date() < trafficExtendUntil
            hidIdle = SleepController.shared.systemIdleSeconds()
            external = SleepController.shared.externalSleepAssertions()
            lid = SleepController.shared.lidClosed()
            let lidClosedNow = lid ?? false

            // —— 状态机 ——
            switch cfg.mode {
            case "manual":
                idleSince = nil
                lastCountdownStatus = ""
                ensureHold(cfg.manualBlock)
            default: // auto：完整逻辑只在合盖时生效，开盖时完全跟随系统原生方案
                if effectiveActive {
                    // 任务运行中：保持清醒（开盖/合盖都保持——这是合盖瞬间任务不被系统休眠杀掉的唯一可靠保障）
                    if idleSince != nil {
                        Log.shared.info("检测到任务恢复活跃，取消空闲计时")
                    }
                    idleSince = nil
                    lastCountdownStatus = ""
                    ensureHold(true)
                } else if lidClosedNow {
                    // 合盖 + 无任务：宽限 N 分钟后休眠
                    if idleSince == nil {
                        idleSince = Date()
                        lastCountdownStatus = ""
                        Log.shared.info("已合盖且无任务，开始 \(Int(grace)) 秒宽限计时")
                    }
                    let elapsed = Date().timeIntervalSince(idleSince!)
                    if elapsed >= grace && !external {
                        if !slept {
                            Log.shared.info("合盖空闲 \(Int(elapsed))s ≥ \(Int(grace))s、无外部占用 → 进入休眠")
                            slept = true
                            ensureHold(false)
                            if !dryRun {
                                lastAutoSleepAt = Date()
                                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAutoSleepAt")
                                SleepController.shared.sleepNow()
                            } else {
                                Log.shared.info("dry-run：跳过真实休眠")
                            }
                        }
                    } else {
                        if !heldByUs {
                            ensureHold(true)
                        }
                        let statusKey = "合盖空闲\(Int(elapsed))s/需\(Int(grace))s 外部占用\(external)"
                        if statusKey != lastCountdownStatus {
                            lastCountdownStatus = statusKey
                            Log.shared.info("倒计时等待: \(statusKey)")
                        }
                    }
                } else {
                    // 开盖 + 无任务：完全跟随系统原生方案（不保持清醒、不强制休眠）
                    if idleSince != nil {
                        idleSince = nil
                        lastCountdownStatus = ""
                        Log.shared.info("已开盖且无任务，释放控制，跟随系统电源设置")
                    }
                    ensureHold(false)
                }
            }
        }

        // 心跳（看门狗用；dry-run 不写，避免干扰真实实例）
        if !dryRun {
            let hb = ConfigStore.shared.dirURL.appendingPathComponent("heartbeat").path
            FileManager.default.createFile(atPath: hb, contents: nil)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: hb)
        }

        let snap = Snapshot(
            mode: cfg.mode,
            manualBlock: cfg.manualBlock,
            services: statuses,
            tasksActive: effectiveActive,
            idleSince: idleSince,
            graceSec: grace,
            hidIdleSec: hidIdle,
            lidClosed: lid,
            externalHold: external,
            held: holdQueue.sync { heldByUs },
            sudoOk: SleepController.shared.sudoAvailable(),
            lastAutoSleepAt: lastAutoSleepAt,
            externalDisplay: ext
        )
        lastSnapshot = snap

        // 周期状态快照（约每分钟一次，供日志排障）+ 耗时监测
        cycleCount += 1
        let dur = Date().timeIntervalSince(cycleStart)
        if dur > 3 {
            Log.shared.warn("本轮检测耗时 \(String(format: "%.1f", dur))s（偏慢，若频繁出现请反馈诊断信息）")
        }
        if cycleCount % 12 == 1 {
            let summary = statuses.map { s -> String in
                var t = "\(s.label)=\(s.stateText)"
                if s.trafficBytes > 0 { t += "(流量\(s.trafficBytes)B)" }
                if let e = s.error { t += "(\(e))" }
                return t
            }.joined(separator: " ")
            let heldNow = holdQueue.sync { heldByUs }
            Log.shared.info("快照: 活跃=\(effectiveActive) | \(summary) | 外接=\(ext) 合盖=\(String(describing: lid)) 外部占用=\(external) 保持=\(heldNow) 耗时=\(String(format: "%.1f", dur))s")
        }

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snap)
        }
    }

    func currentSnapshot() -> Snapshot? { lastSnapshot }

    /// 快速队列上执行：真正写 pmset（执行时读最新配置；手动模式下永远以开关为准）
    private func setHold(_ target: Bool) {
        let cfg = ConfigStore.shared.config
        var final = target
        if cfg.mode == "manual" { final = cfg.manualBlock }
        if heldByUs == final { return }
        if dryRun {
            heldByUs = final
            Log.shared.info("dry-run：disablesleep → \(final ? 1 : 0)")
            return
        }
        if SleepController.shared.setDisableSleep(final) {
            heldByUs = final
            Log.shared.info("disablesleep → \(final ? 1 : 0)")
        }
    }

    /// 统一入口：在快速队列上同步执行（保持/释放立即生效，不被探测拖慢）
    private func ensureHold(_ on: Bool) {
        holdQueue.sync { setHold(on) }
    }
}
