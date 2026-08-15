#!/bin/bash
# 盒盖助手 一键安装
# 需要输入一次管理员密码（用于安装 pmset 免密授权 + 崩溃看门狗守护进程）
set -euo pipefail
cd "$(dirname "$0")"

echo "════════════════════════════════════"
echo " 盒盖助手 安装"
echo "════════════════════════════════════"

echo "① 编译打包…"
./LidAssistant/build-app.sh
ditto "LidAssistant/build/盒盖助手.app" "/Applications/盒盖助手.app"
echo "   ✓ 已复制到 /Applications/盒盖助手.app"

USER_NAME="$(id -un)"
HEARTBEAT="$HOME/Library/Application Support/LidAssistant/heartbeat"
LIDASSIST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lidassist-install.XXXXXX")"
chmod 700 "$LIDASSIST_TMP_DIR"
trap 'rm -rf "$LIDASSIST_TMP_DIR"' EXIT

# ── 生成 sudoers 片段 ─────────────────────────────────────────────
cat > "$LIDASSIST_TMP_DIR/lidassist.sudoers" <<EOF
Cmnd_Alias LIDASSIST_PMSET = /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
$USER_NAME ALL=(root) NOPASSWD: LIDASSIST_PMSET
EOF

# ── 生成看门狗脚本 ───────────────────────────────────────────────
cat > "$LIDASSIST_TMP_DIR/lidassist-watchdog.sh" <<EOF
#!/bin/sh
# 盒盖助手看门狗：App 崩溃超过 2 分钟未更新心跳 → 恢复允许休眠，防止电池耗尽
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

cat > "$LIDASSIST_TMP_DIR/com.lidassist.watchdog.plist" <<EOF
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

# ── 管理员一次性授权 ─────────────────────────────────────────────
cat > "$LIDASSIST_TMP_DIR/root-install.sh" <<EOF
#!/bin/sh
set -e
visudo -c -f "$LIDASSIST_TMP_DIR/lidassist.sudoers" >/dev/null
cp "$LIDASSIST_TMP_DIR/lidassist.sudoers" /etc/sudoers.d/lidassist
chown root:wheel /etc/sudoers.d/lidassist
chmod 440 /etc/sudoers.d/lidassist
mkdir -p /usr/local/bin
cp "$LIDASSIST_TMP_DIR/lidassist-watchdog.sh" /usr/local/bin/lidassist-watchdog.sh
chmod 755 /usr/local/bin/lidassist-watchdog.sh
cp "$LIDASSIST_TMP_DIR/com.lidassist.watchdog.plist" /Library/LaunchDaemons/com.lidassist.watchdog.plist
chmod 644 /Library/LaunchDaemons/com.lidassist.watchdog.plist
launchctl bootout system/com.lidassist.watchdog 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.lidassist.watchdog.plist
exit 0
EOF

echo "② 请求管理员授权（安装 pmset 免密授权 + 看门狗守护进程）…"
echo "   请在弹出的对话框中输入你的开机密码。"
osascript -e "do shell script \"/bin/sh $LIDASSIST_TMP_DIR/root-install.sh\" with administrator privileges" >/dev/null
echo "   ✓ 免密授权与看门狗已安装"

# 验证 sudoers 生效（1 → 0 立即回滚，开盖状态下无副作用）
if sudo -n /usr/bin/pmset -a disablesleep 1 2>/dev/null; then
  sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null
  echo "   ✓ pmset 免密授权验证通过"
else
  echo "   ⚠️ pmset 免密授权验证失败，请检查后重试"
fi

# ── 登录自启 ─────────────────────────────────────────────────────
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
echo "③ 登录自启已配置"

echo "④ 启动盒盖助手…"
open -a "/Applications/盒盖助手.app"

echo ""
echo "════════════════════════════════════"
echo " 安装完成！"
echo " 菜单栏会出现「🤖 自动」图标，点开即可切换模式。"
echo " 设置：任务结束后的等待分钟数可自行填写。"
echo " 日志：~/Library/Application Support/LidAssistant/lidassistant.log"
echo " 卸载：运行 ./uninstall.sh"
echo "════════════════════════════════════"
