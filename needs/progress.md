## 2026-09-25 · D007 桌面 Codex 漏报与残留修复

### 实际连接调查与采用的替代

- 按 D007 修复，不重做规划，不复制 Open Island 源码。前几轮只证明了 CLI hooks、桌面完成事件与会话跳转，不能据此宣称桌面开始状态已覆盖；该验收缺口本轮纠正。
- 核对本机 `codex agents --help`、`app-server proxy --help`、生成的协议 schema 和 [官方 app-server 文档](https://learn.chatgpt.com/docs/app-server)。默认共享控制 socket `~/.codex/app-server-control/app-server-control.sock` 不存在，`daemon version` 连接失败。
- 桌面 App 持有独立 stdio app-server；只读启动一个独立 stdio 实例并调用 initialize / thread/loaded/list，返回空列表，无法观察桌面既有任务。没有为了接入去重启用户桌面服务、启动新共享 daemon、开放网络端口或变更 notify。
- **未声称接通 RPC 订阅**。已验证替代为本地 app-server 写出的会话生命周期：`session_meta` 提供 id/source/originator/cwd；`event_msg` 的 `task_started` / `task_complete` / `turn_aborted` 提供 turn_id 与时间。正文与工具内容不用于判定，不复制到新日志。

### 实现与残留清理

- 新增 `app/CodexActivity.swift`，后台每 2 秒通过系统自带 lsof 发现 Codex 进程持有的会话**写入**句柄，限定本机 `.codex/sessions/` 路径。打开文件只证明存活，不被当成运行信号；明确 task_started 才进入运行中。
- 首次读取元数据与尾部最新生命周期，之后增量读取；按会话和 turn_id 配对，晚到的旧 turn 完成不清除新 turn。已完成但文件仍打开的桌面会话保持空闲。
- 不再从 Codex UserPromptSubmit 历史日志重建运行状态；Claude 原逻辑保持不变。notify 仍提供原来的完成摘要与提醒，并可及时清除对应完成条目。
- task_complete / turn_aborted 清理；进程退出或会话写入句柄关闭，下次扫描清理。通过 macOS proc_pidinfo 读取实际进程启动时间，拒绝上一进程遗留的 task_started，避免重开旧文件复活残留。扫描失败显示状态暂不可确认，短暂保留旧快照，持续失败 10 秒后清除无依据的状态，不伪造完成事件。
- 子代理与未知来源不当作额外用户任务计数。此方案没有“文件停止增长就算完成”或固定任务超时，因此长时间工具运行不会被误清除。

### 必须实际跑出的并发验收：通过

- 新建桌面任务“AgentBell D007 桌面并发验收”，执行 sleep 55 后返回 `AGENTBELL_D007_DESKTOP_DONE`；同时真实运行 CLI，在 `cli-check` 目录执行 sleep 105 后返回 `AGENTBELL_D007_CLI_DONE`。
- Computer Use 读取并截图：两条任务同时处于运行中，分别标明桌面会话与终端入口。总数还包含本执行会话和用户另一个真实任务，不把这两条背景工作错误清掉。
- 桌面任务先结束后，其运行条目消失、完成摘要出现，CLI 条目继续运行；CLI 随后独立消失并出现完成摘要。桌面任务没有 UserPromptSubmit 开始 hook，这次运行状态确实由生命周期组件取得。
- 原残留的旧 turn 不再显示；同项目后来真实启动的新 turn 仍正常显示，以 turn_id 与开始时间区分，不按项目名粗暴删除。
- 另启动独立 `crash-check` CLI，确认已进入运行中后，仅对该验收进程组 SIGKILL。真实事件日志仅有 SessionStart / UserPromptSubmit，**没有 SessionEnd / agent-turn-complete**；界面仍自动清除了它，其他任务保持显示。

### 基础检查与生产状态

- 用 swiftc 构建安装 0.3.1，App 已运行。`checks/main.swift` 是无框架的定向检查：初次遇到空文件后重试、跨读取边界、半行追加、晚到旧 turn、取消、缺少 SessionEnd、重启读取已完成会话、两个会话分别清理；使用生效的 precondition，全部通过。
- `bin/` 未修改；运行脚本与仓库一致；Claude settings、Codex hooks、Codex config 最终逐字节等于本轮前快照，notify 串联未变。
- 创建桌面验收任务时 Codex 自身增加了一条该临时项目的 trust 配置。已先备份，确认它是唯一语义差异，再移除该验收副作用，恢复原文件及安装器校验值；未覆盖其他用户配置。清理备份：`~/.agentbell/backups/20260925-175252-verification-cleanup/`。
- 本轮首次 App 升级备份：`~/.agentbell/backups/20260925-174857-995319/`；其后两次补齐边界保护的升级备份也保存在同目录。卸载还原基线仍为 `20260925-173410-766815`，hooks 基线仍为 `20260925-173410-770884`。本轮未重复执行全量卸载回归。
- 私有证据在 `~/.agentbell/verification/d007/`：并发 / 桌面先完成 / 两者均完成的 AX 与截图、强制结束前后 AX、真实事件与 CLI 输出、三份安装前配置。公开仓库不包含真实会话 ID、正文或家目录。

### 已知边界

- 这是已验证的本地记录替代，**不是共享 app-server 事件订阅**；正常状态更新间隔约 2 秒。未来 Codex 文件格式或句柄持有行为变化可能需要适配。
- 扫描持续不可用时会清除失去依据的运行状态并提示不确定；不会把不确定状态谎报为任务完成。
- 无新增通知、声音、PreToolUse/PostToolUse、第三方依赖、SPM、Xcode 工程、CI 或测试框架。并发及残留清理已直接取得 UI 证据，无需再让用户补做本轮验收。

---

## 2026-09-25 · 阶段 3 已实现并完成真实验收

### 已完成与本轮边界

- 按 D006 将菜单列表改成原生 AppKit 灵动岛；无刘海屏顶部居中、宽度随内容变化，内建屏根据 safe area 与辅助区域贴合刘海。鼠标跨屏时收起并跟随；悬停/点击展开运行中与最近 10 条完成记录。
- 无边框 `.nonactivatingPanel`，禁止 key/main window，层级高于菜单栏，设置 Spaces / 全屏辅助 / transient / ignoresCycle，保留 LSUIElement。菜单栏只有“显示灵动岛”和退出。
- 条目直接打开会话，不创建详情窗口。Claude 的原 `sessionId=<hook UUID>` 候选未定位成功；从本机处理代码确认正确格式为 `claude://code/continue?session=local_…`，并从桌面元数据精确映射 hook UUID。Codex 桌面为 `codex://threads/<id>`；CLI 只打开终端，未知来源或无 Claude 映射时明确退化。
- Claude 只使用元数据中的会话 ID、归档标记；不解析聊天正文。Codex 为判断桌面/CLI，只解析事件指定且位于本地 sessions 目录中的 `session_meta` 首行，限 64 KiB。没有复制 Open Island 源码，没有第三方依赖、Xcode 工程、SPM、测试框架或 CI。
- `bin/` 及 hook 定义完全未改；通知/声音仍由脚本发出。App 构建升级到 0.3.0，安装器只调整 Swift 多文件编译和版本。

### 真实验收证据

- **Claude 跳转**：Safari 深链测试先证实 hook UUID 不能直接导航；改用元数据里的桌面 ID 后，前台出现“AgentBell stage 2 acceptance”及原验收回复。随后从其他 Claude 会话点击灵动岛的阶段 3 完成条目，Computer Use 读到“AgentBell stage 3 acceptance”、对应 `local_…` 路由和 `AGENTBELL_STAGE3_CLAUDE_OK`。
- **Codex 跳转**：先切到另一个已有任务，再实际点击灵动岛里本任务的 Codex 完成条目。Computer Use 禁止读取 Codex 自身界面，用户当场回复“已切回本会话”，据此确认精确跳转；未把协议投递成功当作界面成功。
- **两屏及焦点**：本机几何再次读取，LG 2560×1440，内建屏 safe top 32pt、刘海间隙 185pt。用户回复“两块屏显示、跟随和焦点都正常”。胶囊收起、外屏展开、内建屏展开实拍保存在私有验证目录。
- **真实任务回归**：新建 Claude 桌面验收会话，执行 sleep 25 后回复 `AGENTBELL_STAGE3_CLAUDE_OK`；真实 Codex CLI 执行 sleep 15 后回复 `AGENTBELL_STAGE3_CODEX_OK`。日志包含 Claude UserPromptSubmit / Stop（后台阶段保持运行）、Codex SessionStart / UserPromptSubmit / agent-turn-complete / SessionEnd。界面看到 Claude 后台运行中，最后两边均进入最近完成。
- **声音**：用户回复“两种都听到了”，确认 Claude Glass 与 Codex Submarine。Computer Use 对浏览器、Claude、AgentBell 的读取与点击均成功；原 notify 串联与运行脚本未变。
- **界面复核**：独立复核发现导航失败提示在收起后不可见且被秒级刷新覆盖，已改为非激活展开保留 6 秒；复核判定该问题 resolved。设置 darkAqua 使滚动条与深色面板一致。不扩大为全量测试。

### 实际卸载、逐字节还原和重装

- 执行 `./uninstall.sh`；`~/.claude/settings.json` 与 `~/.codex/config.toml` 分别逐字节等于 `~/.agentbell/backups/20260925-165844-580133/` 中的原始文件。
- Codex hooks 恢复原先不存在的状态；App、进程、LaunchAgent 文件和已加载服务均已移除，日志与备份保留。
- 随即执行 `./install.sh` 重装。上述两份配置和 `~/.codex/hooks.json` **逐字节等于本轮开始前**，包括原 `notify` 串联。脚本逐字节等于仓库版本。
- 当前 App 已运行、LaunchAgent 已加载，ad-hoc 签名严格校验通过；安装状态 `active=true`、`menu_installed=true`。
- **当前卸载还原基线**：`~/.agentbell/backups/20260925-173410-766815/`；**当前 hooks 还原快照**：`~/.agentbell/backups/20260925-173410-770884/`。

### 私有证据与剩余边界

证据仅存于 `~/.agentbell/verification/stage3/`：`real-events.json`、`codex-task.txt`、`uninstall-result.json`、`reinstall-result.json`、安装前配置快照与界面截图；不提交真实日志/会话 ID/正文到公开仓库。

- 本轮要求的人工确认已取得：双屏、焦点、两种声音、Codex 精确会话切换。Claude 精确切换由实际 UI 读取得证。
- 仍未重启/注销电脑，下次登录自启待确认；系统通知横幅和真实权限请求场景未额外验收。
- Claude 内部元数据格式未来可能变化，届时只能打开 App；Codex 强制结束仍可能留下运行状态。来源不明（如部分子任务事件）只打开 Codex，不声称定位成功。
- 阶段 1、2 原 Computer Use 客户端 IPC 错误保留为历史已知问题，本轮未更改或修复其实现；本轮 UI 操作正常。
- 本轮变更提交推送到 main；远程同步以最终 Git 回查为准。

---

# 进展记录

## 2026-09-25 · 阶段 2 菜单栏与双端运行状态

### 当前安装

- 已安装并运行 `~/.agentbell/AgentBell.app`，`LSUIElement=true`，无 Dock 图标；用 Command Line Tools 的 `swiftc` 编译、手工组 bundle、ad-hoc 签名。
- 登录项：`~/Library/LaunchAgents/local.agentbell.menubar.plist`，`RunAtLoad=true`。已验证 LaunchAgent 加载且进程运行；没有重启或注销用户电脑。
- 当前完整卸载还原点：`~/.agentbell/backups/20260925-165844-580133/`。
- 当前菜单栏/hooks 升级快照：`~/.agentbell/backups/20260925-165844-584512/`。Codex hooks 原先不存在，卸载应删除本轮创建的 `hooks.json`。
- `install-state.json` 为 `active=true`、`menu_installed=true`。配置散列与安装记录一致。

### 已核实的 hooks 机制与实现

- 来源：[OpenAI Hooks 官方文档](https://learn.chatgpt.com/docs/hooks)、本机 Codex 0.157.0 生成的 app-server schema，以及临时 `CODEX_HOME` 中的隔离探针。
- 用户级配置确为 `~/.codex/hooks.json`，结构为 `hooks → 事件名 → matcher 组 → hooks → type/command/timeout`。
- 本机 `hooks/list` 返回 `SessionStart` / `UserPromptSubmit` / `SessionEnd` / `Interrupt` 的定义与真实 hash。`TurnStarted` 单独配置时返回零条 hooks；二进制常量不能作为可配置性的证明。
- 按实际语义使用 `UserPromptSubmit` 作为每轮开始，`SessionStart` 仅记录生命周期；关闭和中断清除状态。完成继续来自原 `notify`，通过 session/thread 与 turn 标识关联。没有用 SessionStart 冒充持续运行。
- 信任通过 `hooks/list` 获取真实 hash，使用 Codex `config/batchWrite` 写入四条自有定义的 `hooks.state.*.trusted_hash`，再次列表确认全部 `trusted`。不使用 bypass，不信任其他插件/项目的 hooks。配置写入前备份，写入后核对除预期信任项外的 TOML 语义与 `notify` 原行不变。
- Claude 保留既有 `UserPromptSubmit`，仍挂 `Stop` / `Notification` / `PermissionRequest`；Codex 仅新增上面四个事件。没有新增 `PreToolUse` / `PostToolUse`。
- 复用了前一轮的 Swift 菜单与增量日志读取结构，替换了仅显示 Claude 运行中的假设。两边运行中会话均显示来源、项目和时长，最近 10 条显示完成时刻与末条回复摘要。
- Claude 存活仅跟随 `NSWorkspace.shared.runningApplications` 中的 Claude.app；退出/重新启动 App 会清除旧运行态，不检查 TTY、ps 或 lsof。处理真实桌面 `Stop` 中仍在运行的 `background_tasks`，保留运行态直到后续完成；同一 turn 的追加提示不重置计时。
- D001/D002/D005 保持：`bin/` 中三个事件/通知脚本逐字节未变，App 不发通知、不播放声音；没有权限等待界面、刘海、用量、终端跳转或手机推送。未读取或复制 Open Island 的 GPL 实现。

### 真实验证

1. **Codex**：真实 CLI 任务收到 `SessionStart → UserPromptSubmit → agent-turn-complete → SessionEnd`，开始/结束的 session 与 turn 标识一致。用生产源码中的 EventStore 做同步只读观测，运行态连续采样到 25 秒，完成后消失并出现 `AGENTBELL_STAGE2_CODEX_STATE_OK` 摘要。
2. **Claude 桌面新会话**：通过 Computer Use 新建 `AgentBell stage 2 acceptance`，实际执行一条 `sleep 25`。真实 `UserPromptSubmit` 后，运行态采样到 15 秒，未在约 6 秒被误判结束。桌面端把 sleep 转为后台任务后提前发出一个带 `background_tasks: running` 的 Stop，随后继续并返回最终 `AGENTBELL_STAGE2_CLAUDE_OK`；据此补齐背景任务保留逻辑。最终源码逐条重放这段真实事件，状态为 `运行 → 保持运行 → 保持运行 → 完成`，只产生一条最终完成摘要。
3. **菜单与提示音**：用户明确确认“能看到，菜单已展开”和“听到了”。Computer Use 无法绑定无窗口的菜单栏 App（timeout），因此菜单视觉确认来自用户；运行状态的时序证据来自真实事件和同源状态读取器。
4. **实际卸载**（16:58:40，UTC+8）：退出码 0；App 目录、LaunchAgent 文件、运行进程、launchd service 均已移除；两份 agent 配置与原备份逐字节相同，Codex hooks 恢复为原先不存在，日志保留。
5. **重新安装**（16:58:44）：退出码 0；`settings.json`、`config.toml`、`hooks.json` 三份文件与卸载前快照逐字节相同；App 和 LaunchAgent 恢复运行。
6. **重装回归**：真实 Codex 任务返回 `AGENTBELL_STAGE2_REINSTALL_OK 323`，退出码 0。进程采样捕获 `/usr/bin/afplay`、`osascript`，以及原 SkyComputerUseClient 的完整 argv，与真实 notify argv 完全一致。Computer Use 仍能读取、点击、输入和发送 Claude 桌面会话。
7. **基础检查**：shell 语法、Python AST、Swift 编译、codesign strict 验签、两份 plist lint、`git diff --check` 均通过。运行目录事件脚本与仓库一致；hooks 信任回查全部为 trusted；未产生 AgentBell `errors.log`。没有搭建测试框架、CI 或全量回归。

### 证据与人工确认

- 私有证据在 `~/.agentbell/verification/stage2/`：`codex-events.json`、`claude-events.json`、`live-state.jsonl`、`restore-result.json`、`codex-result.json`、`computer-use-system.log`；不提交原始会话内容到公开仓库。
- 登录自启已做配置与实际加载验证；**重启/注销后自动出现铃铛仍待下次登录人工确认**。
- Codex 声音和菜单记录已由用户确认；Claude 声音、系统横幅、权限请求实际场景仍待确认。
- 原 Computer Use 客户端在本轮 CLI 完成后仍记录 `ComputerUseIPCClient.Error Code=0`（17:00:03）。阶段 1 已确认直接调用也会复现；本轮串联完整参数已实测，未改其配置/实现，不宣称底层 IPC 无错误。
- 强制杀死 Codex 可能缺少 SessionEnd/Interrupt，运行态可残留；没有引入进程轮询或会话文件推测。已有会话需新开以加载新增 hooks。

---

## 2026-09-25 · 本轮真实验证与卸载重装

### 当前生产状态

- **已恢复安装，active=true**。两份配置与本轮卸载前逐字节一致；Claude 仍仅有 `Stop` / `Notification` / `PermissionRequest`，Codex 保留 `turn-ended` 串联。
- 当前安装备份：`~/.agentbell/backups/20260925-155909-561129/`。它包含原始两份配置及重新归档的 `vibe-island` 目录。
- 旧备份 `20260925-155211-033031/` 的两份配置仍保留；其中的 `vibe-island` 在卸载时移回原位、重装时移入新备份，**当前回退以 install-state.json 指向的新备份为准**。

### 本轮实际验证

1. **Codex CLI 真实任务**：CLI 0.157.0 完成算术任务，返回 `AGENTBELL_REAL_CODEX_20260925 323`，退出码 0。15:56:56 左右收到对应 `agent-turn-complete` 原始负载；观察到 `/usr/bin/afplay .../Submarine.aiff` 和 `osascript` 通知进程。用户在本轮明确回复“听到了”。
2. **Computer Use 串联**：系统日志证实原 `SkyComputerUseClient` 收到了同一任务的 thread/turn 标识。任务完成后，Computer Use 实际完成了 Claude 界面读取、新会话点击、输入与发送。进程采样未捕获原客户端完整 argv，因此不将采样当作参数逐字节证明；参数透传依据仍为包装脚本与 worker 的实现。
3. **Computer Use 已知限制**：原客户端在 CLI 完成通知时记录 `ComputerUseIPCClient.Error Code=0`。15:58:10 用该真实事件的同一参数直接调用原程序，退出码 0，但系统日志出现相同 IPC 错误。此错误直接调用也可复现，未发现串联新增故障；不宣称底层通知 IPC 无错误通过。
4. **Claude 桌面端真实新会话**：通过 Code 页的 `New session in agentbell` 新建“AgentBell hooks 桌面会话验证”，发送无工具、无文件修改的任务；界面完成并回复 `AGENTBELL_REAL_CLAUDE_20260925_OK`。15:58:30（UTC+8）日志新增 `source: claude`、`hook_event_name: Stop`，`last_assistant_message` 与界面标记一致，`stdin_timed_out=false`。此前唯一 Claude 记录是 `smoke-test`，本次已取得真实新会话证据。**本机当前桌面版本确实触发 Stop hook**；未引入轮询。
5. **卸载实测**：15:59:09 执行 `./uninstall.sh`，退出码 0；Python `read_bytes()` 比较两份恢复后的配置与旧备份，均为 `True`。`settings.json` 3564 字节，`config.toml` 18215 字节；Vibe Island 目录恢复，日志保留。
6. **重新安装**：紧接着执行 `./install.sh`，退出码 0；重新移除 11 个 Vibe Island hooks 并归档目录。两份配置与卸载前的内存字节快照再次比较，均为 `True`。
7. **基础检查**：shell 语法、Python AST 解析、`git diff --check` 通过；运行目录三个脚本与仓库逐字节一致。JSON/TOML 可解析，配置散列匹配安装记录，Codex 相对备份仅第 11 行变化，原 notify 数组保存在运行配置中；未生成 AgentBell `errors.log`。

### 私有证据位置（不提交公开仓库）

- `~/.agentbell/logs/events.jsonl`：两边真实原始事件。
- `~/.agentbell/verification/codex-result.json`、`codex-task.log`：真实 CLI 结果及声音/通知进程采样。
- `~/.agentbell/verification/computer-use-system.log`、`computer-use-direct.json`：串联和原程序直接调用的对照。
- `~/.agentbell/verification/restore-result.json`：卸载、字节比对、重装及新备份位置。

### 人工确认与已知问题

- Codex 提示音已由用户确认；Claude 的 Glass 提示音、系统横幅显示，以及真实 `Notification` / `PermissionRequest` 场景尚未确认。
- Computer Use 的 CLI 完成通知 IPC 错误如上，界面操作可用，但这项仍有底层错误；本轮未改其配置或实现。
- 真实 CLI 启动仍出现 Linear 未认证、Figma OAuth、Playwright 握手失败和插件目录请求失败告警；任务本身成功，未越界修复这些配置。
- 本轮运行脚本无需修改；只补充操作说明与验证记录。未新增单元测试框架、CI、全量回归、菜单栏或手机推送。
- Git：保留既有 WIP `b67a313`，本轮文档另行提交并一并推送。远程同步结果以本轮最终回复和实际 Git 状态为准。

---

以下为上一轮历史记录；其中“未完成”条目由上方本轮记录更新。

## 2026-09-25 · 阶段 1 执行中被用户主动暂停

### 已完成

- 规划文档齐备：`设计说明.md`、`当前需求.md`、`任务-阶段1.md`、`PROJECT_CONTEXT.md`
- **公开仓库已建并推送**：https://github.com/huan1992929/agentbell
- Codex 已实现 `bin/`、`lib/`、`install.sh`、`uninstall.sh`，并**实际执行了安装**

### 生产环境当前生效状态（重要）

用户的两份 agent 配置**已被修改，且状态一致可用**：

| 文件 | 当前状态 |
|---|---|
| `~/.claude/settings.json` | 只剩 `Stop` / `Notification` / `PermissionRequest` 三个 hook，全部指向 `~/.agentbell/bin/agentbell-event`。vibe-island 引用已彻底清除，`statusLine` 置为 null |
| `~/.codex/config.toml` | 第 11 行 `notify` 指向 `~/.agentbell/bin/agentbell-codex-notify`，固定参数 `"turn-ended"` 保留 |

备份在 `~/.agentbell/backups/20260925-155211-033031/`，含 `settings.json`、`config.toml`、`manifest.json`，以及整个 `vibe-island` 目录。

`~/.agentbell/bin/` 下三个脚本已就位：`agentbell-event`、`agentbell-codex-notify`、`agentbell-worker.py`。

### 已通过的基础检查

- `settings.json` 是合法 JSON，hook 数量和目标正确，无 vibe-island 残留
- Codex 串联正确：包装脚本原样透传 `"$@"` 并立即 `exit 0`；worker 内 `launch([original[0], *args])` 调用原 Computer Use 程序，原有行为不受影响
- 冒烟测试：手动喂一条 `Stop` 事件，退出码 0，`~/.agentbell/logs/events.jsonl` 正确记录了原始负载

### 未完成 / 待办

1. **未做真实场景验证**：没有实际跑一次 Codex 任务确认响声，也没验证 `uninstall.sh` 能否真正还原（任务描述里要求实际验证一次）
2. **Claude 桌面端 hooks 是否触发，仍未定论**。这是本项目最大未知。验证方法：装好探针后**新开一个桌面端会话**（hooks 在会话启动时加载，中途改配置对当前会话不生效），跑一轮，看 `events.jsonl` 里有没有 `source: claude` 的记录
3. 阶段 2（菜单栏常驻 + 开机自启）未开始
4. `bin/`、`lib/`、`install.sh`、`uninstall.sh` 已提交为 WIP，但未经完整验证

### 桌面端监控的退路（已证实可行）

若 hooks 在桌面端不触发，改用轮询会话文件：桌面端确实在实时写
`~/.claude/projects/<项目目录名>/<会话id>.jsonl`。
文件增长 = 任务在跑；停止增长且最后一条是助手消息 = 该轮结束。
代价：延迟 1～2 秒，且无法区分"完成"与"等待批准"。

### 环境变化（影响后续判断）

- **Codex CLI 已从 0.77.0 升级到 0.157.0**，装在 `~/.npm-global/bin/codex`（无需 sudo，靠 PATH 优先级盖过 `/usr/local/bin` 的旧版；旧版保留，`npm uninstall -g @openai/codex` 即可退回）
- 升级原因：旧 CLI 不认识用户默认模型 `gpt-6-astra`，而用户的 ChatGPT 账号又拒绝全部旧模型（实测 `gpt-5.2-codex`、`gpt-5.1-codex-max`、`gpt-5.1-codex-mini`、`gpt-5.1-codex`、`gpt-5-codex`、`gpt-5.1` 均被拒），两头卡死，只能升级
- 网络状态与 9 月 23 日不同：github.com 与 huggingface.co 现均可正常访问
- 用户的 Codex 配了 6 个 MCP，其中 `linear`（未登录）、`figma`（OAuth 失效）、`playwright`（握手失败）三个是坏的，每次启动都会白等几秒。**未处理，已询问用户是否清理，尚未答复**
