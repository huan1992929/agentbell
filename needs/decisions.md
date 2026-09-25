# 决定记录

## D001 阶段 2 不把通知与声音迁移到菜单栏 App（2026-09-25，已确认）

- **决定与范围**：通知和提示音继续由事件脚本发出，菜单栏 App 只负责状态显示。仅覆盖阶段 2，不排除以后再迁。
- **依据**：脚本发通知这条路已在阶段 1 用真实事件验证通过（Codex 侧用户已确认听到声音，Claude 侧拿到真实 Stop 负载）。迁到 App 会引入新的失败模式——App 没启动时就完全没有提醒，而现在脚本是无条件生效的。不拿已验证可用的东西去换一个未验证的架构。
- **覆盖关系**：替代 `设计说明.md` 第三节"阶段 2 引入菜单栏常驻进程后，通知与声音改由它统一发出"这一句。该节其余内容仍然有效。

## D002 不围绕"等待批准"设计任何界面（2026-09-25，已确认）

- **决定与范围**：菜单栏和通知的信息层级以"任务完成"为核心。`PermissionRequest` hook 保留但不作为设计依据。
- **依据**：用户答复本人始终以完全访问模式运行 Codex 与 Claude，权限请求实际不会触发。阶段 1 的真实 Claude 负载里 `permission_mode` 为 `auto`，与此一致。
- **覆盖关系**：不替代既有决定。`PermissionRequest` hook 继续挂着——它零开销，万一以后改用受限模式就能直接用。

## D003 Codex 侧无法获知"任务进行中"（2026-09-25，**已被 D004 推翻**）

- **决定与范围**：菜单栏对 Codex 只显示"最近完成"，不显示"正在运行"。Claude 侧可通过加挂 `UserPromptSubmit` 获得开始信号，从而显示运行中与已运行时长。
- **依据**：Codex 的 `notify` 只有 `turn-ended` 这一个回调点，没有对应的 turn-started。不为这个去轮询进程列表或解析终端，代价与收益不成比例。
- **覆盖关系**：细化 `当前需求.md` 阶段 2 的"显示哪个 agent 在跑"，该描述对 Codex 不成立。

## D004 Codex 有完整 hooks 系统，推翻 D003（2026-09-25，已确认）

- **决定与范围**：Codex 侧同样可以显示"运行中 + 已运行时长"，与 Claude 侧对等。完全替代 D003。
- **依据**：实测 Codex CLI 0.157.0 的二进制中存在完整 hook 事件常量：`SessionStart`(53) / `UserPromptSubmit`(18) / `TurnStarted`(20) / `PreToolUse`(55) / `PostToolUse`(42) / `SessionEnd`(33)、`hook_event_name`(27)，以及配置文件 `hooks.json` 与 `--dangerously-bypass-hook-trust` 命令行开关。另外 Open Island 的文档说明桌面版 Codex 还可通过 `codex app-server` 的 JSON-RPC 拿到 `thread/started`、`turn/started`、`turn/completed`。
- **D003 错在哪**：它的依据来自**升级前的 CLI 0.77**，那时确实只有 `notify`。CLI 已在本轮升级到 0.157.0，但我把旧结论直接带进了新设计，没有重新验证。这正是 needs 规范第二节"外部原因被用来关闭功能时，先验证该依据本身"要防的情况。
- **后续要求**：接入前先查清 `hooks.json` 的实际位置与格式，并确认它与现有 `notify` 串联是否冲突。**`notify` 串联不能动**——Codex Computer Use 仍依赖它，且阶段 1 已验证通过。仍然不挂 `PreToolUse` / `PostToolUse`。

## D005 AgentBell 定位为个人极简版，不追功能广度（2026-09-25，已确认）

