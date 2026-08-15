import AppKit

/// 菜单栏控制器：彩色圆点图标 + 菜单
///
/// 菜单结构（分区清晰、信息精简）：
///   模式  [自动 | 手动]
///   ─────────────
///   手动：合盖休眠 [开关] 合盖不眠
///   自动：任务状态（各服务一行 + 状态行 + 上次自动休眠）
///   ─────────────
///   ✓ 合盖时黑屏节能（亮度调至最低）
///   休眠等待：N 分钟 ▸（仅自动）
///   ─────────────
///   立即休眠 / 打开日志 / 复制诊断信息 / 设置…
///   ─────────────
///   退出盒盖助手
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let monitor: TaskMonitor
    private let config = ConfigStore.shared

    // 模式选择（分段控件：自动 | 手动）
    private var modeSegmentItem: NSMenuItem!
    private var modeSegment: NSSegmentedControl!

    // 手动模式：滑动开关（合盖休眠 ⇄ 合盖不眠）
    private var manualSwitchItem: NSMenuItem!
    private var manualSwitch: ColorSwitch!

    // 自动模式：任务状态区
    private var serviceHeaderItem: NSMenuItem!
    private var serviceItems: [NSMenuItem] = []
    private var statusLineItem: NSMenuItem!
    private var lastSleepItem: NSMenuItem!

    // 选项区
    private var blackScreenItem: NSMenuItem!
    private var blackScreenSwitch: ColorSwitch!
    private var sleepTimeParent: NSMenuItem!
    private var sleepTimeItems: [NSMenuItem] = []

    private var settingsWindow: NSWindowController?
    private var didLogMount = false
    private var dotCache: [String: NSImage] = [:]

    private static let sleepTimes: [(label: String, minutes: Double)] = [
        ("30 秒", 0.5), ("1 分钟", 1), ("2 分钟", 2), ("3 分钟", 3),
        ("5 分钟", 5), ("10 分钟", 10), ("15 分钟", 15), ("30 分钟", 30), ("60 分钟", 60),
    ]

    init(monitor: TaskMonitor) {
        self.monitor = monitor
        super.init()

        // 状态栏图标：纯色圆点（绿=空闲/正常，橙=手动合盖不眠，红=任务运行中，灰=已停用）
        if let button = statusItem.button {
            button.image = dot("green")
            button.title = ""
            button.toolTip = "盒盖助手"
        }
        buildMenu()
        statusItem.menu = menu
        menu.delegate = self
    }

    /// 只用于安全演示和 README 截图；正常启动仍由菜单栏圆点打开。
    func showMenuForDemo() {
        guard let frame = NSScreen.main?.visibleFrame else {
            statusItem.button?.performClick(nil)
            return
        }
        menu.popUp(positioning: nil, at: NSPoint(x: frame.midX - 170, y: frame.midY + 220), in: nil)
    }

    // MARK: - 图标

    private func dot(_ name: String) -> NSImage {
        if let c = dotCache[name] { return c }
        let color: NSColor
        switch name {
        case "red": color = .systemRed
        case "orange": color = .systemOrange
        case "gray": color = .systemGray
        default: color = .systemGreen
        }
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size)
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 14, height: 14)).fill()
        img.unlockFocus()
        dotCache[name] = img
        return img
    }

    private func dotName(for snap: Snapshot) -> String {
        if snap.externalDisplay { return "gray" }
        switch snap.mode {
        case "manual":
            return snap.manualBlock ? "orange" : "green"
        default:
            return snap.tasksActive ? "red" : "green"
        }
    }

    // MARK: - 菜单构建

    private func buildMenu() {
        menu.removeAllItems()
        serviceItems = []
        sleepTimeItems = []

        // ── 模式：原生标题 + 分段控件（与「任务状态」标题风格一致，行高/边距对齐原生）──
        let modeHeader = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)

        modeSegment = NSSegmentedControl(
            labels: ["自动", "手动"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeSegmentChanged(_:))
        )
        modeSegment.segmentStyle = .rounded
        modeSegment.sizeToFit()
        let segView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        let segH = modeSegment.frame.height
        modeSegment.frame = NSRect(x: 19, y: (24 - segH) / 2, width: modeSegment.frame.width, height: segH)
        segView.addSubview(modeSegment)
        modeSegmentItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        modeSegmentItem.view = segView
        menu.addItem(modeSegmentItem)
        menu.addItem(.separator())

        // ── 手动：滑动开关（自定义着色控件，行高 24、文字与原生菜单项对齐）──
        manualSwitch = ColorSwitch()
        manualSwitch.onToggle = { [weak self] on in
            guard let self else { return }
            self.config.config.manualBlock = on
            self.config.save()
            // 立即反馈：图标与开关颜色马上切换，不等待下一轮检测
            self.statusItem.button?.image = self.dot(on ? "orange" : "green")
            self.manualSwitch.tintColor = on ? .systemOrange : .systemGreen
            Log.shared.info("手动开关 → \(on ? "合盖不眠" : "合盖休眠")")
            self.monitor.applyModeNow()
        }
        let switchView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        let left = NSTextField(labelWithString: "合盖休眠")
        left.sizeToFit()
        // x=15：补偿 menuItem.view 的约 4pt 自动内缩，使文字与原生菜单项精确对齐
        left.frame = NSRect(x: 15, y: 4, width: left.frame.width, height: 16)
        manualSwitch.frame = NSRect(x: left.frame.maxX + 6, y: 0, width: 44, height: 24)
        let right = NSTextField(labelWithString: "合盖不眠")
        right.sizeToFit()
        right.frame = NSRect(x: manualSwitch.frame.maxX + 6, y: 4, width: right.frame.width, height: 16)
        switchView.addSubview(left)
        switchView.addSubview(manualSwitch)
        switchView.addSubview(right)
        manualSwitchItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        manualSwitchItem.view = switchView
        menu.addItem(manualSwitchItem)

        // ── 自动：任务状态区 ──
        serviceHeaderItem = NSMenuItem(title: "任务状态", action: nil, keyEquivalent: "")
        serviceHeaderItem.isEnabled = false
        serviceHeaderItem.indentationLevel = 1
        for _ in config.config.services {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            serviceItems.append(item)
        }
        statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        statusLineItem.indentationLevel = 1
        lastSleepItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lastSleepItem.isEnabled = false
        lastSleepItem.indentationLevel = 1

        menu.addItem(serviceHeaderItem)
        for it in serviceItems { menu.addItem(it) }
        menu.addItem(statusLineItem)
        menu.addItem(lastSleepItem)
        menu.addItem(.separator())

        // ── 选项区 ──
        // 黑屏节能：滑动开关（自定义着色控件，打开=蓝色）
        blackScreenSwitch = ColorSwitch()
        blackScreenSwitch.tintColor = .systemBlue
        blackScreenSwitch.onToggle = { [weak self] on in
            guard let self else { return }
            self.config.config.blackScreenOnLidClose = on
            self.config.save()
            Log.shared.info("合盖黑屏节能 → \(on ? "开" : "关")")
        }
        let bsLabel = NSTextField(labelWithString: "合盖时黑屏节能（亮度调至最低）")
        bsLabel.sizeToFit()
        let bsView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        // x=15：补偿 menuItem.view 的约 4pt 自动内缩，使文字与原生菜单项精确对齐
        bsLabel.frame = NSRect(x: 15, y: 4, width: bsLabel.frame.width, height: 16)
        blackScreenSwitch.frame = NSRect(x: bsLabel.frame.maxX + 8, y: 0, width: 44, height: 24)
        bsView.addSubview(bsLabel)
        bsView.addSubview(blackScreenSwitch)
        blackScreenItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        blackScreenItem.view = bsView
        menu.addItem(blackScreenItem)

        sleepTimeParent = NSMenuItem(title: "休眠等待：1 分钟", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "")
        for (label, mins) in Self.sleepTimes {
            let it = NSMenuItem(title: label, action: #selector(selectSleepTime(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = mins
            sub.addItem(it)
            sleepTimeItems.append(it)
        }
        let custom = NSMenuItem(title: "自定义…", action: #selector(openSettings(_:)), keyEquivalent: "")
        custom.target = self
        sub.addItem(custom)
        sleepTimeParent.submenu = sub
        menu.addItem(sleepTimeParent)
        menu.addItem(.separator())

        // ── 操作区 ──
        let sleepItem = NSMenuItem(title: "立即休眠", action: #selector(sleepNow(_:)), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)
        let logItem = NSMenuItem(title: "打开日志", action: #selector(openLog(_:)), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        let diagItem = NSMenuItem(title: "复制诊断信息", action: #selector(copyDiagnostics(_:)), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出盒盖助手", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - 刷新

    func update(_ snap: Snapshot) {
        statusItem.button?.image = dot(dotName(for: snap))

        // ── 外接屏：停用态 ──
        if snap.externalDisplay {
            modeSegment.isEnabled = false
            manualSwitchItem.isHidden = true
            serviceHeaderItem.isHidden = true
            for it in serviceItems { it.isHidden = true }
            statusLineItem.isHidden = false
            statusLineItem.title = "⚪ 已停用：检测到外接屏幕，拔掉后自动恢复"
            lastSleepItem.isHidden = true
            sleepTimeParent.isHidden = true
            blackScreenItem.isHidden = true
            statusItem.button?.toolTip = "盒盖助手：已停用（检测到外接屏幕）"
            if !didLogMount {
                didLogMount = true
                let w = statusItem.button?.frame.width ?? -1
                Log.shared.info("状态栏项目已挂载: visible=\(statusItem.isVisible) 宽度=\(Int(w))px")
            }
            return
        }
        modeSegment.isEnabled = true
        blackScreenItem.isHidden = false

        let isAuto = snap.mode == "auto"
        modeSegment.selectedSegment = isAuto ? 0 : 1
        manualSwitchItem.isHidden = isAuto
        serviceHeaderItem.isHidden = !isAuto
        for it in serviceItems { it.isHidden = !isAuto }
        statusLineItem.isHidden = !isAuto
        lastSleepItem.isHidden = !isAuto
        sleepTimeParent.isHidden = !isAuto

        if !isAuto {
            manualSwitch.isOn = snap.manualBlock
            // 开关颜色与状态栏圆点一致：合盖不眠=橙、合盖休眠=绿
            manualSwitch.tintColor = snap.manualBlock ? .systemOrange : .systemGreen
        }

        // ── 自动：服务行（颜色圆点 + 状态，一行讲清）──
        for (i, item) in serviceItems.enumerated() {
            guard i < snap.services.count else { continue }
            let s = snap.services[i]
            let line: String
            if !s.enabled {
                line = "⚪ \(s.label) · 已停用"
            } else {
                switch s.state {
                case .active:
                    line = "🔴 \(s.label) · 运行中"
                case .idle:
                    line = "⚪ \(s.label) · 空闲 · \(s.ageText)"
                case .unknown:
                    line = "🟡 \(s.label) · 不可用"
                }
            }
            item.title = line
        }

        // ── 自动：状态行 + 上次自动休眠 ──
        if isAuto {
            if snap.tasksActive {
                statusLineItem.title = "🔴 有任务在运行 · 保持清醒"
            } else if snap.lidClosed == true, let since = snap.idleSince {
                let elapsed = Date().timeIntervalSince(since)
                var t = String(format: "⏳ 空闲 %d 秒 / %d 秒后休眠", Int(elapsed), Int(snap.graceSec))
                if snap.externalHold { t += " · ⚠️ 有外部占用" }
                statusLineItem.title = t
            } else {
                statusLineItem.title = "🟢 跟随系统设置（合盖后自动介入）"
            }
            lastSleepItem.title = "上次自动休眠：" + fmtLastSleep(snap.lastAutoSleepAt)
        }

        sleepTimeParent.title = "休眠等待：" + fmtMinutes(config.config.graceMinutes)
        for it in sleepTimeItems {
            let mins = it.representedObject as? Double ?? -1
            it.state = abs(mins - config.config.graceMinutes) < 0.001 ? .on : .off
        }
        blackScreenSwitch.isOn = config.config.blackScreenOnLidClose
        // 黑屏节能开关：打开时为蓝色
        blackScreenSwitch.tintColor = .systemBlue

        statusItem.button?.toolTip = buildTooltip(snap)

        if !didLogMount {
            didLogMount = true
            let w = statusItem.button?.frame.width ?? -1
            Log.shared.info("状态栏项目已挂载: visible=\(statusItem.isVisible) 宽度=\(Int(w))px")
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        modeSegment.selectedSegment = config.config.mode == "auto" ? 0 : 1
        manualSwitch.isOn = config.config.manualBlock
        manualSwitch.tintColor = config.config.manualBlock ? .systemOrange : .systemGreen
        blackScreenSwitch.isOn = config.config.blackScreenOnLidClose
        blackScreenSwitch.tintColor = .systemBlue
        sleepTimeParent.title = "休眠等待：" + fmtMinutes(config.config.graceMinutes)
        for it in sleepTimeItems {
            let mins = it.representedObject as? Double ?? -1
            it.state = abs(mins - config.config.graceMinutes) < 0.001 ? .on : .off
        }
    }

    private func buildTooltip(_ snap: Snapshot) -> String {
        var lines = ["盒盖助手"]
        if !snap.sudoOk {
            lines.append("⚠️ 未完成安装（sudo 免密不可用）——请运行 install.sh")
        }
        if snap.externalDisplay {
            lines.append("⚪ 已停用：检测到外接屏幕")
            return lines.joined(separator: "\n")
        }
        switch snap.mode {
        case "manual":
            lines.append(snap.manualBlock ? "🟠 合盖不眠（保持清醒）" : "🟢 合盖休眠（正常）")
        default:
            if snap.tasksActive {
                let names = snap.services.filter { $0.state == .active }.map { $0.label }.joined(separator: "、")
                lines.append("🔴 任务运行中：\(names)")
            } else if snap.lidClosed == true {
                lines.append("🟢 合盖无任务 · \(fmtMinutes(config.config.graceMinutes)) 后休眠")
            } else {
                lines.append("🟢 跟随系统设置")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func fmtLastSleep(_ date: Date?) -> String {
        guard let d = date else { return "无记录" }
        let hm = DateFormatter()
        hm.dateFormat = "HH:mm"
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天 " + hm.string(from: d) }
        if cal.isDateInYesterday(d) { return "昨天 " + hm.string(from: d) }
        let md = DateFormatter()
        md.dateFormat = "M月d日 HH:mm"
        return md.string(from: d)
    }

    private func fmtMinutes(_ m: Double) -> String {
        if m < 1 { return "\(Int(m * 60)) 秒" }
        if m == Double(Int(m)) { return "\(Int(m)) 分钟" }
        return "\(m) 分钟"
    }

    // MARK: - Actions

    @objc private func modeSegmentChanged(_ sender: NSSegmentedControl) {
        let mode = sender.selectedSegment == 0 ? "auto" : "manual"
        guard config.config.mode != mode else { return }
        config.config.mode = mode
        config.save()
        // 立即反馈：分区马上切换
        let isAuto = mode == "auto"
        manualSwitchItem.isHidden = isAuto
        serviceHeaderItem.isHidden = !isAuto
        for it in serviceItems { it.isHidden = !isAuto }
        statusLineItem.isHidden = !isAuto
        lastSleepItem.isHidden = !isAuto
        sleepTimeParent.isHidden = !isAuto
        Log.shared.info("模式切换 → \(mode)")
        monitor.applyModeNow()
    }

    @objc private func selectSleepTime(_ sender: NSMenuItem) {
        guard let mins = sender.representedObject as? Double else { return }
        config.config.graceMinutes = mins
        config.save()
        Log.shared.info("休眠等待 → \(fmtMinutes(mins))")
        monitor.applyModeNow()
    }

    @objc private func sleepNow(_ sender: NSMenuItem) {
        monitor.sleepNowUserRequested()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openLog(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: Log.shared.path))
    }

    @objc private func copyDiagnostics(_ sender: NSMenuItem) {
        let text = Diagnostics.build(snapshot: monitor.currentSnapshot())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let alert = NSAlert()
        alert.messageText = "诊断信息已复制到剪贴板"
        alert.informativeText = "粘贴给开发者即可排查检测不准的问题。"
        alert.runModal()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
