# AgentBell

macOS 上的本地 Agent 提醒工具，为 Codex CLI 和 Claude hooks 提供可区分的提示音与系统通知。

阶段 1 按 [`needs/任务-阶段1.md`](needs/任务-阶段1.md) 实现：短路径事件采集、Codex 原通知串联、配置备份与一键还原。已在本机验证 Codex CLI 完成提醒和 Claude 桌面端新会话的 `Stop` hook；其他机器仍需实际验证。

不使用网络服务，不安装第三方依赖。运行日志和用户配置仅保存在 `~/.agentbell/`，不提交到仓库。

实现细节见 [`needs/设计说明.md`](needs/设计说明.md)。

## 使用

在仓库目录执行（macOS，Python 3.11+，使用标准库 `tomllib`）：

```sh
./install.sh
```

安装后正常使用 Codex；Claude 桌面端需要**新开 Code 会话**才会加载 hooks。任务完成分别播放 Submarine / Glass，需要处理时播放 Ping。安装脚本打印配置修改位置和备份目录。

```sh
# 查看事件（原始负载可能包含会话文本，请勿公开上传）
tail -f ~/.agentbell/logs/events.jsonl

# 完整还原本次安装前的配置，保留运行日志
./uninstall.sh

# 恢复安装
./install.sh
```

声音映射及开关在 `~/.agentbell/config.json`。运行脚本、日志和备份位于 `~/.agentbell/`。若安装后手动修改了 agent 配置，卸载会拒绝覆盖，需先核对差异。重复安装会保留原备份；更新运行脚本需卸载后重新安装。

## 验证边界

- 2026-09-25：真实 Codex CLI 任务触发完成事件，用户确认听到提示音；Claude 桌面端新会话收到真实 `Stop`，不是手工注入的事件。
- 实际执行卸载后，两份配置与安装前备份逐字节相同；重新安装后，两份配置也与卸载前逐字节相同。
- Computer Use 界面读取、点击和发送可用。CLI 完成通知中原客户端出现 IPC 错误；用相同参数直接调用原程序也出现相同错误，不能把这项报告为无错误通过。
- Claude 的 `Notification` / `PermissionRequest` 真实场景、Claude 提示音试听和系统通知横幅仍待人工确认。

详细证据与当前安装状态见 [`needs/progress.md`](needs/progress.md)。
