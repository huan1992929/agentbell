---
name: AgentBell
description: 原生 macOS 顶部任务状态胶囊
colors:
  ink: "rgb(94% 94% 94%)"
  quiet: "rgb(64% 64% 64%)"
  mint: "rgb(49% 88% 72%)"
  clay: "rgb(92% 68% 51%)"
  surface: "rgb(6.5% 6.5% 6.5% / 99%)"
  notch: "#000000"
  border: "rgb(100% 100% 100% / 14%)"
  row-hover: "rgb(100% 100% 100% / 6.5%)"
  row-pressed: "rgb(100% 100% 100% / 12%)"
  destination-surface: "rgb(10% 10% 10%)"
typography:
  title:
    fontFamily: "NSFont.systemFont"
    fontSize: "16pt"
    fontWeight: 600
  project:
    fontFamily: "NSFont.systemFont"
    fontSize: "13pt"
    fontWeight: 500
  body:
    fontFamily: "NSFont.systemFont"
    fontSize: "12pt"
    fontWeight: 400
  source:
    fontFamily: "NSFont.systemFont"
    fontSize: "12pt"
    fontWeight: 600
  label:
    fontFamily: "NSFont.systemFont"
    fontSize: "11pt"
    fontWeight: 600
  stamp:
    fontFamily: "NSFont.monospacedDigitSystemFont"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  compact: "18pt"
  expanded: "22pt"
  row: "12pt"
  destination: "5pt"
components:
  compact-island:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.compact}"
  expanded-island:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.expanded}"
  task-row:
    height: "52pt"
  task-row-hover:
    backgroundColor: "{colors.row-hover}"
    rounded: "{rounded.row}"
  task-row-pressed:
    backgroundColor: "{colors.row-pressed}"
    rounded: "{rounded.row}"
---

# Design System: AgentBell

## Overview

依据 `needs/decisions.md` D006 / D008 与 `app/Island.swift` 记录已实现的 AppKit 界面。保留深色胶囊、低干扰状态提示和整行点击入口；尺寸单位均为 AppKit 逻辑点。用户已确认双屏跟随正常；这里的其余行为来自源码记录，不代替端到端验收。

## Colors

薄荷色 `mint` 标识 Codex、运行数量及活动状态；陶土色 `clay` 标识 Claude。`ink` 承载主要文字，`quiet` 承载任务标题、时间与辅助提示。来源名称和状态文字与颜色同时出现。深色 `surface`、黑色刘海连接区及轻描边构成底层。

前置颜色值按源码 `NSColor(calibrated…)` 的通道比例记录；实际显示仍由 AppKit 色彩管理决定。

## Typography

沿用系统字体：标题、项目名、来源名、任务标题依次使用上述角色。紧凑状态为系统字体 12pt medium，底部提示为 11pt regular；时间使用等宽数字，刘海旁计数为等宽数字 12pt。长文字尾部截断，任务行另附 tooltip 与辅助功能标签。

## Layout

- 单个面板跟随**鼠标所在屏幕**；跨屏先收起并重新定位。这里的“跟随焦点”不表示追踪键盘焦点或前台窗口。
- 无刘海：顶部水平居中，紧凑宽度按文字测量加 50pt，限制为 148–360pt，高 34pt；顶部取 `min(visibleFrame.maxY, frame.maxY − 24) − 7`。
- 有刘海：贴屏幕顶缘；刘海高度读取 `safeAreaInsets.top`，宽度取辅助区域间隙与 185pt 的较大值。紧凑面板宽为刘海宽度加 108pt，高为 `max(34, notch)`；来源字标和计数分列刘海两侧。
- 展开：宽 `min(460, screen.width − 32)`，高按内容自适应，普通屏 230–480pt，加上刘海高度并受可见屏幕限制。内容起始位置避开刘海，面板仍居中。
- 标题左距 23pt；滚动区域左右各 10pt，自 `notch + 49` 开始，高为 `max(0, panel.height − notch − 104)`。列表按“运行中”“最近完成”分组，行高见令牌；滚动位置在刷新时尽量保留。

## Elevation & Depth

透明、无边框的 `NSPanel` 使用系统窗口阴影，并显式采用 `.darkAqua` 外观；正文表面有 0.5pt 细描边。窗口层级为主菜单层级加 1，可加入各 Space 并作为全屏辅助窗口。阴影参数交由系统，未定义 CSS 阴影或模糊材质。

## Shapes

紧凑与展开胶囊使用各自圆角令牌。任务行悬停和按下背景向内缩进（横向 2pt、纵向 1pt）；来源色条宽 3pt，运行中高 28pt、完成项高 15pt，圆角 1.5pt；状态圆点直径 6pt。

## Components

- **状态胶囊**：悬停展开；点击切换收展。显式展开保留 3 秒，移出后延迟 0.35 秒收起；轮询间隔 0.12 秒。点击切换后抑制悬停 0.6 秒，打开条目后抑制 1 秒。当前切换直接更新窗口尺寸，没有自定义补间动画。
- **任务行**：来源、项目、时间置于首行，用户提示词标题置于第二行；不使用助手回复。悬停保留标题，路由目标说明见 tooltip 与辅助功能标签；整行点击调用现有导航，并先收起面板。目标是否精确到会话由导航结果决定，不在设计记录中宣称所有路由已验证。
- **额度**：底部一行显示 Codex 实际配额窗口、已用百分比、相对重置时间；系统字体 11pt，两个窗口时按宽度缩小到最低 9pt。Claude 无本地账号级数据，不显示。
- **列表与提示**：最近完成最多 5 条；运行显示已运行时长，完成显示相对时间。透明滚动容器使用自动隐藏的系统浮层滚动条；空列表显示说明。导航返回问题时，面板非激活展开，临时提示保留 6 秒并暂缓自动收起；到期刷新后恢复状态问题或操作提示。跨屏或显式点击仍可收起面板。
- **不抢焦点**：面板使用 `.nonactivatingPanel`，不能成为 key/main window；自绘视图不接受 first responder，但接受首次鼠标点击。初始化和显式展示调用 `orderFrontRegardless()`，点击任务后由导航打开目标应用。

## Do's and Don'ts

- Do 保持原生 AppKit、现有颜色、系统字体和真实状态；用鼠标屏幕与安全区域计算布局。
- Do 区分源码实现记录、用户已确认的双屏表现与仍需单独验证的路由行为。
- Don't 加入网页界面、第三方依赖、生成图片或复制 Open Island 代码。
- Don't 在设计样例中保存真实任务正文、会话标识或绝对家目录。
