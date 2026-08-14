import AppKit

/// 设置窗口：自动休眠等待分钟数（可填小数）+ 各服务开关
final class SettingsWindowController: NSWindowController {
    private var minutesField: NSTextField!
    private var serviceButtons: [String: NSButton] = [:]
    private var blackScreenButton: NSButton!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "盒盖助手设置"
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.lineBreakMode = .byWordWrapping
        return l
    }

    private func buildContent() {
        let cfg = ConfigStore.shared.config
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
        ])

        // 分钟数
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let l1 = label("任务全部结束后，等待多久自动休眠（分钟）：")
        minutesField = NSTextField(string: String(cfg.graceMinutes))
        minutesField.placeholderString = "1"
        minutesField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        row.addArrangedSubview(l1)
        row.addArrangedSubview(minutesField)
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(label("说明：自动逻辑只在合盖时生效；开盖时完全跟随系统原生电源方案。"))

        // 合盖黑屏节能
        blackScreenButton = NSButton(
            checkboxWithTitle: "合盖保持运行期间，把内置屏亮度调到最低（黑屏节能）",
            target: nil, action: nil
        )
        blackScreenButton.state = cfg.blackScreenOnLidClose ? .on : .off
        stack.addArrangedSubview(blackScreenButton)

        stack.addArrangedSubview(label("监控哪些服务："))

        // 服务开关
        for s in cfg.services {
            let b = NSButton(checkboxWithTitle: "\(s.label)", target: nil, action: nil)
            b.state = s.enabled ? .on : .off
            serviceButtons[s.id] = b
            stack.addArrangedSubview(b)
        }

        // 按钮
        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 10
        let saveBtn = NSButton(title: "保存", target: self, action: #selector(save(_:)))
        let dirBtn = NSButton(title: "打开配置目录", target: self, action: #selector(openDir(_:)))
        let closeBtn = NSButton(title: "关闭", target: self, action: #selector(closeWindow(_:)))
        btnRow.addArrangedSubview(saveBtn)
        btnRow.addArrangedSubview(dirBtn)
        btnRow.addArrangedSubview(closeBtn)
        stack.addArrangedSubview(btnRow)
    }

    @objc private func save(_ sender: NSButton) {
        let store = ConfigStore.shared
        let v = Double(minutesField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        guard v > 0, v <= 1440 else {
            let alert = NSAlert()
            alert.messageText = "请输入有效的分钟数"
            alert.informativeText = "范围 0.1 – 1440（24 小时）"
            alert.runModal()
            return
        }
        store.config.graceMinutes = v
        store.config.blackScreenOnLidClose = blackScreenButton.state == .on
        for (id, btn) in serviceButtons {
            if let i = store.config.services.firstIndex(where: { $0.id == id }) {
                store.config.services[i].enabled = btn.state == .on
            }
        }
        store.save()
        Log.shared.info("设置已保存：graceMinutes=\(v) 黑屏=\(store.config.blackScreenOnLidClose)")
        let alert = NSAlert()
        alert.messageText = "已保存"
        alert.informativeText = "新设置在下一轮检测（5 秒内）生效。"
        alert.runModal()
    }

    @objc private func openDir(_ sender: NSButton) {
        NSWorkspace.shared.open(ConfigStore.shared.dirURL)
    }

    @objc private func closeWindow(_ sender: NSButton) {
        window?.close()
    }
}
