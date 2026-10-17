# 晴日界面资料

“晴日”就是拾日现在这套界面：浅蓝灰底、深色字、蓝色主操作，今日页头上是天空和波浪，底部是悬浮导航加助手入口。

这个目录只放数值和说明。真正跑起来的代码在 `apps/mobile/lib/ui/v2`，页面在 `apps/mobile/lib/features`。这里没有独立原型，没有目标截图，也没有另一份 Flutter 工程，所以不存在“把参考实现同步进 App”这种步骤，以前写文档的人容易误会。

## 从哪儿看起

1. [界面维护规则](../shiri/MASTER.md)：保存、未知时间、请假、无障碍、截图这些共同要求。
2. [界面说明](DESIGN.md)：现在颜色、排版、组件、动画具体怎么做的。
3. [tokens.json](tokens/tokens.json)：颜色、字体、间距、圆角、布局、动效参数，文件版本 `2.0.0`。
4. `apps/mobile/lib/ui/v2/shiri_tokens.dart`：Flutter 里对应的数值和主题扩展。
5. `apps/mobile/lib/ui/v2/shiri_theme.dart`：Material 主题入口。

应用版本和 tokens 版本是两码事。App 的版本在 `apps/mobile/pubspec.yaml` 里，现在是 1.1.1。设计数值文件是 2.0.0 不代表软件也是 2.0，别混着写。

## 代码在哪

| 内容 | 现在的实现 |
| --- | --- |
| 浅色主题 | `shiriLightTheme()`，App 入口接的就是它 |
| 高对比主题 | `lib/ui/campus_theme.dart`、`lib/ui/accessibility.dart` |
| Forui 控件适配 | `lib/ui/forui_theme.dart` |
| 按钮、输入、列表、弹窗 | `lib/ui/app_controls.dart` |
| 通用弹层和键盘避让 | `lib/ui/app_sheet.dart` |
| 导航坞和助手胶囊 | `lib/ui/v2/widgets/glass_dock.dart`、`lib/ui/app_navigation.dart` |
| 天空、太阳、波浪 | `lib/ui/v2/widgets/sky_header.dart`、`wave_edge.dart` |
| 周课表块 | `lib/ui/v2/widgets/schedule_block.dart` |
| 分段选择、完成勾选、数字、骨架 | `lib/ui/v2/motion/` |
| 周课表滑动切周 | `lib/features/calendar/calendar_week_pager.dart` |

表里的路径从 `apps/mobile` 开始算。品牌标志、导航图标、空状态插画在 `apps/mobile/assets`，用 `flutter_svg` 读。

## 现在做到哪一步

主入口接的是浅色主题和高对比主题。tokens 和主题代码里还有深色数值，但入口没接 `darkTheme`，也没有切换设置，所以深色模式不能算成已交付的功能。

四个主页面各自保留状态和滚动位置。周课表横向分页；底部点击和任务状态选择去掉了大块灰色按压反馈。助手是统一的可拖动面板，现在没有“从底部胶囊变形展开”那种容器动画。

组件留了可复用参数，但页面里仍有写死的局部数值。改 tokens 不会自动更新所有局部样式，得顺手看调用处，尤其是课表密集信息、表单和窄屏。

## 怎么维护

改颜色、字体、通用尺寸时，JSON 和 Flutter 数值一起改，再看一眼 `campus_theme.dart` 和 Forui 主题有没有被带偏。改单页布局先改那一页；确实重复了再往共用组件提——为了“统一”把不同的东西都塞进同一种卡片，那不是统一，是偷懒。

改完跑 `flutter analyze` 和相关测试，再用模拟器看普通字号、360 dp 宽加 1.6 倍字号、减少动画、高对比、键盘弹开这几种。截图从当前 App 里取，标清版本和状态。这份说明讲的是实现思路和改法，代替不了一次新的运行验收。

1.1.1 那轮标签页的变化（静默整理、点名称看关联记录、跨学期列表）写在[界面说明](DESIGN.md)里，这里不重复。
