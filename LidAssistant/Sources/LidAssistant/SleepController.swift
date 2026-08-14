import Foundation
import IOKit

/// 电源控制：pmset（免密 sudo）、HID 空闲时长、合盖状态、外部占用检查
final class SleepController {
    static let shared = SleepController()
    private init() {}

    // MARK: - pmset

    /// 需要 /etc/sudoers.d/lidassist 免密授权（install.sh 安装）
    @discardableResult
    func setDisableSleep(_ on: Bool) -> Bool {
        let r = Proc.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"], timeout: 8)
        if r.status != 0 {
            Log.shared.error("pmset disablesleep 失败: \(r.stderr.isEmpty ? "sudo 拒绝（未完成安装？）" : r.stderr)")
            return false
        }
        return true
    }

    /// 当前 disablesleep 值（仅诊断显示）
    /// macOS 26 起 pmset -g 里显示为 SleepDisabled；旧系统为 disablesleep。无该行即视为 0
    func currentDisableSleep() -> Bool? {
        let r = Proc.run("/usr/bin/pmset", ["-g"], timeout: 6)
        for line in r.stdout.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            for key in ["SleepDisabled", "disablesleep"] {
                if t.hasPrefix(key) {
                    let parts = t.split(separator: " ")
                    if parts.count >= 2, let v = Int(parts[1]) { return v == 1 }
                    return false
                }
            }
        }
        return false
    }

    /// 立即休眠（无需 sudo）
    func sleepNow() {
        _ = Proc.run("/usr/bin/pmset", ["sleepnow"], timeout: 6)
    }

    /// 关闭所有显示器（合盖黑屏节能；无需 sudo，系统继续运行）
    func displaySleepNow() {
        _ = Proc.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 6)
    }

    /// 唤醒显示器（模拟用户活动，无需 sudo）
    func wakeDisplay() {
        _ = Proc.run("/usr/bin/caffeinate", ["-u", "-t", "1"], timeout: 6)
    }

    /// sudo 免密是否可用（诊断用）
    func sudoAvailable() -> Bool {
        Proc.run("/usr/bin/sudo", ["-n", "true"], timeout: 5).status == 0
    }

    // MARK: - IOKit 状态

    /// 距上次键盘/鼠标输入的秒数（IOHIDSystem HIDIdleTime，纳秒）
    func systemIdleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let v = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return nil }
        return v.doubleValue / 1_000_000_000.0
    }

    /// 合盖状态（IOPMrootDomain 的 AppleClamshellState）
    func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let v = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return v as? Bool
    }

    /// 是否有其他进程持有系统休眠阻止断言（排除自身与 powerd 的“显示器亮着”）
    func externalSleepAssertions() -> Bool {
        let r = Proc.run("/usr/bin/pmset", ["-g", "assertions"], timeout: 6)
        let ownPid = ProcessInfo.processInfo.processIdentifier
        var inSection = false
        for line in r.stdout.components(separatedBy: "\n") {
            if line.contains("Listed by owning process") { inSection = true; continue }
            guard inSection else { continue }
            if !line.contains("PreventSystemSleep") { continue }
            if line.contains("Powerd - Prevent sleep while display is on") { continue }
            var pid: Int32? = nil
            if let rr = line.range(of: "pid ") {
                let rest = line[rr.upperBound...]
                let digits = rest.prefix(while: { $0.isNumber })
                pid = Int32(digits)
            }
            if let pid, pid == ownPid { continue }
            return true
        }
        return false
    }
}