- **决定与范围**：AgentBell 只服务本人的两个 agent（Codex、Claude 桌面端），只做"任务完成提醒 + 菜单栏状态"。**明确不做**：多 agent 广度支持、终端精准跳转、用量额度面板、刘海 UI、手机推送。
- **依据**：用户在了解 `Octane0411/open-vibe-island`（GPL v3，13 agent、15+ 终端、刘海 UI、用量面板，可 `brew install --cask open-island`）之后，仍选择继续自建，并明确定位为"只给自己用的极简版"。想要完整体验时装 Open Island 即可，两者不冲突。
- **刘海 UI 不做的具体理由**：实测用户主屏是 LG HDR 4K（无刘海，坐标原点在其上），MacBook 内建屏（刘海 185×32pt）是副屏。刘海 UI 在其主要视野之外，投入产出比不成立。
- **许可证边界**：Open Island 是 GPL v3，**只读思路、不复制代码**。本项目保持自有实现，不引入 GPL 传染。
- **覆盖关系**：收窄 `当前需求.md` 阶段 2 的范围；不影响 D001、D002、D004。

## D006 改做灵动岛形态 + 点击直达会话（2026-09-25，已确认）

- **决定与范围**：部分推翻 D005 的两条排除项。
  1. **做灵动岛 UI**：有刘海的屏幕贴刘海显示；**无刘海的屏幕退化成顶部居中的浮动胶囊**。
  2. **做点击跳转**：点条目直接打开对应会话界面，不再弹独立窗口。
- **依据**：用户明确表示更喜欢 Vibe Island / Open Island 的灵动岛形态，并主动给出了无刘海屏的降级方案（顶部居中）。这回应了 D005 当初排除刘海 UI 的唯一理由——用户主屏 LG HDR 4K 无刘海。降级方案成立后，该理由不再有效。
- **已核实的技术前提**：
  - `Claude.app` 注册 `claude://`，存在 `claude://code/continue`、`claude://code/needs-input`、`claude://code/new` 三个路径；`sessionId` 作为参数名在应用内出现 148 次。**确切格式需实测**。
  - `ChatGPT.app` 注册 `codex://`；Open Island 文档称 `codex://threads/<id>` 可打开指定会话。**需实测**。
  - 内建屏刘海 185×32pt，`safeAreaInsets.top = 32`，`auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 可用。
- **仍然排除**（D005 其余部分继续有效）：多 agent 广度、终端精准跳转（终端里的 CLI 会话最多激活终端 App，不做 tab/split 定位）、用量额度面板、手机推送。
- **许可证边界不变**：不复制 Open Island 的 GPL v3 代码，只读思路。

## D007 接入 Codex app-server 以获取桌面版运行状态（2026-09-25，已确认）

- **决定与范围**：允许新增一个与本地 `codex` app-server 通信的组件，用于获取 Codex **桌面版**的开始/结束事件。这是 D005"极简"定位下的必要例外，不是功能扩张。
- **依据**：实测数据显示 `agent-turn-complete` 16 次而 `SessionStart` 仅 5 次——**Codex 桌面版不读 `~/.codex/hooks.json`**，只有 CLI 读。桌面版任务因此永远无法进入"运行中"，这是用户实际报告的缺陷（两个任务在跑只显示一个），不修则该场景始终不可用。
- **已知可用线索**：
  - `notify` 负载含 `thread-id`、`turn-id`、`cwd`，以及 `client` 字段（观察到取值 `"Codex Desktop"`），可据此区分来源并关联会话。
  - `codex agents` 子命令的说明为"Browse all agent sessions on the shared local app-server daemon"，证实存在本地共享 app-server。
  - Open Island 文档称桌面版 Codex 可通过 app-server 的 JSON-RPC 取得 `thread/started`、`turn/started`、`turn/completed`。**仅作思路参考，不复制其 GPL 代码。**
- **附带缺陷**：`SessionStart` 比 `SessionEnd` 多一次，存在永不关闭的残留运行条目，需一并修复。
- **覆盖关系**：放宽 D005 的"不新增组件"含义，不影响 D005 其余排除项（多 agent 广度、终端精准跳转、用量面板、手机推送仍不做）。
