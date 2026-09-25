# AgentBell 项目上下文

采用 needs 工作流规范 V5.1。

## 目标

**2026-09-25 阶段 2 校正**：以 `decisions.md` 的 D001/D002/D004/D005 为准。通知与声音留在事件脚本，App 仅显示状态。Codex CLI 实际为 0.157.0，用户级 `hooks.json` 已验证；`UserPromptSubmit` 标记每轮开始，`SessionStart` 仅标记会话生命周期，未识别同名 `TurnStarted` hook。详情见 `progress.md` 最新记录。下面旧环境/架构内容仅作历史背景，不覆盖这些决定。

Codex CLI 和 Claude 桌面端**任务完成或需要人处理时**，立刻发出系统通知 + 可区分的提示音；菜单栏常驻显示各 agent 当前状态。全本地运行，不联网，无账号。

## 运行环境（已核实，2026-09-25）

- MacBook Pro，Apple M1 Pro，16GB，macOS 27.2（Darwin 27.2.0）
- Swift 6.4，`/usr/bin/swiftc`，仅装了 Command Line Tools（`/Library/Developer/CommandLineTools`），**没有完整 Xcode**
- Python 3.13.2，**未装** rumps / pyobjc，所以菜单栏不走 Python 路线
- **未装** terminal-notifier；`osascript` 可用
- Codex CLI 0.157.0，当前使用 `~/.npm-global/bin/codex`；`/usr/local/bin/codex` 为保留的旧版
- Claude 主要用**桌面端**（Claude.app 的 Code 标签），`claude` CLI **没有装**，PATH 里找不到

## 两个接入点

| 来源 | 配置位置 | 关键约束 |
|---|---|---|
| Codex CLI | `~/.codex/config.toml` 的 `notify` | **已被 Codex Computer Use 占用**，值为 `["<SkyComputerUseClient 路径>", "turn-ended"]`。必须串联透传，不能覆盖 |
| Claude 桌面端 | `~/.claude/settings.json` 的 `hooks` | 只挂 `Stop` / `Notification` / `PermissionRequest`。**不挂 PreToolUse / PostToolUse**，那会在每次工具调用时起进程 |

Codex 的 notify 调用形式：配置数组是「程序 + 固定参数」，codex 在末尾追加 JSON 负载。即配置为 `[prog, "turn-ended"]` 时，实际执行 `prog turn-ended <json>`。串联脚本必须原样转发 `"$@"` 并保留退出码。

## 架构

事件采集与呈现分离。hooks 和 notify 都是短命进程，必须毫秒级返回，不能在里面弹通知（会拖慢 agent）。

```
Codex turn-ended  ──→ 事件脚本 ──┐
Claude 桌面端 hooks ──→ 事件脚本 ──┴──→ 事件文件 ──→ 菜单栏常驻进程（Swift）
                                                      发通知 · 放声音 · 显示状态
```

上图是早期设想，已被 D001 覆盖：事件脚本继续发通知与声音，常驻 App 仅消费事件日志显示状态。

## 历史包袱

用户此前装过 **Vibe Island** 并已删除 App，但残留仍在，**已授权清理**：

- `~/.claude/settings.json` 里 11 个 hooks 全部指向 `~/.vibe-island/bin/vibe-island-bridge`（含 PreToolUse / PostToolUse）
- `statusLine` 也被它接管
- `~/.vibe-island/` 目录仍在

清理前必须备份 `~/.claude/settings.json`。

## 同类开源项目：Open Island

`Octane0411/open-vibe-island`（GPL v3，SwiftUI + AppKit）做的是同一件事，而且更完整：13 个 agent、15+ 终端、刘海 UI、用量面板。**它是学习对象，不是可以直接抄代码的对象——GPL v3 具有传染性，复制其代码会强制本项目也变成 GPL v3。** 读思路可以，拷代码要先想清楚许可证。

从它文档里得到的、对本项目有用的事实：

- **Claude 桌面端**在"local agent mode"下以无 TTY 子进程运行，`ps` / `lsof` 看不到。可通过环境变量 `CLAUDE_CODE_ENTRYPOINT=claude-desktop` 识别（备用判据 `__CFBundleIdentifier=com.anthropic.claudefordesktop`）。
- **存活判定要跟着 Claude.app 走**（`NSWorkspace.shared.runningApplications`），不能跟着终端进程。否则会话会在出现约 6 秒后被误判为已结束（他们的 issue #510）。做阶段 2 的"运行中"状态时必须注意这一点。
- **桌面版 Codex** 可通过 `codex app-server` 的 JSON-RPC（stdio）拿到 `thread/started`、`turn/started`、`turn/completed`；点击会话可用 `codex://threads/<id>` 直接跳转。
- 他们的 hook 设计原则同样是 **fail open**——Open Island 没运行时，agent 完全不受影响。与本项目一致。

## 网络限制

早期曾遇到网络问题；阶段 1 已重新验证 GitHub 可访问并完成推送。安装和运行不下载第三方依赖。

## 常用命令

```bash
# 安装/升级菜单栏（先编译、备份配置）
./install.sh

# 查看真实事件
tail -f ~/.agentbell/logs/events.jsonl

# 还原所有配置改动
./uninstall.sh
```
