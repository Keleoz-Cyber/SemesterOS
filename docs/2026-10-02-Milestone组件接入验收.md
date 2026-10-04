# Milestone 组件接入验收

日期：2026-10-02。产品：拾日。目标版本：0.1.0+7。

当日验证状态：实际组件接入、相关回归、模拟器主要操作和 Release 打包完成；新包已覆盖安装到模拟器，原数据保留。下面的矩阵按真实页面和调用点记录，文件数量、演示页面和静态分析通过都不能单独证明流程完成。

## 实际接入矩阵

代码路径以 `apps/mobile/lib/` 为起点。

| 能力 | 真实页面与调用点 | 用户行为与数据范围 |
| --- | --- | --- |
| 今日双视图 | `features/home/today_dashboard.dart` → `today_view_enhanced.dart` 的 `TodayViewSwitch` | 首页切换“日程 / 待办”。未手动选择时按实际安排决定默认视图；偏好按账号与学期保存在本机。 |
| 时间轴 | `TodayViewSwitch` → `ui/time_river.dart` → 既有 `TimeTrack` | 查看实际课程和日程；未知结束时间保留为时点。已经结束的当天安排可折叠查看，避免孤立的“现在”标记占据空白。 |
| 截止紧迫度 | `ui/time_urgency.dart`、`features/items/item_widgets.dart`、首页优先事项 | 仅真实截止产生倒计时和紧迫度；开始时间、候选日期及未确认的日期不能被当成截止。沿用蓝绿主题和既有警示色。 |
| 有限强调动画 | 首页 `UrgentItemCard` → `ui/breathing_card.dart` | 仅已知截止、距离截止不足两小时的优先事项短暂强调。两次呼吸后停止；后台、隐藏页面和系统减少动画时停止。普通任务列表默认不启动。 |
| 首页待办预览 | `TodayViewSwitch` → `ItemCard`；`features/timetable/shell_page.dart` 提供回调 | 预览最多八项，更多事项进入完整任务清单。可以点击详情、双击编辑或使用可见编辑按钮；拖动顺序只改变本机展示。 |
| 可选周热力图 | 首页内容设置 → `features/home/week_heatmap.dart` → `ui/week_heatmap.dart` | 开启后读取完整七天安排，按实际小时区间显示。仅有日期的记录独立计数；读取失败不能显示成空闲。点日期进入对应日程。 |
| 可选学期进度 | 首页内容设置 → `features/home/semester_progress.dart` | 使用用户设置的首周日期和总周数，展示学期日历进度；不推测考试节点或学习完成率。 |
| 可选时间统计 | 首页内容设置 → `features/home/time_stats_card.dart` | 统计已记录日程的已知区间，重叠时段计一次；未知结束不补造时长。不代表实际学习时长或效率。 |
| 可选呼吸练习 | 首页内容设置 → `ui/breathing_exercise_card.dart` | 默认关闭；用户主动开启并开始练习后才运行。不会另建主导航入口。 |
| 任务快捷操作与排序 | `features/items/items_view.dart`、`items/item_actions.dart`、Shell 的 `editTask` | 长按提供详情、编辑、进度及完成/恢复操作；双击编辑。排序菜单可选自动或拖动，保留可见手柄和移动操作。状态改变仍使用原业务预览和确认。 |
| 统一时间选择 | `ui/app_time_picker.dart`，课程节次、日程、任务、计划、提醒及采集表单的原时间入口 | 同一选择框支持滑动、逐分钟调整和 24 小时数字输入；15 分钟吸附可关闭。返回或取消不写入表单结果。 |
| 手势层 | `ui/gesture_layer.dart` → 时间选择框内的 `MagneticTimePicker` | 手势限于明确的时间操作区；不覆盖整页或劫持日程翻页、列表滚动。点击与数字输入继续可用。 |
| 长任务列表按视口构建 | Shell 的 `CustomScrollView` → `ItemsView(sliver: true)` → `VirtualizedSliverList` / `SliverReorderableList` | 主任务列表不靠嵌套的 `shrinkWrap` 列表一次构建全部卡片；滚动位置与页面切换仍由原 Shell 管理。 |
| 对话与历史列表 | `features/agent/agent_page.dart` → `VirtualizedListView` / `LazyLoadList` | 对话按视口构建；历史沿用现有后端分页与重试。查看旧消息时不强制跳回底部。 |
| 私有图片来源 | `features/media/source_view.dart` → `OptimizedImage.memory`、骨架屏、重试与空状态 | 沿用鉴权接口获取图片；账号、请求代次和来源版本改变时隔离旧结果。未授权图片不会改成公开 URL。 |
| 有界缓存 | `ItemsView` → `MemoryCache` 与 `BuildCache` | 任务投影和局部头部复用受账号、学期、数据版本、输入变化和期限限制；不会跨账号或无限保留旧视图。 |
| 防重复提交 | `ui/app_controls.dart` → `DebouncedButton`；详情操作底栏 | 保存动作在异步操作完成前防止重复提交。导航或打开窗口仍应可用，不因旧请求阻塞新页面。 |
| 基础无障碍 | `ui/accessibility.dart` → 公用按钮、开关、卡片、底部导航及学期进度 | 可点击语义与原操作一致，提供键盘焦点/激活和触摸目标；保留卡片内的独立操作。不是完整合规认证。 |
| 高对比度与减少动画 | `app/semester_app.dart`、`ui/forui_theme.dart`、`campus_theme.dart`、`motion.dart` | 系统高对比度进入应用主题；减少动画进入切换、面板、加载和重点提示。隐藏页面不持续运行动效。 |
| 情境反馈与帮助 | 日程、任务、学校搜索、原图、详情、统计等页面；账户菜单 → `/help` | 按情况使用空、加载、错误或成功反馈，保留实际重试/导入操作。使用说明是主动打开的单页，连接现有课程、通知和计划流程。 |

