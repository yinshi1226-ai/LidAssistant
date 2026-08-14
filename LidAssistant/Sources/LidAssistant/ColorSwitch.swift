import AppKit

/// 可自定义颜色的滑动开关（macOS 原生 NSSwitch 不支持着色，故自绘）
/// - 开启：轨道填充 tintColor（如 橙/绿/蓝），白色滑块靠右
/// - 关闭：灰色轨道，白色滑块靠左
final class ColorSwitch: NSView {
    var isOn: Bool = false {
        didSet { needsDisplay = true }
    }

    var tintColor: NSColor = .systemBlue {
        didSet { needsDisplay = true }
    }

    var onToggle: ((Bool) -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 44, height: 24)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onToggle?(isOn)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 轨道
        let track = NSBezierPath(roundedRect: NSRect(x: 2, y: 5, width: 40, height: 14), xRadius: 7, yRadius: 7)
        if isOn {
            tintColor.setFill()
        } else {
            NSColor.systemGray.withAlphaComponent(0.45).setFill()
        }
        track.fill()

        // 滑块
        let knobX: CGFloat = isOn ? 24 : 4
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: 4, width: 16, height: 16)).fill()

        // 细描边，深浅色菜单栏下都清晰
        NSColor.black.withAlphaComponent(0.12).setStroke()
        track.lineWidth = 1
        track.stroke()
    }
}
