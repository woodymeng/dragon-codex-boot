# macOS 移植本地交接

检查日期：2026-10-07 UTC。仓库：<https://github.com/woodymeng/dragon-codex-boot>。

**当前状态：云端可执行的核心检查完成，源码已本地提交；GitHub 推送和 macOS Actions 被无效凭据阻止。尚无编译完成的 `.app`，尚未达到“远程成果已提交且 macOS 编译通过”的里程碑。** 用户已经授权推送和运行 Actions，仍需要实际有效的环境凭据，口头授权不能修复 401。

## 2026-10-08 接回本地

本轮重新检查仍为云端 Linux，没有连接的本地 Codex 会话，GitHub 授权仍返回 401。尚未迁移执行环境，也未在 Mac 运行任何检查。无需重新授权推送，但需要本地任务实际连接到 Mac。

下载 `dist/DragonCodexBoot-LocalResume.zip` 到 Mac 并解压，双击 `Resume-On-Mac.command`；也可在终端运行 `bash /解压路径/DragonCodexBoot-Local/Resume-On-Mac.command`。若缺少 SDK，先执行 `xcode-select --install`；需支持 Swift 5.9+ 的当前工具链。

入口校验 Git bundle 并恢复原提交到 `~/Developer/dragon-codex-boot-macos-提交前12位`，打印准确路径。它执行核心测试、arm64 构建、实际 AVFoundation 播放验证、签名和打包，保存日志；首次配置会读取已安装 Codex 的实际 bundle ID，现有用户配置保留。若本机 gh 有仓库写权限且源码干净，会尝试已授权的分支推送；成功验证后打开构建的 `.app`。它不把打开窗口当作实机验收通过。

接着在 Mac 的 Codex 中以**本地执行环境**打开该仓库，把压缩包内 `LOCAL_SESSION_PROMPT.txt` 的内容交给本地任务。当前云端对话没有可直接切换 Mac 的工具；本地项目连接后才能继续读编译日志、修复 Apple SDK 错误并验证真实窗口。两项系统权限仍需在 Mac 设置中授予。

恢复入口也已纳入源码：`macos/scripts/resume-local.command`。此次调整让自动检查支持仅安装 Command Line Tools 的 Mac，不要求完整 Xcode；本轮只验证了脚本语法、Linux 拒绝路径和离线恢复，不声称已在 Mac 运行。

## 分支、提交和交付物

- 分支：`feat/macos-port`，从 `main` 创建。
- 基线：`d3b7bb84b75134f8250491c86d72996a70d58165`。
- 移植实现提交：`d8e5e6519ef7f0460def06dd59eba5fe20c1ed77`。
- 交付提交包含本文件和授权失败日志；准确完整哈希见随包 `dist/DELIVERY.json`，在 Git 检出中执行 `git rev-parse HEAD` 亦可获得。
- 工作目录：`/workspace/dragon-codex-boot`。
- 完整源码和原视频：`dist/dragon-codex-boot-macos-source.zip`。
- 基线到交付提交的邮件格式补丁：`dist/feat-macos-port.patch`。
- 可恢复完整分支历史和原提交标识：`dist/feat-macos-port.bundle`。
- 校验：`dist/SHA256SUMS` 和 `dist/DELIVERY.json`。

`dist/` 不提交到仓库。源码压缩包内没有 SDK、工具链、凭据或已编译的 `.app`。恢复后的 Git 仓库可以用 `bash macos/scripts/export-handoff.sh origin/main` 再次生成源码交付；bundle 恢复时没有 `origin/main`，请把脚本参数替换成上面的基线哈希。

最稳妥的离线恢复方法（保留原提交）：

```bash
git clone --branch feat/macos-port /path/to/feat-macos-port.bundle dragon-codex-boot
cd dragon-codex-boot
git remote set-url origin https://github.com/woodymeng/dragon-codex-boot.git
git rev-parse HEAD
```

已有目标仓库时，也可从基线创建 `feat/macos-port`，执行 `git am /path/to/feat-macos-port.patch`。邮件补丁会保留作者和内容，但重新生成提交可能改变提交哈希；Git bundle 保留准确哈希。

## 已实现

独立 `macos/` 目录中使用 Swift + AppKit + AVFoundation + ScreenCaptureKit；公开 AX 属性实现窗口恢复、移动、尺寸调整和置前。独立 `.app` 为入口，保留 Windows 实现，不替换系统或官方启动入口。

播放随附视频并启动/接入已有 Codex；在 11.3 秒配置节点等待；权限允许且窗口稳定、收到有效画面后，按 12.7–13.65 秒关键帧显示真实窗口；视频结尾撤去动画，交还焦点。支持 Esc、总超时、等待超时、媒体错误退出，以及权限不足/捕获失败时的普通淡出。窗口捕获不录制系统音频，帧只在内存中处理，不保存聊天内容或截图。

