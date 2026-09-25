# AgentBell

macOS 上的本地 Agent 提醒工具，为 Codex CLI 和 Claude hooks 提供可区分的提示音与系统通知。

阶段 1 提供事件提醒，阶段 2 增加 Swift 原生菜单栏：同时显示 Codex / Claude 的运行会话、项目、已运行时长和最近 10 条完成摘要。通知与声音仍由事件脚本发送，退出菜单栏 App 后提醒仍可用。

不使用网络服务，不安装第三方依赖。运行日志和用户配置仅保存在 `~/.agentbell/`，不提交到仓库。

范围以 [`needs/decisions.md`](needs/decisions.md) 的 D001 / D002 / D004 / D005 为准。

## 使用

在仓库目录执行（macOS，Command Line Tools、Python 3.11+、Codex CLI；本机验证版本为 0.157.0）：

```sh
./install.sh
```

安装脚本用 `swiftc` 编译、组装 `.app` 并 ad-hoc 签名，写入登录自启 LaunchAgent 并启动；不用 Xcode 工程、SPM 或第三方库。点击菜单栏铃铛查看状态，有任务运行时图标旁显示数量。

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

菜单栏每秒增量读取事件日志；Claude 的存活跟随 `Claude.app`，不检查终端或 TTY。带有仍在运行的 `background_tasks` 的 Claude `Stop` 不会提前清除菜单状态。摘要只来自完成事件，不抓取会话文件。

## 验证边界

- 2026-09-25：Codex 和新建 Claude 桌面会话均取得真实开始 / 完成事件；状态读取验证经过 6 秒后仍保持运行，最终转为完成。用户确认菜单记录可见、Codex 提示音仍能听到。
- 实际卸载验证了 App、进程、LaunchAgent 和新增 hooks 移除、原配置按字节还原；重装后三份配置与卸载前逐字节相同。
- 重装后真实 Codex 任务回归捕获到原 Computer Use 客户端的完整转发参数，Computer Use 界面操作可用。原客户端曾出现直接调用也能复现的 IPC 错误，详情见进展记录。
- 已验证 `RunAtLoad` 配置、LaunchAgent 加载和进程启动；未重启或注销电脑。下次登录后确认铃铛自动出现即可完成这一项人工验收。
- Claude 提示音试听、系统通知横幅和权限请求真实场景仍待人工确认。
- 强制杀死 Codex 可能来不及产生关闭事件，菜单可能保留最后的运行状态；没有额外引入进程轮询来猜测完成。

详细证据与当前安装状态见 [`needs/progress.md`](needs/progress.md)。
