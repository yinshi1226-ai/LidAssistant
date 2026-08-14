# 参与贡献

欢迎提交 Issue 与 Pull Request！

## 开发环境

- macOS 13+，Apple Silicon 或 Intel
- Xcode Command Line Tools（含 Swift）

## 本地开发

```bash
cd LidAssistant
swift build                      # 编译
swift run LidAssistant --dry-run # 试跑：只监控记录，不动 pmset、不真休眠
./build-app.sh                   # 打包 .app
```

## 提交规范

- 提交信息用中文或英文均可，请写清楚改动内容；
- 涉及隐私/权限的改动请同步更新 [SECURITY.md](SECURITY.md)；
- 新增功能请同时更新 [CHANGELOG.md](CHANGELOG.md)。

## 行为准则

请保持友善与建设性。涉及安全的漏洞请走 [SECURITY.md](SECURITY.md) 的私密流程，不要公开讨论。