旧的 `TodayDashboardEnhanced`、`WeekViewEnhanced` 等增强包装作为兼容适配器复用真实实现。展示用的 `milestone_showcase.dart`、`milestone2_demo.dart` 不作为正式功能验收入口。未需要的演示动效和工具包装不为增加组件数量强行插入页面。

## 简要使用方式

1. 在“今日”切换“日程 / 待办”；页面设置中可开启本周热力图、学期进度、时间统计或呼吸练习，也可关闭和调整顺序。
2. 在完整任务清单中，点击看详情、双击编辑、长按看快捷操作；排序菜单提供自动排序或拖动排序。
3. 从原有表单点开时间。滑动、分钟加减和数字输入在同一个窗口；取消后原值保持不变。
4. 在助手里查看当前对话或历史。图片与语音继续沿用原采集流程，没有增加新的独立录音步骤。
5. 从账户菜单打开“使用说明”。高对比度、减少动画等系统设置不需要另建一套应用设置。

## 业务约束

- 缺少开始、结束、地点或具体日期的事项保持原信息；不为了图表或动画生成确定时间。日期截止须沿用用户已确认的语义。
- 任务编辑先读取当前记录，再走原保存流程。完成、取消或恢复通过业务预览；关联学习安排、锁定安排、版本冲突和撤销仍按原流程处理。
- 首页顺序与视图偏好只影响显示，不修改课程、日程日期、任务优先级或服务端计划。
- 账号、学期、数据版本与请求代次仍是结果和缓存的边界。离线缓存有标识；网络失败不能被当成没有安排。
- 本轮以移动端组件接入为范围；后端未改动时不重复部署。APK 保持 0.1.0+7 和原签名，最终只保留一个正式测试包。

## 验证记录

本轮全量 Flutter 回归 **435 项通过**，静态分析零问题。最后原生体验发现空状态操作误导，只将已完成／已取消空列表的“添加事项”隐藏；随后相关 7 项检查与改动文件分析通过，未再次扩大全量检查。

| 检查 | 最终结果 | 原始证据 |
| --- | --- | --- |
| Flutter 静态分析 | 零问题；末次小调整的相关文件也零问题 | `output/milestone-integration-20261002/analysis.log`、`empty-state-final-analysis.log` |
| 针对性行为检查 | 首页、时间选择、语义、缓存、真实任务列表及业务确认通过；末次空状态 7 项通过 | `focused-tests.log`、`targeted-infrastructure-final.log`、`empty-state-final-tests.log` |
| 全量 Flutter 回归 | 435 项通过 | `output/milestone-integration-20261002/full-tests-final.log` |
| 模拟器基本操作 | 已走过视图切换、偏好持久化、热力图日期跳转、任务菜单／完成／撤销／恢复、拖动排序、时间取消和帮助入口 | `output/milestone-integration-20261002/native-checkpoints.json`；截图／XML 在 `output/verification/20261002-milestone-integration/` |
| 离线与大字号 | 飞行模式仍显示缓存课表和本机顺序；恢复网络后读取正常。1.6 倍字号、关闭动画、高文字对比度下主要页面未见溢出；系统设置已恢复 | `final-offline-cache.xml`、`final-online-recovered.xml`、`final-large-task-list.png`、`emulator-settings-restored.json` |
| 当前构建帧耗时 | 模拟器 Profile 模式 217 帧；构建 P50/P90/P99 = 0.579/1.602/16.198 ms，绘制 = 13.547/17.070/19.262 ms。构建 1 帧、绘制 36 帧超过 16.67 ms | `frames-final.json`、`frame-actions.json`、`profile-source-snapshot.json`；未换算成操作系统丢帧或稳定 FPS |
| 长列表按需构建 | 真正任务视口载入 1000 项，首屏和滚动后同时构建的卡片均少于 25 项；双击与原保存确认路径可用 | `test/milestone_live_flow_test.dart` 及相关检查日志；这是构建行为证据，不是内存减少百分比 |
| 最终 APK | 0.1.0+7，普通 Release，原证书，三架构与正式 URL，v2/v3 与 16KB ZIP 对齐通过；`output/apk` 仅一个 APK，覆盖安装到 emulator-5554 | `output/milestone-integration-20261002/release/apk-metadata.json` 和签名／对齐／构建日志 |
| 正式服务 | 健康检查 ok，0.1.0、PostgreSQL。本轮不改后端业务，不重复部署 | `output/milestone-integration-20261002/server-health.json` |

