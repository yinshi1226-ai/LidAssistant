import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let dryRun: Bool
    private var menuBar: MenuBarController?
    private var monitor: TaskMonitor?

    init(dryRun: Bool) {
        self.dryRun = dryRun
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 阻止 App Nap，避免定时器被节流（允许系统空闲休眠）
        _ = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled],
            reason: "盒盖助手任务监控"
        )
        let monitor = TaskMonitor(dryRun: dryRun)
        self.monitor = monitor
        let menuBar = MenuBarController(monitor: monitor)
        self.menuBar = menuBar
        monitor.onUpdate = { [weak menuBar] snap in
            menuBar?.update(snap)
        }
        monitor.start()
        Log.shared.info("盒盖助手已启动 dryRun=\(dryRun) mode=\(ConfigStore.shared.config.mode)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出时恢复安全状态：允许正常休眠 + 恢复内置屏亮度（避免忘记关造成电池耗尽）
        if !dryRun {
            _ = SleepController.shared.setDisableSleep(false)
            BrightnessController.shared.restore()
        }
        Log.shared.info("盒盖助手退出，disablesleep 已恢复 0，屏幕亮度已恢复")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