构建脚本可生成 arm64 `.app`，包含启动视频、模板、MIT 许可证和媒体说明，附临时签名与 ZIP/SHA-256 校验。**这描述的是实现和构建流程；macOS 部分尚未实际编译或执行。**

## 实际验证结果

| 项目 | 本次结果 |
| --- | --- |
| 实际执行环境 | Debian 13、Linux x86_64；无 Xcode/macOS SDK；临时安装官方 Linux Swift 6.0.3 |
| GitHub 克隆 | 成功；网络策略 unrestricted/enforced，命令需要启用执行沙箱网络权限 |
| 初次网络错误 | `Failed to connect to proxy port 8080` / socket `Operation not permitted`；启用命令网络权限后修复，未绕过代理或修改环境策略 |
| 核心 Swift 编译、XCTest | **25 tests，0 failures**；配置、媒体时序校验、插值、坐标、等待、超时、Esc、流失效状态 |
| 媒体实际探测 | H.264/AAC、1920×1080、24 fps、14.101 秒 |
| 原 Windows 文件与媒体 | 与 origin/main 逐文件比较，字节一致 |
| 脚本/清单 | Bash 语法、JSON、Info.plist、Actions YAML 解析通过 |
| macOS 源码语法 | arm64 macOS 目标语法解析通过；不含 SDK 类型检查和链接 |
| macOS 构建实际尝试 | exit 2：`macOS SDK required` |
| GitHub REST | `Bad credentials`，HTTP 401，无法确认仓库写权限 |
| 真实推送 | 使用 gh 凭据助手，exit 128：`Invalid username or token` / `Authentication failed` |
| 触发 macOS Actions | `gh workflow run macos.yml --ref feat/macos-port` 返回 HTTP 401；无 run ID |
| macOS SDK 编译 / AVFoundation smoke / .app 打包 | **未运行，无通过结论，无二进制交付** |
| 真实 Codex、TCC、窗口移动/捕获、焦点、Esc、多屏 | **未运行，需要开机的 Mac** |
| Windows 测试 | 本次 Linux 没有 PowerShell/.NET Framework，未重跑；原代码/测试未修改 |

运行证据在 `macos/validation/`。Linux 日志中 `Compiling DragonCodexBoot` 只编译了条件编译后的 Linux 入口，不能作为 macOS 编译证据；语法解析也不能代替编译或运行。

## 补充连接/授权并完成云端里程碑

需要在 **Base Environment 的 GitHub 凭据绑定**中提供有效 `GH_TOKEN`（或 CLI 能使用的同等 GitHub 连接）。不要把明文 token 发到聊天中或写入仓库。当前环境状态显示没有绑定的 secrets/outbound identities；现有 GH_TOKEN 实际请求返回 401。

Fine-grained PAT：选择 `woodymeng/dragon-codex-boot` 仓库，授予 **Contents: Read and write、Workflows: Read and write、Actions: Read and write**，并满足组织批准要求（如适用）。如果使用 classic PAT，需要 `repo`（私有仓库；公共仓库可按需要使用 `public_repo`）及 `workflow` 范围。仅安装 GitHub 阅读连接或确认授权并不会自动给云端 Git/gh 配置有效凭据。

凭据实际生效后，在本工作目录运行：

```bash
gh auth status
gh api repos/woodymeng/dragon-codex-boot --jq .permissions
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u origin feat/macos-port
gh workflow run macos.yml --repo woodymeng/dragon-codex-boot --ref feat/macos-port
gh run list --repo woodymeng/dragon-codex-boot --workflow macos.yml --branch feat/macos-port --limit 5
# 将实际 run ID 填入下一行
gh run watch RUN_ID --repo woodymeng/dragon-codex-boot --exit-status
gh run view RUN_ID --repo woodymeng/dragon-codex-boot --log-failed
gh run download RUN_ID --repo woodymeng/dragon-codex-boot --dir dist/actions
```

推送本身也会触发该 workflow，可直接监看实际 push run，避免重复手动触发。失败时必须依据实际编译/测试日志修复、提交并重跑，不能把已配置 workflow 当作验证通过。下载 artifact `DragonCodexBoot-macos-arm64` 和 `macOS-verification-logs`。

runner 使用 `macos-15`，记录真实 CPU、Xcode 和 Swift。它运行核心 XCTest、编译 arm64、验证许可证/视频、临时签名和程序包。若 host 为 Intel，额外构建 x86_64 包执行 AVFoundation 真正播放到至少 0.1 秒的静音 smoke test；不把 x86_64 的运行结果当作 arm64 运行结果。CI 无法代替真实 Codex 与用户桌面权限验收。

## Mac 构建、运行和授权

Mac 需要 Apple Silicon、macOS 13+、Swift 5.9+ 的 Xcode Command Line Tools。没有工具时运行 `xcode-select --install`。

