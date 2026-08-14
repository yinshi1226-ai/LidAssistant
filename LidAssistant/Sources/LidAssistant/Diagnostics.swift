import Foundation

/// 诊断信息（复制到剪贴板用）
enum Diagnostics {
    static func build(snapshot: Snapshot?) -> String {
        var lines: [String] = []
        lines.append("== 盒盖助手诊断 ==")
        lines.append("时间: \(Date())")

        let cfg = ConfigStore.shared.config
        lines.append("")
        lines.append("== 配置 ==")
        if let data = try? JSONEncoder().encode(cfg),
           let s = String(data: data, encoding: .utf8) {
            lines.append(s)
        }

        lines.append("")
        lines.append("== 当前状态 ==")
        if let s = snapshot {
            lines.append("模式: \(s.mode)")
            lines.append("任务活跃: \(s.tasksActive)")
            if let since = s.idleSince {
                lines.append("空闲起始: \(since)（\(Int(Date().timeIntervalSince(since)))s 前）")
            }
            lines.append("宽限: \(Int(s.graceSec))s")
            lines.append("HID 空闲: \(Int(s.hidIdleSec ?? -1))s")
            lines.append("合盖: \(s.lidClosed.map(String.init) ?? "未知")")
            lines.append("外部占用: \(s.externalHold)")
            lines.append("当前保持: \(s.held)")
            lines.append("sudo 免密: \(s.sudoOk)")
            for svc in s.services {
                lines.append("  \(svc.label): \(svc.stateText) | 最近活动 \(svc.ageText) | 尾部事件 \(svc.lastEvent) | 流量 \(svc.trafficBytes)B | \(svc.error ?? "")")
            }
        } else {
            lines.append("(尚无快照)")
        }

        lines.append("")
        lines.append("== pmset ==")
        let r = Proc.run("/usr/bin/pmset", ["-g"], timeout: 6)
        for l in r.stdout.components(separatedBy: "\n")
        where l.contains("SleepDisabled") || l.contains("disablesleep") || l.contains(" sleep") {
            lines.append(l.trimmingCharacters(in: .whitespaces))
        }

        lines.append("")
        lines.append("== 日志尾部 ==")
        lines.append(Log.shared.tail())

        return lines.joined(separator: "\n")
    }
}
