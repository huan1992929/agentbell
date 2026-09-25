# 进展记录

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
