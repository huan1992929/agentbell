# 进展记录

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
