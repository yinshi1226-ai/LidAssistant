#!/bin/bash
# grant.sh — 为「盒盖助手」配置系统权限（适用于 brew cask / 手动下载安装后运行一次）
# 作用：安装 pmset 免密授权（严格限定两条命令）+ 崩溃看门狗 + 登录自启
set -euo pipefail

USER_NAME="$(id -un)"
HEARTBEAT="$HOME/Library/Application Support/LidAssistant/heartbeat"
TMPDIR_LA="/tmp/lidassist-grant.$$"
mkdir -p "$TMPDIR_LA"

# sudoers：仅允许 pmset -a disablesleep 0/1
cat > "$TMPDIR_LA/lidassist.sudoers" <<EOF
Cmnd_Alias LIDASSIST_PMSET = /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
$USER_NAME ALL=(root) NOPASSWD: LIDASSIST_PMSET
EOF

# 看门狗：App 崩溃超过 2 分钟 → 恢复允许休眠，防电池耗尽
cat > "$TMPDIR_LA/lidassist-watchdog.sh" <<EOF
#!/bin/sh
HB="$HEARTBEAT"
while true; do
  STALE=1
  if [ -f "\$HB" ]; then
    MT=\$(stat -f %m "\$HB" 2>/dev/null || echo 0)
    NOW=\$(date +%s)
    if [ \$((NOW - MT)) -lt 120 ]; then STALE=0; fi
  fi
  if [ \$STALE -eq 1 ]; then
    /usr/bin/pmset -a disablesleep 0 2>/dev/null
  fi
  sleep 30
done
EOF

cat > "$TMPDIR_LA/com.lidassist.watchdog.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.lidassist.watchdog</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>/usr/local/bin/lidassist-watchdog.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF

cat > "$TMPDIR_LA/root.sh" <<EOF
#!/bin/sh
set -e
visudo -c -f "$TMPDIR_LA/lidassist.sudoers" >/dev/null
cp "$TMPDIR_LA/lidassist.sudoers" /etc/sudoers.d/lidassist
chown root:wheel /etc/sudoers.d/lidassist
chmod 440 /etc/sudoers.d/lidassist
mkdir -p /usr/local/bin
cp "$TMPDIR_LA/lidassist-watchdog.sh" /usr/local/bin/lidassist-watchdog.sh
chmod 755 /usr/local/bin/lidassist-watchdog.sh
cp "$TMPDIR_LA/com.lidassist.watchdog.plist" /Library/LaunchDaemons/com.lidassist.watchdog.plist
chmod 644 /Library/LaunchDaemons/com.lidassist.watchdog.plist
launchctl bootout system/com.lidassist.watchdog 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.lidassist.watchdog.plist
exit 0
EOF

echo "请求管理员授权（安装 pmset 免密授权 + 看门狗）…"
echo "请在弹出的对话框中输入你的开机密码。"
osascript -e "do shell script \"/bin/sh $TMPDIR_LA/root.sh\" with administrator privileges" >/dev/null
echo "✓ 免密授权与看门狗已安装"

# 登录自启
AGENT="$HOME/Library/LaunchAgents/com.lidassist.app.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.lidassist.app</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>/Applications/盒盖助手.app</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/com.lidassist.app" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || true
rm -rf "$TMPDIR_LA"

echo "✓ 登录自启已配置"
echo "完成！菜单栏已可正常使用盒盖助手。"
