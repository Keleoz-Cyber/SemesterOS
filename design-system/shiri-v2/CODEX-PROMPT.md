# 任务：拾日 App 界面「晴日 v2」大改版

你在仓库 `D:\study\Contest\AIC\SemesterOS` 中工作，Flutter 客户端位于 `apps/mobile`。

目标：按 `design-system/shiri-v2/` 的规范，把 App 全部界面从"单调、平铺、动效死板"改成「晴日」视觉语言——通透、有日光感、层级清楚、动效能看出前因后果——同时**不改变任何业务逻辑和数据语义**。

## 一、先读（按顺序）
1. `design-system/shiri-v2/README.md`：素材总览
2. `design-system/shiri-v2/DESIGN.md`：视觉、布局、动效规范，是本任务的主要依据
3. `design-system/shiri-v2/tokens/tokens.json`：所有数值
4. `design-system/shiri-v2/screens/*.png`：目标效果图。`prototype/index.html` 可以在 Chrome 里交互查看，精确尺寸看 `prototype/styles.css`
5. `design-system/shiri-v2/flutter/`：已验证的 Flutter 参考实现（tokens、主题、动效原语、关键组件）。它的 README 写了每个文件对应哪段现有代码
6. `design-system/shiri-v2/assets/`：SVG 插画与图标，兼容 flutter_svg
7. `design-system/shiri/MASTER.md`：**现行的产品与无障碍规则，继续有效**

各文件冲突时的优先级：MASTER（业务、数据、无障碍）> tokens.json > DESIGN.md > prototype > screens。

## 二、边界（必须遵守）
- **只改展示层**：widgets、主题、动效、资源，以及为此必需的轻量 UI 状态。不改以下内容：
  - API、数据库；
  - Riverpod 控制器和状态；
  - go_router 路由语义；
  - 确认、撤销、回执、版本冲突的流程；
  - 学校导入和 WebView 逻辑；
  - 提醒逻辑。
- **文案**：保留现有的功能性文案，可以删掉冗余文字。不新增口号、励志句、虚构数据或百分比。
- **继续遵守 MASTER 的约定**：
  - 周课表的"现在"标记放在左侧时间轴；
  - 未知时间不补造；
  - 触控目标 48dp；
  - 系统字号放大到 1.6 倍时不溢出；
  - 颜色不能是唯一的信息来源；
  - 开启减少动画时直接显示终态；
  - 任务完成要等服务端确认后再划线。
- **依赖**：只允许新增 `flutter_svg`（`vector_graphics` 可选），不引入其他动画库。
- **匿名**：学校选择页因功能需要可以出现学校名称，其余界面和插画不出现学校名称或校徽。

## 三、实施步骤

### 阶段 0：准备
- 新建分支 `ui-v2`。先跑一次 `flutter analyze` 和 `flutter test`，记录基线。
- 通读 `apps/mobile/lib/ui/`（`campus_theme.dart`、`forui_theme.dart`、`app_controls.dart`、`motion.dart`），以及 `lib/features/` 各页面的结构。

### 阶段 1：基础层
1. 把 `design-system/shiri-v2/flutter/lib` 复制到 `apps/mobile/lib/ui/v2/` 并调整 import，`MaterialApp` 改用 `shiriLightTheme()`。
2. `campus_theme.dart` 里旧的颜色和 `CoursePalette` 先转发到新 tokens，保证能编译；`ShiriForuiTheme` 改为从 `context.shiri` 取色。
3. 按 DESIGN §7 升级共用控件：
   - `app_controls.dart`：AppButton、AppField、AppTile、AppFilterChip、AppDialog 等；
   - `motion.dart`：用新的动效原语替换 TabEntrance、SkeletonLoader、SuccessCheckmark。旧 API 名保留为适配层，避免大面积改调用点。
4. 加入 `flutter_svg`；把 `assets/{illustrations,icons,brand,patterns}` 复制到 `apps/mobile/assets/`，并在 pubspec 里声明。

### 阶段 2：外壳
- **底部**：主壳（`lib/features/timetable/shell_page.dart` 等）改为 `GlassDock` + `AssistantPill`，去掉主页面上那条整宽输入栏。
  - 胶囊随滚动方向收起或展开。
  - 长按麦克风沿用现有的按住录音逻辑，hold_voice 相关测试必须继续通过。
  - 轻点胶囊打开现有助手面板，用容器变换过渡。
