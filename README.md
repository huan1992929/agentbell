# AgentBell

macOS 上的本地 Agent 提醒工具，为 Codex CLI 和 Claude hooks 提供可区分的提示音与系统通知。

阶段 5 提供 Swift 原生灵动岛：同时显示 Codex / Claude 的运行会话、项目、已运行时长和最近 5 条完成任务标题，点击条目打开对应会话。无刘海屏使用顶部居中的浮动胶囊，有刘海屏贴合刘海，跟随鼠标所在屏幕。通知与声音仍由事件脚本发送，退出 App 后提醒仍可用。

不使用网络服务，不安装第三方依赖。运行日志和用户配置仅保存在 `~/.agentbell/`，不提交到仓库。

范围以 [`needs/decisions.md`](needs/decisions.md) 的 D001 / D002 / D004 / D005 / D006 / D007 / D008 为准。

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

## Codex 运行状态（D007 修复）

桌面 App 不读取 CLI 的 `~/.codex/hooks.json`，因此 hooks 不能作为桌面任务开始信号。本机实测：`codex app-server daemon version` 无法连接默认控制 socket；桌面持有自己的 stdio app-server，另起一个 app-server 的 `thread/loaded/list` 返回空。没有为接入重启桌面、打开网络端口或修改 Codex 配置。

当前采用已实测的本地替代：

- 后台组件每 2 秒通过 macOS 自带 `lsof` 找到 **Codex 正在持有写入句柄**的本地会话文件；文件打开本身不等于任务运行中。
- 只解释 `session_meta` 与 `event_msg` 的 `task_started` / `task_complete` / `turn_aborted` 标识、来源和时间，按会话及 `turn_id` 配对。不按文本生成、文件增长或静默时长推断状态，不使用助手回复或工具内容判断状态。
- 首次从尾部寻找最新生命周期记录，以后增量读取。支持启动时接回正在运行的任务，已完成但仍被桌面 App 保持打开的会话不会重新出现。
- 完成、取消、新一轮开始均更新状态；进程退出或关闭会话写入句柄后，下次扫描清除旧条目，不依赖 `SessionEnd`。另以系统进程启动时间排除上一进程遗留的开始记录，避免重新打开旧文件时复活残留。扫描失败会明确显示“状态暂不可确认”，最多保留旧快照 10 秒，之后清除失去依据的条目，不伪造完成通知。

原 Codex hooks（SessionStart / UserPromptSubmit / SessionEnd / Interrupt）与 `notify` 原样保留。完成事件、系统通知与声音仍只来自原事件脚本；App 的本地观察不会重复发送通知。Claude 的 hooks 与存活判断不变。没有添加 PreToolUse / PostToolUse。

