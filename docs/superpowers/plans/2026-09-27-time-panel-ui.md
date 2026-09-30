# Time Panel UI Implementation Plan

> **For agentic workers:** Use executing-plans for integration and dispatching-parallel-agents for isolated page implementation. Each worker edits only its declared files. User has chosen the design; no per-page approval gate.

**Goal:** 将拾日实际Flutter界面重做为明快蓝绿时间面板，保持完整功能与真实状态。

**Architecture:** 共用主题/动效/导航由根代理拥有；今日、日程、计划学期分开修改展示层，业务controller与API保持不变；根代理负责助手、统计、集成与最终视觉QA。

**Tech Stack:** Flutter Material 3，现有calendar_view、fl_chart、GoRouter；不引入网页UI框架。

## 任务与文件责任

- [x] 安装、核对三个用户指定skill，读取原生规则、搜索产品/Flutter指南，记录来源和边界。
- [x] 复核用户原始反馈与当前UI，用户确认明快时间面板方向，保存设计规范。
- [x] 共用层：`ui/campus_theme.dart`、`ui/campus_widgets.dart`、`ui/app_navigation.dart`、`ui/motion.dart`、`features/timetable/shell_page.dart`，重建排版、色彩、导航和转场，保留可访问性与页面状态。
- [x] 今日：`features/home/today_dashboard.dart`，时间轨道、下一项重点、截止/建议模块以及加载/错误/自定义模块。
- [x] 日程：`features/calendar/calendar_panel.dart`、`schedule_grid.dart`，网格与按日视图重新构图，保持日期/周次/冲突/完整文字语义。
- [x] 计划与学期：`features/items/items_view.dart`、`features/planning/plan_list.dart`、`features/centers/semester_timeline.dart`，内容分层、任务密度、周带时间轴、次级入口。
- [x] 助手与统计：`features/agent/agent_page.dart`、`change_confirmation.dart`、`features/insights/insights_page.dart`，共用视觉与紧凑确认、图表层级、动效与状态。
- [x] 集成验证：Flutter全量和analyze；新增减少动画/适配检查；截图普通、大字号、小屏与横屏；逐页视觉复核与问题修正。
- [x] 输出统一QA候选包与变更记录，保留前一个候选；记录安装/原生复验的实际状态，不把构建通过当设备通过。

## 验证执行

页面worker不并发跑Flutter测试，集中由根代理串行执行，避免共享构建锁及golden字体状态冲突。定向验证发现问题先修再扩到全量。UI_PREVIEW_DIR指向output/verification/time-panel-ui；字体使用本机msyh.ttc，icons使用Flutter缓存字体。每轮截图必须真实渲染，不制作与代码无关的假效果图。

验收基准：现有161项Flutter回归、教务JS3项、后端204项已通过；本轮不改业务API，只针对受影响客户端做全量及视觉验证。

实际交付记录见 docs/29-UI重设计与技能应用.md。工程与组件/视觉验证完成，APK已备妥；设备安装后的原生复验仍未完成，不属于已勾选的构建检查。
