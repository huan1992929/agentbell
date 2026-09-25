# AgentBell

macOS 上的本地 Agent 提醒工具，为 Codex CLI 和 Claude hooks 提供可区分的提示音与系统通知。

阶段 1 按 [`needs/任务-阶段1.md`](needs/任务-阶段1.md) 实现：短路径事件采集、Codex 原通知串联、配置备份与一键还原。Claude 桌面端是否触发 hooks 需要人工确认。

不使用网络服务，不安装第三方依赖。运行日志和用户配置仅保存在 `~/.agentbell/`，不提交到仓库。

实现细节见 [`needs/设计说明.md`](needs/设计说明.md)。
