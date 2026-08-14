import Foundation
import CoreGraphics
import Darwin

/// 内置显示器亮度控制（合盖黑屏节能）与外接屏检测
final class BrightnessController {
    static let shared = BrightnessController()

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getFn: GetFn?
    private var setFn: SetFn?
    private var saved: [CGDirectDisplayID: Float] = [:]
    private let lock = NSLock()

    private init() {
        // macOS 26 起亮度接口位于 DisplayServices 私有框架（旧系统在 CoreDisplay）
        let paths = [
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        ]
        for p in paths {
            if let h = dlopen(p, RTLD_LAZY) {
                if let s = dlsym(h, "DisplayServicesGetBrightness") {
                    getFn = unsafeBitCast(s, to: GetFn.self)
                }
                if let s = dlsym(h, "DisplayServicesSetBrightness") {
                    setFn = unsafeBitCast(s, to: SetFn.self)
                }
                if getFn != nil, setFn != nil { break }
            }
        }
        if getFn == nil || setFn == nil {
            Log.shared.warn("亮度控制接口不可用（合盖黑屏节能将失效）")
        }
    }

    // MARK: - 外接屏检测

    func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// 是否有外接显示器：存在即程序停用（只服务内置屏场景）
    func hasExternalDisplay() -> Bool {
        activeDisplays().contains { CGDisplayIsBuiltin($0) == 0 }
    }

    // MARK: - 调暗 / 恢复（仅内置屏）

    /// 把内置显示器亮度调到 0，并记住原亮度（合盖黑屏；显示器不休眠）
    func dimBuiltin() {
        lock.lock()
        defer { lock.unlock() }
        guard let getFn, let setFn else { return }
        saved.removeAll()
        for id in activeDisplays() where CGDisplayIsBuiltin(id) != 0 {
            var b: Float = 0.5
            if getFn(id, &b) == 0 {
                saved[id] = b
                let rc = setFn(id, 0)
                Log.shared.info("内置屏 \(id)：亮度 \(Int(b * 100))% → 0（rc=\(rc)）")
            } else {
                Log.shared.warn("内置屏 \(id)：亮度读取失败，跳过黑屏")
            }
        }
    }

    /// 恢复被调暗的内置显示器（开盖即亮）
    func restore() {
        lock.lock()
        defer { lock.unlock() }
        guard let setFn else { return }
        for (id, b) in saved {
            let rc = setFn(id, b)
            Log.shared.info("内置屏 \(id)：恢复亮度 \(Int(b * 100))%（rc=\(rc)）")
        }
        saved.removeAll()
    }
}