安装包：[拾日-0.1.0-手机测试.apk](../output/apk/拾日-0.1.0-手机测试.apk)。组件接入初版 SHA-256 为 `8cb40305eba952a8f76b31f3bcfe0891b6ca00f46ceef32e85d4f45a0c20143f`；当前文件已由下述资料页修正版替换。

帧采样与主要原生检查使用最后一处空状态按钮调整前的 QA Profile 构建；该差异仅涉及空筛选列表，采样的非空列表不走这个分支。正式 Release 包包含这处调整，相关显示行为以末次 7 项检查验证。原生过程仅在独立演示账号写入，不修改正常包的数据。首次 Release 因 QA 遗留的插件注册生成物失败，重新生成注册后构建成功，未修改业务源码来绕过失败。

不沿用旧稿的固定帧率、首屏提升比例、内存下降比例、操作效率比例或满意度预测。列表按需构建的检查不能替代实机性能测量；模拟器帧耗时也不能证明所有手机达到固定帧率。基础语义和主题接入不等于完整 WCAG 审计。

真实语音识别准确率、实际教务登录与厂商后台提醒仍需对应环境验证；既有验收记录不能代替本次新构建的流程检查。

## 历史报告处理

原来的九份 Milestone 报告/指南已完整备份到 `output/milestone-integration-20261002/docs-before/`，原稿相对目录与内容保留，`manifest.json` 记录 SHA-256。原位置仅保留历史说明并指向本文，避免重复旧结论被当作本次交付证据。

本文件保留 2026-10-02 阶段验证；后续源码与安装包差异见 [README](../README.md)。


## 资料页选项修正（2026-10-02）

培养层次仅保留“本科／研究生”，空资料两者都不选，不再把“未填写”当成身份选项；已选项可再次点击取消。用实际 Forui 选择按钮取代必选页面标签，避免空值被显示为本科。其他资料字段没有类似占位选项或自动补值，后端资料结构未变。

本轮只运行资料相关的 20 项既有检查，均通过；改动文件静态分析零问题。新版普通 Release 已覆盖安装到 emulator-5554，原账户、学期和课表保留；只读打开真实资料页确认两个选项均未选中且没有“未填写”。证据：`output/profile-choice-fix-20261002/tests.log`、`native/updated-profile.png`、`native-verification.json`。

当前唯一 APK 保持 0.1.0+7、原证书、三架构、正式服务器地址。资料选项修正版 SHA-256：`c7429e0fe1d07880b402fae6595c45ab4b93f9e9038fa7c18749db4de7a56c60`（随后由通知权限修正版替换）。签名、16KB 对齐和安装记录见 `output/profile-choice-fix-20261002/release/apk-metadata.json`。


## 通知权限开启修正（2026-10-02）

旧 Release 资源表不含 `drawable/ic_notification`。通知插件初始化按字符串查找该图标后返回 `invalid_icon`，而客户端缓存了失败 Future，因此“开启”没走到权限步骤。实际复现中，Android 已授权但页面误显示未允许并提示读取失败。

保留动态通知图标、允许初始化失败后重试；提醒设置的“开启／设置”直接打开 Android 的拾日通知设置，不等待云端同步。返回后更新授权状态，新增授权会同步已保存的本机提醒；未知状态不再显示为未允许，旧读取错误成功后清除。

36 项相关检查通过，改动文件分析零问题。编译后的新 Release 资源表已强制校验图标存在，真实覆盖安装到 emulator-5554 后验证：状态显示已允许，按钮打开 Android 通知设置，返回无读取／同步错误；原账号、学期、课表和系统授权保留。本轮不宣称完成新的真机/OEM后台通知投递测试。

最新唯一 APK 仍为 0.1.0+7、原证书、三架构和正式服务器 URL；SHA-256：`aca9fb35c52b52970b740c8570cc36aec631738d1f3395f7c04c1312b7ff03d7`。根因资源表、检查、原生截图与打包记录在 `output/notification-permission-fix-20261002/`，最终记录为 `verification-summary.json` 和 `release/apk-metadata.json`。