```bash
bash macos/scripts/test.sh
bash macos/scripts/build.sh arm64
bash macos/scripts/package.sh
ditto 'build/macos-arm64/Dragon Codex Boot.app' '/Applications/Dragon Codex Boot.app'
launcher='/Applications/Dragon Codex Boot.app/Contents/MacOS/DragonCodexBoot'
"$launcher" --validate-config
"$launcher" --smoke-test
"$launcher" --diagnose
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Codex.app/Contents/Info.plist
```

如果 Codex 的实际标识与默认 `com.openai.codex` 不同，先复制模板并调整 `bundleIdentifier` 和 `applicationPath`：

```bash
mkdir -p "$HOME/Library/Application Support/DragonCodexBoot"
cp '/Applications/Dragon Codex Boot.app/Contents/Resources/launcher.example.json' \
   "$HOME/Library/Application Support/DragonCodexBoot/launcher.json"
```

模板必须保留所有字段。相对 `video` 路径以 `.app/Contents/Resources` 为根，自定义视频可用绝对路径。视频时长必须覆盖过渡节点并小于总超时。

完整嵌入需辅助功能与屏幕录制权限：

```bash
"$launcher" --request-permissions
open '/Applications/Dragon Codex Boot.app'
```

在系统设置 → 隐私与安全性中，启用 **Dragon Codex Boot** 的辅助功能和屏幕录制/屏幕与系统音频录制，退出并重新打开 `.app`。CLI 请求有时归属终端，必要时在设置中用 `+` 添加 `.app`，以 Finder 入口实际运行结果为准。运行时不捕获系统音频。不得通过禁用 TCC 来绕过授权。

## 明天最短的实机验收

如果 Actions 已通过，直接下载 arm64 ZIP、解压并移到 `/Applications`；否则先运行上面的本机测试和构建命令，修复实际报错后再继续。临时签名未经公证，下载版可能需在系统设置中“仍要打开”；本机自行编译可避免下载隔离属性的影响。

1. **预检（约 1 分钟）**：核对 Codex bundle ID，执行 `--diagnose` 和 `--smoke-test`。确认 arm64、视频可播、两项权限已开启；保存诊断输出。
2. **已有窗口（约 20 秒）**：把 Codex 放在普通桌面，输入一段无敏感内容的测试文字；打开启动器。确认只有原 Codex 进程、动画中显示其真实内容/变化、关键帧边界扩大、结束后可直接输入。日志需出现 `first-real-window-frame` 和 `focus-requested-for-real-client`。
3. **冷启动（约 20 秒）**：退出 Codex，再打开启动器。确认启动 Codex，未就绪时停在 11.3 秒；就绪后继续播放和交接。
4. **Esc（约 5 秒）**：再次打开启动器立即按 Esc，确认动画关闭、Codex 接到焦点。也在等待节点按 Esc。辅助功能授权时检查客户端抢焦点后仍可跳过。
5. **降级与超时（约 1 分钟）**：暂时关闭启动器的屏幕录制权限并重新打开，确认正常视频后淡出、无无限等待。用模板副本和 `--config` 设置一个不存在的客户端标识/路径、`maxWaitSeconds: 3`、`maxTotalSeconds: 30`，确认等待节点后自动退出；不改正式配置。之后恢复权限。
6. **额外检查（可后续）**：Retina、负坐标副屏/上方屏幕、客户端最小尺寸、多窗口、最小化、全屏 Space 和重复启动入口。记录问题及 `~/Library/Logs/DragonCodexBoot/launcher.log`。

## 已知问题与尚需确认

- 未得到 macOS 编译日志，Apple SDK 类型或可用性错误仍可能存在；必须由 Actions 或实机编译确认。
- 默认 Codex 标识/路径需要本机核对；未利用真实 Codex 测试窗口发现规则。
- 就绪是稳定可见窗口和有效画面的启发式判断，启动页/登录页可能被认为已就绪，不能证明后台初始化完成。
- 捕获为完整窗口（可能含标题栏与阴影），不是 Windows DWM 客户区；矩形关键帧没有透视变换。
- AX 可能受客户端最小尺寸、最小化、全屏或不可调整窗口影响，日志会报告 `alignment-inexact`；结束后保留调整后的窗口布局。
- 无辅助功能权限且客户端抢走焦点时，需点回动画窗口才能按 Esc；有该权限时使用临时全局 Esc 监听，结束即移除。
- 全屏/跨 Space、多屏/Retina 和权限请求归属尚需实测。
- 仅 ad hoc 签名，没有 Developer ID、公证或稳定分发身份；更新/移动程序后可能需要重新授予权限。
- 没有将 macOS 代码审查、Linux 单测或 CI 配置描述成真实 Codex 窗口验收通过。

源码 MIT 许可证与媒体授权范围原样保留，详见 `LICENSE`、`THIRD_PARTY_NOTICES.md`、`media/MEDIA_NOTICE.md`。要继续到完整里程碑，先补充有效 GitHub 环境凭据运行 macOS CI，再做上述 Mac 验收。