- **页面切换**：用 fade-through；主页面内容在底部渐隐；各页签的滚动位置和状态要保留。

### 阶段 3：逐页改版（每完成一页就截图自检）
1. **今日**（`features/home/today_dashboard.dart`、`today_view_enhanced.dart`），从上到下：
   - 可折叠的 `SkyHeader`；
   - 下一节卡；
   - 空档卡：`GapSlotBar`，"安排这项"就地展开预览 → 保存 → 填充动画，仍然调用现有的预览和保存逻辑；
   - 今日时间线；
   - 待办（`CompletionCheck`）；
   - 近期考试横向滑动；
   - 本周条形。
2. **日程**（`features/calendar/calendar_panel.dart`、`schedule_grid.dart`）：
   - 顶部固定栏 + `SpringSegmented`；
   - 周课表：`ScheduleBlock`（按 `KindStyle`）、今天这一列淡蓝底、午休和晚饭压缩成斜纹带、左侧"现在"书签；
   - 列表视图按天分组；
   - 课表块用容器变换进入课程详情。
3. **任务**（`features/items/*`、`planning/plan_list.dart`）：
   - 统计卡（`RollingNumber`）、`SpringSegmented`；
   - 按紧迫程度分组的任务行；
   - 学习安排卡；
   - 右滑完成，复用现有的完成确认流程。
4. **学期**（`features/semester/semester_page.dart`、`centers/semester_timeline.dart`）：地平线进度、周次弹簧选择、选中周按类别排列内容、学期资料宫格。
5. **助手**（`features/agent/*`）：
   - 面板、气泡；
   - 解析卡、修改预览、空档结果、回执换新样式；
   - 打开时定位到最新消息；流式输出只追加文字。
6. **详情与表单**（item_detail、event_form、item_form、exam_pages、changes 等）：课程色页头、分组卡片、底部弹层、输入框和时间滚轮的新样式。
7. **登录、注册、资料、学期创建、导入核对**：品牌标志 + 波浪 + 引导插画。导入核对页保持现有的步骤和语义。
8. **所有空状态、加载、错误**：插画 + 一句事实 + 一个动作；加载用骨架屏。

### 阶段 4：动效与打磨
- 对照 DESIGN §6.2 的 12 个模式逐条落实。打开"减少动画"逐页检查；低端机走 `lowEnd` 不透明回退。
- 性能：
  - 动画区域外包 `RepaintBoundary`；
  - 列表行不加阴影；
  - `BackdropFilter` 只用在导航坞和胶囊上。

## 四、验收
- **视觉**：
  - 用现有 `test/ui_polish_test.dart` 的 mount/capture 截图流程，设置环境变量 `UI_PREVIEW_FONT=C:/Windows/Fonts/NotoSansSC-VF.ttf`；
  - 为今日、日程、任务、学期、助手、详情、空状态各导出一张 390×844 截图，逐张对照 `design-system/shiri-v2/screens/` 的布局和层级；
  - 再导出 360dp 宽 + 1.6 倍字号的版本，确认没有溢出。
- **质量**：
  - `flutter analyze` 无问题；
  - `flutter test` 全部通过。测试因为文案或结构变化而失败时，更新测试去反映新界面，不删断言来过关；
  - 业务行为相关的测试（确认、撤销、回执、冲突、按住说话、导入）必须原样通过。
- **行为**：确认、撤销、回执、版本冲突、未知时间的语义、账号隔离，都与改版前一致。
- **交付**：在 `docs/` 新增《UI v2 改版说明》，写清改了哪些页面和共用组件、对照截图的路径、没做完的部分及原因、已知风险。

## 五、工作方式
- 小步提交：每个阶段或每个页面一个提交，提交信息写清改了什么。
- 规范和业务约束冲突时，以 MASTER 为准，并在改版说明里记录取舍。
- 规范没覆盖到的页面，沿用最接近的页面模式，不另创风格。
- 会改变操作步骤数量之类的产品行为变动，先列出来，不要擅自实现。
