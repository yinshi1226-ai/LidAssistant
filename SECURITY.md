# 安全说明（Security）

## 报告漏洞

如果你发现了安全漏洞，请**不要公开讨论**，直接在 GitHub Issues 中新建一个 issue，并在标题前加 `[SECURITY]`，或在 issue 正文中注明「请私密处理」。作者会尽快回复。

## 权限与数据

本项目坚持最小权限、零遥测：

- **无任何网络上报/遥测**。程序只在本地运行，不会向任何服务器发送数据（唯一网络活动是可选地查询本机 `127.0.0.1` 上的 DeepSeek Harness 会话状态，且仅当该服务在本机运行时才有）。
- **不读取你的私密内容**。只读取以下本地状态文件用于判断「任务是否在运行」：
  - DeepSeek Harness：`POST http://127.0.0.1:3080/api/session.list` 的 `running` 字段（仅布尔状态）；
  - ChatGPT/Codex：`~/.codex/sessions/**` 任务日志的时间戳与尾部事件类型；
  - Claude：`~/.claude/projects/**` 任务日志的时间戳与尾部事件类型；
  - WorkBuddy：`~/.workbuddy/projects/**` 任务日志的时间戳。
  - 日志内容不会被上传或外发。
- **sudoers 范围严格限定**：安装时只授予 `pmset -a disablesleep 0` 和 `pmset -a disablesleep 1` 这两条命令的免密权限（`/etc/sudoers.d/lidassist`），不开放其他任何命令。
- **崩溃看门狗**：若 App 意外退出，看门狗（LaunchDaemon）会在 2 分钟内自动恢复 `disablesleep 0`，避免电池被耗尽。
- **外接屏自动停用**：检测到外接显示器时，程序自动停用、不干预系统行为。
- **合盖黑屏**：仅在合盖保持运行期间把内置屏亮度调到最低，开盖立即恢复；程序退出时也会恢复亮度。

## 签名说明

当前构建为 ad-hoc 签名（无开发者证书），首次安装需在「系统设置 → 隐私与安全性」中允许「仍要打开」。正式发布版会尝试公证（notarization）以消除该提示。
