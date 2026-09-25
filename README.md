# AgentBell

macOS 上的本地 Agent 提醒工具，为 Codex CLI 和 Claude hooks 提供可区分的提示音与系统通知。

阶段 3 提供 Swift 原生灵动岛：同时显示 Codex / Claude 的运行会话、项目、已运行时长和最近 10 条完成摘要，点击条目打开对应会话。无刘海屏使用顶部居中的浮动胶囊，有刘海屏贴合刘海，跟随鼠标所在屏幕。通知与声音仍由事件脚本发送，退出 App 后提醒仍可用。

不使用网络服务，不安装第三方依赖。运行日志和用户配置仅保存在 `~/.agentbell/`，不提交到仓库。

范围以 [`needs/decisions.md`](needs/decisions.md) 的 D001 / D002 / D004 / D005 / D006 为准。

## 使用

在仓库目录执行（macOS，Command Line Tools、Python 3.11+、Codex CLI；本机验证版本为 0.157.0）：

```sh
./install.sh
```

安装脚本用 `swiftc` 编译、组装 `.app` 并 ad-hoc 签名，写入登录自启 LaunchAgent 并启动；不用 Xcode 工程、SPM 或第三方库。悬停或点击顶部胶囊展开列表，移开自动收起；点任务条目打开会话。菜单栏铃铛仅保留“显示灵动岛”和退出。展开不会抢输入焦点；点击会话会按用户操作激活目标 App。

安装后**新开 Codex / Claude Code 会话**以加载新增 hooks。任务完成分别播放 Submarine / Glass，需要处理时播放 Ping。安装脚本打印配置修改位置和备份目录。

```sh
# 查看事件（原始负载可能包含会话文本，请勿公开上传）
tail -f ~/.agentbell/logs/events.jsonl

# 菜单选择退出后，手动重新打开
open ~/.agentbell/AgentBell.app

# 卸掉 App、登录自启和 hooks，还原安装前配置，保留日志和备份
./uninstall.sh

# 恢复安装
./install.sh
```

声音映射及开关在 `~/.agentbell/config.json`。运行脚本、App、日志和备份位于 `~/.agentbell/`，登录项为 `~/Library/LaunchAgents/local.agentbell.menubar.plist`。若安装后手动修改了 agent 配置或 Codex hooks，卸载会拒绝覆盖，需先核对差异。重复安装可更新菜单栏 App 并保留最初的还原点；更新事件脚本需卸载后重新安装。

## Codex hooks 与状态

依据 [OpenAI Hooks 文档](https://learn.chatgpt.com/docs/hooks) 和本机 0.157.0 的实际接口验证，配置放在 `~/.codex/hooks.json`。安装器保留其他 hooks，只添加：

- `SessionStart`：记录会话生命周期，不把打开空会话误报为正在运行。
- `UserPromptSubmit`：每轮任务开始，使用 `session_id` / `turn_id` 与原 `notify` 完成事件配对。
- `SessionEnd` / `Interrupt`：清除关闭或中断的运行状态，不伪造完成记录。

二进制中存在 `TurnStarted` 字符串不等于可配置同名 hook；本机 `hooks/list` 未识别该事件，因此采用已验证的 `UserPromptSubmit`。没有添加 `PreToolUse` / `PostToolUse`。

安装器通过 Codex `hooks/list` 获取上述四条定义的真实 hash，再由 `config/batchWrite` 登记 `hooks.state` 信任并回查。不会信任其他来源的 hooks，也不使用 bypass 开关。写入前有备份，写入后检查配置语义和 `notify` 原行不变；可在 CLI `/hooks` 复核。

App 每秒增量读取事件日志；Claude 的存活跟随 `Claude.app`，不检查终端或 TTY。带有仍在运行的 `background_tasks` 的 Claude `Stop` 不会提前清除菜单状态。摘要只来自完成事件，不解析会话消息。为定位会话，另只使用下面所述的标识元数据。

## 点击会话

- Claude：已实测 `claude://code/continue?session=local_…`。先在本地 `~/Library/Application Support/Claude/claude-code-sessions/` 的两层账户目录中读取元数据，按 `cliSessionId` 精确映射 `sessionId`；不使用项目名或时间猜配。映射缺失、重复或已归档时只打开 Claude，条目会明确说明无法定位。
- Codex 桌面：已由用户确认点击条目后实际切到目标任务，格式为 `codex://threads/<id>`。
- Codex CLI：只打开正在运行的 iTerm2 或 Terminal，不定位窗口、tab 或 split。客户端来源优先采用事件负载；开始事件缺失客户端字段时，只解析其 `transcript_path` 指向的本地 `session_meta` 首行（最多 64 KiB），检查会话 ID 与来源，不解析后续消息。来源不明只打开 Codex，并标注“来源未确认”。
- 悬停条目显示实际操作，完整摘要可看 tooltip。无法启动 App 或深链投递失败时，非激活面板显示 6 秒提示；操作系统接收链接不被当成导航成功回执。

## 验证边界

- 2026-09-25 阶段 3：真实 Codex CLI、新建 Claude 桌面会话均记录开始和完成；Claude 后台运行期间未提前清除状态。用户确认 Submarine、Glass 两种提示音。
- Claude 条目点击后，Computer Use 读到目标会话标题、路由和验收标记；Codex 条目点击后，用户确认从其他任务切回指定会话。CLI 条目明确标注“不定位会话”。
- 用户已确认 LG 无刘海屏、内建刘海屏显示、跨屏跟随与输入焦点正常；AppKit 胶囊最小态、展开态和真实记录已检查。界面独立复核发现的错误提示过早消失已修复。
- 实际卸载后，两份 agent 配置逐字节等于原始备份，新增 hooks、App、进程和 LaunchAgent 均移除；重装后两份配置及 hooks 文件逐字节等于本轮安装前，App 已重新运行。
- `bin/` 完全未改，运行脚本与仓库逐字节一致；`notify` 串联安装前后相同。Computer Use 实际操作 Claude、浏览器和 AgentBell 均可用。阶段 1、2 曾记录的原客户端 IPC 错误未在本轮修复，不承诺底层错误已消失。
- 登录自启配置和 LaunchAgent 已检查；下次登录自动出现仍待人工确认。系统通知横幅、真实权限请求场景也未在本轮额外验收。
- 强制杀死 Codex 可能来不及产生关闭事件，保留最后运行状态；未用进程轮询猜测完成。Claude 元数据是桌面端内部格式，后续版本变化可能使映射降级为打开 App。

详细证据与当前安装状态见 [`needs/progress.md`](needs/progress.md)，界面实现记录见 [`DESIGN.md`](DESIGN.md)。
