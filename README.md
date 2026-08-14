<p align="center">
  <b>English</b> &nbsp;·&nbsp;
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/menu-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/menu-light.png">
    <img alt="LidAssistant menu" src="assets/menu-light.png" width="640">
  </picture>
</p>

<p align="center">
  <b>LidAssistant (盒盖助手)</b> — a macOS menu-bar app that decides whether your Mac sleeps when the lid closes, and keeps it awake while your AI tasks are still running.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-brightgreen?style=flat-square"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/macOS-13%2B-8B5CF6?style=flat-square&logo=apple&logoColor=white">
  <img alt="Telemetry: none" src="https://img.shields.io/badge/telemetry-none-D946EF?style=flat-square">
  <img alt="Language: Swift" src="https://img.shields.io/badge/language-Swift-FA7343?style=flat-square&logo=swift&logoColor=white">
  <a href="https://github.com/yinshi1226-ai/LidAssistant/actions"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/yinshi1226-ai/LidAssistant/ci.yml?label=CI&style=flat-square"></a>
  <a href="https://github.com/yinshi1226-ai/LidAssistant/releases"><img alt="Release" src="https://img.shields.io/github/v/release/yinshi1226-ai/LidAssistant?label=release&style=flat-square"></a>
</p>

> [!NOTE]
> Closing the lid sleeps your Mac by default, and `caffeinate`-based tools (KeepingYouAwake and friends) can't change that, by design. The only reliable switch is `pmset disablesleep` (the kernel's `SleepDisabled` flag). LidAssistant wraps that single switch with **AI-task awareness** and several safety nets.

## Features

| | | |
|---|---|---|
| 🔀 | **Two modes** | `Auto` (task-aware) / `Manual` (lid-close sleep ⇄ stay awake), switched with a segmented control |
| 🤖 | **AI-task aware** | Lid closed + tasks running → stay awake; all tasks finished → sleep after a configurable delay (default 1 min) |
| 🎯 | **Accurate detection** | Reads each app's authoritative local state instead of guessing CPU/titles |
| 🌑 | **Black-screen energy saver** | While running with the lid closed, dims the built-in display to minimum (display stays awake), restored instantly on lid open |
| 🖥️ | **Auto-disable on external display** | Detects an external monitor and stops intervening entirely, resuming when unplugged |
| 🛡️ | **Safe by design** | sudoers limited to two commands, crash watchdog prevents battery drain, zero telemetry |
| 🚀 | **Launch at login** | Starts automatically and keeps watching your tasks |

## How task detection works

Instead of guessing, LidAssistant reads authoritative local state sources:

| Service | Detection |
|---|---|
| DeepSeek (DeepSeek Harness) | Local API `POST /api/session.list` → official `running` field |
| ChatGPT (desktop Codex engine) | `~/.codex/sessions/**` task logs: written only while running; `task_complete` marks the end |
| Claude (Claude Code / desktop) | `~/.claude/projects/**` task logs: `last-prompt` marks the end of a turn |
| WorkBuddy | `~/.workbuddy/projects/**` streamed task logs |

Plus a per-process network-traffic corroboration signal (only extends activity, never false-positives) and a debounce gate.

## Comparison

| | **LidAssistant** | Sleepless | Amphetamine | KeepingYouAwake | `caffeinate` |
|---|:---:|:---:|:---:|:---:|:---:|
| Awake with lid closed (no external display) | ✅ | ✅ | ⚠️ ¹ | ❌ ² | ❌ |
| AI-task-aware auto sleep | ✅ | ❌ | ❌ | ❌ | ❌ |
| Black-screen energy saver | ✅ | ❌ | ⚠️ | ❌ | ❌ |
| Auto-disable on external display | ✅ | ❌ | ❌ | ❌ | ❌ |
| Open source | ✅ MIT | ✅ MIT | ❌ | ✅ MIT | Apple |

<sub>¹ Amphetamine's closed-display mode has known reliability issues on Apple Silicon. ² KeepingYouAwake wraps `caffeinate` and can't prevent lid-close sleep by design.</sub>

## Install

```sh
brew install --cask yinshi1226-ai/tap/lidassistant
/Applications/盒盖助手.app/Contents/Resources/grant.sh   # one-time passwordless grant
```

> The grant step is one-time: it installs the sudoers rule for exactly two commands (`pmset -a disablesleep 0/1`), the crash watchdog, and login-at-startup. See [SECURITY.md](SECURITY.md).

| Alternative | How |
|---|---|
| **Download** | Grab the [latest release](https://github.com/yinshi1226-ai/LidAssistant/releases/latest), unzip to `/Applications`, then run `/Applications/盒盖助手.app/Contents/Resources/grant.sh` |
| **Build from source** | `git clone https://github.com/yinshi1226-ai/LidAssistant.git && cd LidAssistant && ./install.sh` (installs everything including the grant) |

> [!NOTE]
> Builds are ad-hoc signed; on first launch allow it in **System Settings → Privacy & Security → Open Anyway** (or run the installer script, which avoids the prompt).

## Usage

Click the **colored dot** in the menu bar:

- **Dot colors**: 🟢 green = idle/normal · 🟠 orange = manual stay-awake · 🔴 red = tasks running · ⚪ gray = disabled (external display). Hover for details.
- **Mode**: `Auto | Manual` segmented control.
  - Auto: shows the per-service task status list, a status line, and the last auto-sleep time. The full logic only applies while the lid is **closed**; with the lid open it follows the system entirely.
  - Manual: a sliding switch `Sleep on lid close ⇄ Stay awake` — the switch color matches the status dot.
- **Black-screen energy saver**: switch (blue when on) — dims the built-in display to minimum while running with the lid closed.
- **Sleep delay**: pick "sleep N minutes after no activity" directly from the submenu (30 s – 60 min, custom decimals allowed).

## Security & privacy

See [SECURITY.md](SECURITY.md). Highlights:

- **Zero telemetry** — nothing is ever sent anywhere.
- **Least privilege** — sudoers grants exactly `pmset -a disablesleep 0/1`.
- **No private content read** — only task-log timestamps and event types are inspected, never uploaded.
- **Crash protection** — the watchdog restores normal sleep within 2 minutes if the app dies.
- **External display** — the app disables itself whenever an external monitor is connected.

## FAQ

- **Why doesn't it sleep immediately after closing the lid?** Auto mode has a configurable grace period (default 1 min). Use Manual → Sleep for instant sleep.
- **Tasks finished but it didn't sleep after N minutes?** Check the status line — likely "external occupancy" (video/call) is holding the system awake.
- **After quitting, lid-close sleep no longer stays disabled?** Quitting restores normal sleep on purpose, so a forgotten quit can't drain the battery. Keep it running (login item is configured).

## Development

```bash
cd LidAssistant
swift build                          # compile
swift run LidAssistant --dry-run     # dry run: monitor only, never touch pmset/sleep
./build-app.sh                       # package the .app
```

## Uninstall

```bash
cd <project>
./uninstall.sh
```

## License

[MIT](LICENSE) © 2026 LidAssistant contributors