[官方 app-server 文档](https://learn.chatgpt.com/docs/app-server) 描述了直接连接的状态通知；本机没有可观察桌面现有任务的共享服务，**当前实现不是 app-server RPC 订阅**。未来桌面暴露共享连接后可替换观察组件，界面和通知链无需改变。

可选的单文件缺陷回归检查（无测试框架）：

```sh
swiftc -framework AppKit app/TaskPresentation.swift app/CodexActivity.swift app/EventStore.swift app/SessionNavigation.swift checks/main.swift -o /tmp/agentbell-codex-check
/tmp/agentbell-codex-check
```

## 额度与任务信息（D008）

展开态底部显示 Codex 最近一次 `rate_limits`：已用百分比、按实际 `window_minutes` 换算的窗口名、相对重置时间。primary / secondary 非空时都显示；没有记录显示不可用，重置时间已过但尚无新记录显示“待刷新”，不自行把用量归零。活动文件随状态每 2 秒读取，已关闭文件后台每 30 秒补查，启动也能恢复最近记录。额度随 Codex 写入更新，不是实时计费查询。

**Claude 不显示用量**：没有可用的本地账号级配额窗口，未累加消息 token 或做任何估算。

任务标题仅取用户提示词的首个非空行，最长 100 字。Codex 完成取 notify `input-messages` 中最近一条实际用户输入，运行中取本轮 rollout 的用户输入记录；Claude 取 `UserPromptSubmit.prompt`，后台任务通知沿用原始标题。去掉粘贴内容包装，纯文件路径显示文件名；缺少提示词如实显示“未记录任务提示词”，不回退到助手回复，也不解析会话正文。

无刘海屏收起显示运行数量与最近启动的任务标题，长标题省略；刘海两侧空间有限，显示来源字标（CX / CL / 双）与数量。运行条目显示已运行时长，完成条目显示相对时间。最近完成最多 5 条；行高 52pt，展开面板根据内容收缩，普通屏最多 480pt 高（原 580pt）。并发多时仍可滚动。

## 点击会话

- Claude：已实测 `claude://code/continue?session=local_…`。先在本地 `~/Library/Application Support/Claude/claude-code-sessions/` 的两层账户目录中读取元数据，按 `cliSessionId` 精确映射 `sessionId`；不使用项目名或时间猜配。映射缺失、重复或已归档时只打开 Claude，条目会明确说明无法定位。
- Codex 桌面：已由用户确认点击条目后实际切到目标任务，格式为 `codex://threads/<id>`。
- Codex CLI：只打开正在运行的 iTerm2 或 Terminal，不定位窗口、tab 或 split。客户端来源优先采用事件负载；开始事件缺失客户端字段时，只解析其 `transcript_path` 指向的本地 `session_meta` 首行（最多 64 KiB），检查会话 ID 与来源，不解析后续消息。来源不明只打开 Codex，并标注“来源未确认”。
- 悬停保留任务标题，实际打开目标见 tooltip 与辅助功能标签。无法启动 App 或深链投递失败时，非激活面板显示 6 秒提示；操作系统接收链接不被当成导航成功回执。

## 验证边界

- D008：真实额度快照与 UI 一致（验收时 7天已用16%，secondary=null）；真实 Codex CLI 与新 Claude 桌面任务的提示词标题、并发运行 / 完成清除、相对时间及最近 5 条已检查；Claude 点击精确定位通过。本轮声音与 Codex 精确跳转已请求用户核对，尚待回复，不借用前轮确认。详细过程见 progress。

- D007：已真实同时运行桌面任务与 CLI 任务，界面同时显示两条；桌面先完成后单独消失，CLI 继续运行，随后 CLI 也消失。原有用户任务保持显示。另实测强制结束一个 CLI，缺少 SessionEnd 和完成事件时条目仍自动清除。修复前的阶段 3 验收不足以证明桌面开始信号，以下历史结果不能替代这次并发验收。

- 2026-09-25 阶段 3：真实 Codex CLI、新建 Claude 桌面会话均记录开始和完成；Claude 后台运行期间未提前清除状态。用户确认 Submarine、Glass 两种提示音。
- Claude 条目点击后，Computer Use 读到目标会话标题、路由和验收标记；Codex 条目点击后，用户确认从其他任务切回指定会话。CLI 条目明确标注“不定位会话”。
- 用户已确认 LG 无刘海屏、内建刘海屏显示、跨屏跟随与输入焦点正常；AppKit 胶囊最小态、展开态和真实记录已检查。界面独立复核发现的错误提示过早消失已修复。
- 实际卸载后，两份 agent 配置逐字节等于原始备份，新增 hooks、App、进程和 LaunchAgent 均移除；重装后两份配置及 hooks 文件逐字节等于本轮安装前，App 已重新运行。
- `bin/` 完全未改，运行脚本与仓库逐字节一致；`notify` 串联安装前后相同。Computer Use 实际操作 Claude、浏览器和 AgentBell 均可用。阶段 1、2 曾记录的原客户端 IPC 错误未在本轮修复，不承诺底层错误已消失。
- 登录自启配置和 LaunchAgent 已检查；下次登录自动出现仍待人工确认。系统通知横幅、真实权限请求场景也未在本轮额外验收。
- Codex 本地生命周期记录与 Claude 元数据均是内部格式；上游变化可能影响状态或导航，出现读取问题会明确提示。Codex 子代理和未知来源不当作额外用户任务计数。

详细证据与当前安装状态见 [`needs/progress.md`](needs/progress.md)，界面实现记录见 [`DESIGN.md`](DESIGN.md)。
