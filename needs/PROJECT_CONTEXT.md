# AgentBell 项目上下文

采用 needs 工作流规范 V5.1。

## 目标

Codex CLI 和 Claude 桌面端**任务完成或需要人处理时**，立刻发出系统通知 + 可区分的提示音；菜单栏常驻显示各 agent 当前状态。全本地运行，不联网，无账号。

## 运行环境（已核实，2026-09-25）

- MacBook Pro，Apple M1 Pro，16GB，macOS 27.2（Darwin 27.2.0）
- Swift 6.4，`/usr/bin/swiftc`，仅装了 Command Line Tools（`/Library/Developer/CommandLineTools`），**没有完整 Xcode**
- Python 3.13.2，**未装** rumps / pyobjc，所以菜单栏不走 Python 路线
- **未装** terminal-notifier；`osascript` 可用
- Codex CLI 0.77.0，装在 `/usr/local/bin/codex`（npm 全局，root 所有，升级需 sudo）
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

通知由常驻 App 统一发出：通知权限只需授权一次，图标和来源归属清晰。

## 历史包袱

用户此前装过 **Vibe Island** 并已删除 App，但残留仍在，**已授权清理**：

- `~/.claude/settings.json` 里 11 个 hooks 全部指向 `~/.vibe-island/bin/vibe-island-bridge`（含 PreToolUse / PostToolUse）
- `statusLine` 也被它接管
- `~/.vibe-island/` 目录仍在

清理前必须备份 `~/.claude/settings.json`。

## 网络限制

huggingface.co、github.com 在这台机器上连不上（DNS 污染 + 端口封锁），没有配置任何代理。不要依赖需要从 GitHub 拉取的安装方式。

## 常用命令

```bash
# 阶段 0：装探针（会先备份配置）
probe/install-probe.sh

# 阶段 0：看探针抓到什么
tail -f probe/probe.log

# 还原所有配置改动
probe/uninstall-probe.sh
```
