# 晴日 v2 · Flutter 参考实现

只依赖 Flutter SDK，没有第三方包。验证环境 Flutter 3.44 / Dart 3.12：
- `flutter analyze`：**No issues found**；
- `test/gallery_render_test.dart`：**2 项通过**（白天、夜间），渲染图在 `previews/`。

## 文件与它替换的现有代码

| 文件 | 内容 | 对应现有代码 |
|---|---|---|
| `lib/shiri_tokens.dart` | 颜色（浅色/深色）、品牌色、渐变（含按北京时间变化的天空）、8 组课程色 `CoursePalette.forTitle`、`KindStyle`（课程/活动/计划/考试/截止）、字体阶梯 `ShiriType`、间距、圆角、阴影、布局尺寸、动效（时长、曲线、弹簧），以及 `ThemeExtension` 和 `context.shiri` | 取代 `lib/ui/campus_theme.dart` 的 `CampusColors` / `CoursePalette`；`CoursePalette` 保留 `background/foreground/accent` 字段名，方便迁移 |
| `lib/shiri_theme.dart` | `shiriLightTheme()` / `shiriDarkTheme()`：显式构建的 ColorScheme 和各组件主题（按钮、输入框、芯片、弹层、卡片、回执提示、fade-through 页面切换） | 取代 `campusTheme()`。`forui_theme.dart` 改为从 `context.shiri` 取色 |
| `lib/motion/reduced_motion.dart` | `reduceMotion()`、`motionDuration()` 等 | 对应 `AppMotion.reduced` |
| `lib/motion/pressable.dart` | `Pressable`：按下缩放到 0.97 + 弹簧回弹 + 可选触感 | 新增，用于卡片和课表块 |
| `lib/motion/staggered_reveal.dart` | `StaggeredReveal`：列表交错进入，同一个 key 只播一次 | 取代 `TabEntrance` |
| `lib/motion/rolling_number.dart` | `RollingNumber`：逐位滚动的等宽数字 | 新增，用于倒计时和统计 |
| `lib/motion/now_pulse.dart` | `NowDot`：金色"现在"点，整分钟脉冲一次 | 新增 |
| `lib/motion/completion_check.dart` | `CompletionCheck(status: idle/pending/done)` + `StrikeThroughText` | 取代 `SuccessCheckmark`。划线由父级在服务端确认后触发 |
| `lib/motion/skeleton.dart` | `SkeletonScope` / `SkeletonBox` / `SkeletonLine`：共用一个闪光控制器 | 取代 `SkeletonLoader` |
| `lib/motion/spring_segmented.dart` | `SpringSegmented<T>`：弹簧指示块的分段控件 | 取代现有的分段切换 |
| `lib/widgets/sky_header.dart` | `SkyHeader` + `SunArcPainter`：时间天空、太阳/月亮弧、日出入场、可折叠 | 今日页头 |
| `lib/widgets/wave_edge.dart` | `WaveEdge`：图标同款两层波浪 | 新增 |
| `lib/widgets/glass_dock.dart` | `GlassSurface`、`GlassDock`、`AssistantPill`（滚动收起、长按说话、可用 Hero） | 取代主页面底部的输入栏 + 导航栏 |
| `lib/widgets/gap_slot_bar.dart` | `GapSlotBar`：空档虚线框 + 按占比的任务块 + 填充动画 | 今日"课前空档" |
| `lib/widgets/schedule_block.dart` | `ScheduleBlock`：按 `KindStyle` 绘制的课表块（带虚线、徽标、Hero） | `features/calendar/schedule_grid.dart` 的块 |
| `lib/widgets/dashed_border.dart` | `DashedRRectPainter` | 新增，供计划块和空档条共用 |
| `test/gallery_render_test.dart` | 渲染检查 + 预览导出 | import 路径要改成 `package:semester_os/ui/v2/...` |

## 接入建议
1. 复制到 `apps/mobile/lib/ui/v2/`，在 `MaterialApp` 里用 `theme: shiriLightTheme()`。
2. 先让 `campus_theme.dart` 的旧常量转发到新 tokens，保证编译通过，再逐页替换。
3. 预览渲染测试需要中文字体：`FontLoader('NotoSansSC')` 加载 `C:/Windows/Fonts/NotoSansSC-VF.ttf`，图标字体来自 Flutter SDK 缓存，写法见测试文件。

## 已知限制
- 深色主题已经实现，但没有逐页走查，列为第二阶段。
- `AssistantPill` 的"胶囊变面板"需要页面配合 `Hero` 或自定义路由，组件只提供 `heroTag`。
- `SkyHeader` 的日出入场每个进程只播一次（静态标记）；如果要求"每天第一次打开播放"，需要由页面记录日期。
- 低端机判断（`lowEnd`）要由 App 提供，例如根据设置项或帧耗时决定。
