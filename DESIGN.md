---
name: AgentBell
description: 面向 Codex 当前任务的原生 macOS 状态胶囊
colors:
  ink: "rgb(94% 94% 94%)"
  quiet: "rgb(62% 62% 62%)"
  active: "rgb(49% 88% 72%)"
  attention: "rgb(96% 72% 40%)"
  surface: "rgb(2.5% 2.5% 2.5%)"
  notch: "#000000"
  row-hover: "rgb(100% 100% 100% / 5.5%)"
  row-pressed: "rgb(100% 100% 100% / 10%)"
  divider: "rgb(100% 100% 100% / 7%)"
typography:
  project:
    fontFamily: "NSFont.systemFont"
    fontSize: "13pt"
    fontWeight: 600
  body:
    fontFamily: "NSFont.systemFont"
    fontSize: "12pt"
    fontWeight: 400
  label:
    fontFamily: "NSFont.systemFont"
    fontSize: "11pt"
    fontWeight: 500
  stamp:
    fontFamily: "NSFont.monospacedDigitSystemFont"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  compact: "18pt"
  expanded: "22pt"
  row: "10pt"
components:
  task-row:
    height: "68pt"
  quota-track:
    height: "2pt"
---

# AgentBell 界面实现

依据 D006 / D008 / D009。原生 AppKit，Operate 模式；精修信息层级，不改成网页或复制第三方视觉。以 `app/Island.swift` 为实现真值，尺寸均为逻辑点。

## 信息规则

- 只显示 Codex。项目名称是行内主信息，用户提示词是两行以内的说明，运行时长或相对结束时间辅助扫描；不逐行重复 Codex 品牌，不把提示词改写成成功结论。
- 顶部直接说“正在进行 · 数量”或“当前空闲”。没有运行任务不保留空运行分区，也不声称监听已就绪。读取或导航出现真实异常时显示“需要关注”、具体问题与“打开 Codex”入口；不设计虚假的审批状态。
- 运行优先。同一会话只保留最新结束记录，不按项目名合并不同会话；运行会话不在历史重复。默认近期两条，按需展开至五条。标题缺失如实说明；心跳不进入列表或计数。
- 额度独立于任务列表。Codex 用量、记录更新时间/缓存标记、每个窗口的已用百分比、细进度条、相对重置时间；两个窗口纵向排列，不压小字号。0% 无填充，<1% 使用明确文字，数据缺失不画进度条，缓存/重置过期不归零。

## 视觉

系统字体与 SF Symbols。主要文字白色，次要文字中灰；薄荷色仅表示正在进行，琥珀色表示异常或接近额度上限，不用颜色标识重复品牌。任务行取消彩色竖条；悬停只加轻背景和右上跳转箭头，标题不被覆盖。

无刘海主体为近黑色，有刘海主体和连接同为纯黑。取消整圈白色描边，保留系统窗口阴影；额度与列表之间只有低对比细分隔线。无大面积毛玻璃、渐变、像素字体或装饰光效。

## 尺寸和适配

- 普通屏顶部居中；胶囊宽按内容计算，148–360pt，高 34pt。顶部 `min(visibleFrame.maxY, frame.maxY − 24) − 7`。
- 刘海屏读取 safe area 高度和辅助区域间隙，最小间隙 185pt；折叠时两侧分别显示来源符号和数量/空闲，避开实际刘海。展开连接与主体同底色。
- 展开宽 `min(420, screen.width − 32)`；高随当前内容计算，普通屏 180–520pt，加刘海高度，受可见屏幕约束。单额度、两条历史的空闲面板约 343pt；双额度约 381pt。并发超过容量才滚动。
- 行高 68pt，项目 13pt，提示词 12pt（两行），时间 11pt。左侧行内距 14pt，列表外距 10pt；额度左右距 24pt，每个窗口占 38pt，轨道高 2pt。

## 交互

悬停临时展开，移出 0.35 秒后收起；显式展开至少保留 3 秒。收展 160ms ease-out，尊重系统减少动态效果设置。不会因加入动画而抢键盘焦点。

图钉固定时显式展开，并停在该屏幕，鼠标跨屏不会带走面板；取消固定后恢复跟随与自动收起。右上收起按钮同时解除固定。列表较早记录用明确文字按钮展开/收起。

任务整行可点、悬停箭头提示打开，tooltip 与辅助功能标签说明真实目标；CLI 仍明确不定位终端会话。固定时打开会话也保留面板；临时查看时打开后收起。导航投递不冒充精确跳转成功。

`.nonactivatingPanel`，不能 key/main；主菜单层级加 1，支持 Spaces 和全屏辅助。菜单栏保留显示/退出入口。

## 验证边界

实际任务与固定/历史操作用 Computer Use 检查。`checks/preview/main.swift` 是离屏布局样例，只渲染检查图片，绝不写生产事件或在安装 App 内伪造任务。原生空闲、刘海、异常、双额度状态样例和真实任务验收分开记录在 progress。
