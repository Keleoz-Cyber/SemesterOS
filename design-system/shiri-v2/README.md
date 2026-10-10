# 晴日界面资料

“晴日”是拾日当前使用的界面样式：浅蓝灰背景、深色文字、蓝色主要操作，天空和波浪用于今日页头部，底部使用悬浮导航和助手入口。

这份目录保存界面数值和说明。真正运行的 Flutter 代码在 `apps/mobile/lib/ui/v2`，页面在 `apps/mobile/lib/features`。当前目录没有独立原型、目标截图或另一份 Flutter 工程，不需要再执行一次“把参考实现复制进 App”的步骤。

## 从哪里看起

1. [界面维护规则](../shiri/MASTER.md)：保存、未知时间、请假、无障碍和截图等共同要求。
2. [界面说明](DESIGN.md)：当前颜色、排版、组件和动画的具体做法。
3. [tokens.json](tokens/tokens.json)：颜色、字体、间距、圆角、布局和动效参数，文件版本为 `2.0.0`。
4. `apps/mobile/lib/ui/v2/shiri_tokens.dart`：Flutter 使用的对应数值和主题扩展。
5. `apps/mobile/lib/ui/v2/shiri_theme.dart`：Material 主题入口。

应用版本与 tokens 版本是两回事。App 的版本由 `apps/mobile/pubspec.yaml` 管理，不能因为设计数值文件是 2.0.0 就把软件写成 2.0。

## 代码位置

| 内容 | 当前实现 |
| --- | --- |
| 浅色主题 | `shiriLightTheme()`，由 App 入口接入 |
| 高对比主题 | `lib/ui/campus_theme.dart` 和 `lib/ui/accessibility.dart` |
| Forui 控件适配 | `lib/ui/forui_theme.dart` |
| 按钮、输入、列表和弹窗 | `lib/ui/app_controls.dart` |
| 通用弹层与键盘避让 | `lib/ui/app_sheet.dart` |
| 导航坞和助手胶囊 | `lib/ui/v2/widgets/glass_dock.dart`、`lib/ui/app_navigation.dart` |
| 天空、太阳和波浪 | `lib/ui/v2/widgets/sky_header.dart`、`wave_edge.dart` |
| 周课表块 | `lib/ui/v2/widgets/schedule_block.dart` |
| 分段选择、完成勾选、数字和骨架 | `lib/ui/v2/motion/` |
| 周课表滑动切周 | `lib/features/calendar/calendar_week_pager.dart` |

表内的相对代码路径从 `apps/mobile` 开始。品牌标志、导航图标和空状态插画位于 `apps/mobile/assets`，使用 `flutter_svg` 加载。

## 当前实现的范围

主入口接入浅色主题和高对比主题。tokens 和主题代码还提供深色数值，但 App 入口没有接入 `darkTheme` 或主题切换设置，因此不能把深色模式列为已经交付的用户功能。

四个主页面保留各自状态和滚动位置。周课表使用横向分页；底部点击和任务状态选择取消大块灰色按压反馈。助手使用统一可拖动面板；当前不是从底部胶囊变形成面板的独立容器动画。

组件有可复用参数，页面也仍有局部布局数值。修改 tokens 不会自动更新全部局部样式；维护时要同时检查调用处，尤其是课表密集信息、表单和窄屏。

## 怎么维护

改颜色、字体或通用尺寸时，同时更新 JSON 和 Flutter 数值，检查兼容的 `campus_theme.dart` 与 Forui 主题。改某一页的布局时，先调整该页；确实重复的部分再提到共用组件，避免为“统一”把不同内容都包成同一种卡片。

变更后运行 `flutter analyze` 和相关测试，使用模拟器检查普通字号、360 dp 宽加 1.6 倍字号、减少动画、高对比及键盘展开。截图应来自当前 App，并标明版本和状态。这里的说明描述实现和维护方法，不代替一次新的运行验收。
