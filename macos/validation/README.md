# 本次云端运行证据（2026-10-07 UTC）

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| Linux x86_64 / Swift 6.0.3 核心编译和 XCTest | 25 tests、0 failures | `linux-swift-tests.log` |
| 随附视频探测 | H.264、AAC、1920×1080、24 fps、14.101 秒 | `media-probe.json` |
| macOS 条件分支语法解析 | exit 0 | `macos-syntax-parse.log` |
| macOS arm64 构建尝试 | exit 2：缺少 macOS SDK | `macos-build-attempt.log` |
| Windows 源码/脚本/测试/配置与媒体逐文件对比 origin/main | 字节相同 | `windows-and-media-preservation.json` |
| Bash 语法、配置 JSON、Info.plist、workflow YAML 解析 | 通过 | 本次执行工具输出；非 macOS 编译证据 |
| GitHub REST / Actions | GH_TOKEN 无效，HTTP 401；无 Actions run ID | `github-access.log` |
| GitHub push | 无可用 Git 凭据，推送失败 | `github-push.log` |

Swift Linux 的日志中会出现 `Compiling DragonCodexBoot`。所有 AppKit/AVFoundation/ScreenCaptureKit 代码处于 `#if os(macOS)` 内，Linux 只编译了启动器的不支持平台入口，**不表示 macOS 原生部分已编译**。

语法解析同样不加载 macOS SDK，不验证 Apple API 类型、不链接、不执行。没有用代码审查或语法解析替代运行验证。

核心 XCTest 的真实复现命令（本次临时安装的工具链不纳入源码交付）：

```bash
PATH=/workspace/toolchains/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH \
CLANG_MODULE_CACHE_PATH=/workspace/swift-cache/clang \
SWIFT_MODULECACHE_PATH=/workspace/swift-cache/swift \
SWIFT_TEST_SCRATCH=/workspace/swift-build/core \
bash macos/scripts/test.sh \
  --cache-path /workspace/swift-cache/cache \
  --config-path /workspace/swift-cache/config \
  --security-path /workspace/swift-cache/security
```

首次运行因默认缓存目录 `/home/agent/.cache` 只读而失败。将缓存路径设置到可写工作区后实际编译并执行通过；没有修改系统或 HOME 设置。

macOS SDK 编译、AVFoundation 播放 smoke test、代码签名、`.app` 打包尚未运行。真实 Codex 画面、AX 权限及窗口尺寸、焦点交接、Esc 全局监听、多屏/Space 行为也尚未运行。连接恢复后先执行 Actions，再在用户 Mac 上验收。
