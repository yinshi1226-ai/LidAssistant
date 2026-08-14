#!/bin/bash
# 盒盖助手 卸载
set -euo pipefail
cd "$(dirname "$0")"

echo "卸载盒盖助手…"

# 退出 App
osascript -e 'tell application "盒盖助手" to quit' 2>/dev/null || true
pkill -f "盒盖助手.app/Contents/MacOS/盒盖助手" 2>/dev/null || true

# 用户侧：登录自启
launchctl bootout "gui/$(id -u)/com.lidassist.app" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.lidassist.app.plist"

# 管理员侧：看门狗 + sudoers
osascript -e "do shell script \"
  launchctl bootout system/com.lidassist.watchdog 2>/dev/null || true;
  rm -f /Library/LaunchDaemons/com.lidassist.watchdog.plist /usr/local/bin/lidassist-watchdog.sh /etc/sudoers.d/lidassist;
  /usr/bin/pmset -a disablesleep 0 2>/dev/null || true
\" with administrator privileges" >/dev/null

rm -rf "/Applications/盒盖助手.app"
echo "✓ 卸载完成（已恢复合盖正常休眠）"
echo "（配置与日志保留在 ~/Library/Application Support/LidAssistant/，可手动删除）"
