# Apple Silicon 原生启动器

macOS 13+、Apple Silicon、Xcode Command Line Tools（Swift 5.9+）。使用 Swift、AppKit、AVFoundation、ScreenCaptureKit；窗口恢复、移动、缩放和置前使用公开 Accessibility API。Windows 实现在原目录保留。

独立 `Dragon Codex Boot.app` 是启动入口，放到 `/Applications` 后可拖到 Dock。它不改写 Codex、系统快捷方式或原有 Dock 项。默认目标是 `com.openai.codex`、`/Applications/Codex.app`，本机需核对实际 bundle identifier。

## 构建和测试

在仓库根目录运行：

```bash
bash macos/scripts/test.sh
bash macos/scripts/build.sh arm64
bash macos/scripts/package.sh
open 'build/macos-arm64/Dragon Codex Boot.app'
```

程序包：`dist/DragonCodexBoot-0.1.0-macos-arm64-with-video.zip` 与 SHA-256 文件。包含视频、配置模板、MIT 许可证和原媒体说明。使用临时签名（ad hoc），没有 Developer ID 签名或公证；自行编译可以正常运行，下载的包可能需要在“隐私与安全性”中选择“仍要打开”。发布给大众前需要自己的 Apple Developer 签名与公证。改变签名、路径或重新构建后，权限可能需要重新授予。

Linux 可以运行 `LauncherCore` 的 XCTest，不能编译或验证 AppKit、AVFoundation、ScreenCaptureKit 分支。仓库 workflow `.github/workflows/macos.yml` 使用 macOS runner，执行核心测试、原生 arm64 编译、AVFoundation 真正播放视频的 smoke test、签名检查与打包。若 runner 是 Intel，视频 smoke test 使用额外构建的 x86_64 包，日志清楚记录架构；arm64 包仍由 macOS SDK 编译。CI 不声称完成真实 Codex、TCC 权限或可见桌面的验收。

## 配置

默认读取 `.app/Contents/Resources/launcher.example.json`；有用户配置时读取：

```text
~/Library/Application Support/DragonCodexBoot/launcher.json
```

建议先把模板复制到用户目录，保留模板所有字段，再修改需要的值：

```bash
mkdir -p "$HOME/Library/Application Support/DragonCodexBoot"
cp '/Applications/Dragon Codex Boot.app/Contents/Resources/launcher.example.json' \
   "$HOME/Library/Application Support/DragonCodexBoot/launcher.json"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Codex.app/Contents/Info.plist
```

把输出填入 `bundleIdentifier`，设置实际 `applicationPath`。启动器严格匹配应用标识，避免接入 CLI、辅助进程或同名应用。已经运行时复用现有进程，不再启动第二个实例。

`video` 相对路径以启动器 bundle 的 `Contents/Resources` 为根；也接受个人视频的绝对路径。`--config /absolute/file.json` 优先于用户配置，可用于隔离测试。缺少字段、无效时间、超出画面的关键帧会报错并以状态 1 退出；不会默默使用错误配置。

| 字段 | 含义 |
| --- | --- |
| `holdAt` | 客户端未就绪时暂停在视频秒数，默认 11.3 |
| `transitionStart` / `transitionEnd` | 12.7–13.65 秒开始与完成画面嵌入/淡出，视频会继续到结尾 |
| `screenFrames` | 按时间递增，归一化坐标以视频左上角为原点；必须覆盖过渡时段 |
| `maxWaitSeconds` | 等待节点的墙钟等待上限，默认 60 秒 |
| `maxTotalSeconds` | 所有状态的总墙钟上限，默认 90 秒 |
| `mediaLoadTimeout` | 视频准备上限，默认 12 秒 |
| `captureStartTimeout` | 首个捕获帧上限，默认 3 秒；随后切换淡出 |
| `stableWindowSeconds` | 同一可见窗口稳定时间，默认 0.6 秒 |
| `playerWidth` / `playerHeight` | AppKit 点，默认 1280×720；按当前屏幕可用区域缩小 |
| `matchClientToPlayer` | 用 AX 把真实窗口移到动画窗口的位置和尺寸，结束后保留该布局 |
| `volume` | 0–1，默认 1 |

默认时序只适用于随附 14.101 秒的视频。异比例视频使用等比缩放，关键帧相对实际视频区域定位。关键帧描述矩形，不支持透视四边形或遮挡分割。捕获显示的是完整客户端窗口（包括标题栏），和 Windows 的客户区缩略图可能略有差异。

## 权限与诊断

第一次运行不强制弹权限框。任一权限不足时正常播放，再淡出到 Codex；客户端窗口仍未出现时继续等待，达到上限后退出。完整嵌入需要“辅助功能”和“屏幕录制”（较新系统称“屏幕与系统音频录制”）两项权限。虽然系统权限名称含音频，启动器没有捕获客户端音频。

```bash
launcher='/Applications/Dragon Codex Boot.app/Contents/MacOS/DragonCodexBoot'
"$launcher" --diagnose
"$launcher" --request-permissions
```

在系统设置 → 隐私与安全性中启用 **Dragon Codex Boot** 的两项权限，退出启动器并重新打开。直接执行 bundle 内的 CLI 时，macOS 有时会把请求归属终端；以 Finder 打开的 `.app` 实际诊断与系统设置显示为准。可在设置中用 `+` 添加独立 `.app`。不要关闭系统权限保护。

```bash
"$launcher" --validate-config
"$launcher" --smoke-test
```

`--diagnose` 不启动客户端、不请求权限、不捕获窗口。`--smoke-test` 用 AVFoundation 验证随附视频轨道并真正准备播放到至少 0.1 秒，静音，不启动 Codex、不创建动画窗口、不请求权限。它不能代替真实窗口测试。

日志：`~/Library/Logs/DragonCodexBoot/launcher.log`（512 KB 后轮换）。只记录阶段、错误和权限状态，不记录聊天正文、窗口标题、画面或按键内容，不做网络遥测。捕获帧仅在内存中存在，退出时释放。

## 交接和限制

播放视频时启动/接入 Codex。先按进程标识查找可见正常窗口；权限齐全时通过 AX 主窗口和几何信息关联，不使用私有窗口编号 API。窗口稳定且已收到首个捕获帧才进入嵌入模式。流启动失败、超时、流停滞、窗口消失时切换普通淡出。视频结束或 Esc/超时/媒体错误后释放捕获、关闭动画窗口，再恢复并激活真实客户端。

“就绪”是可见稳定窗口和有效捕获帧的启发式判断，无法证明 Codex 的后台任务全部完成；启动页、登录页或客户端多个窗口仍需实机检查。窗口尺寸可能受 Codex 最小尺寸约束。AX 操作设置 150 ms 请求上限，避免客户端无响应时长期阻塞启动器。

Esc 在动画窗口有焦点时始终可用；有辅助功能权限时还安装临时全局 Esc 监听，以处理客户端抢走焦点的情况。无该权限且其他应用抢走焦点时，点击动画窗口再按 Esc，或等待超时。全局监听随动画结束移除。客户端不存在时无法把焦点交给它，启动器会有界退出并记录原因。

多屏坐标通过主显示器高度转换到 AX 坐标；负坐标、上方屏幕、Retina 实际捕获尺寸需要本地验收。全屏客户端和跨 Space 激活由 macOS 管理，可能出现切换；建议首轮在普通桌面窗口验证。

本次实际运行结果、未运行项和明天最短验收路径见仓库根目录 `LOCAL_HANDOFF.md`。本项目是独立社区工具，媒体许可说明见随包 `MEDIA_NOTICE.md`，源码 MIT 许可不追加媒体授权。
