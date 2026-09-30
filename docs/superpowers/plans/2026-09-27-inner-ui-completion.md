# Internal UI Completion Plan

> **For agentic workers:** Use dispatching-parallel-agents for disjoint feature pages; root owns shared widgets, onboarding/import/capture and integrated validation. No per-page approval gate; user already authorized full UI redesign.

**Goal:** 补齐主导航以下的全部用户界面，真实覆盖录入、详情、编辑、提醒、导入、规划、账号与设置，而不把主题换色当完整重做。

**Architecture:** 沿用明快蓝绿方向；详情、编辑、文稿、方案、设置采用不同内容结构。共享RecordHeading/EditorSection/RecordFact/WorkflowHeader/ActionFooter/DocumentPanel仅提供结构语法，不强制所有页套相同大卡。业务controller/API与数据语义保持。

**Tech Stack:** Flutter Material 3及现有依赖；现有UI/移动端技能与原反馈继续生效。

## 页面范围与责任

- [x] 任务与日程：ItemDetailPage、ItemFormPage、ReminderEditor、EventFormPage、EventDetailPage。身份/时间/提醒/进度/来源分层，编辑表单按逻辑分组，保留校验与未知日期。
- [x] 课程与考试：CourseHubPage、ExamCenterPage、ReviewSetupPage、ExamReschedulePage、ExamChangePreviewPage、ChangesPage、ChangePreviewPage。事实、影响、用户决策清楚分开，正式学校安排不能伪装可任意拖动。
- [x] 规划与设置：AvailabilityPage、SchedulePage、ProposalPage、ProgressPage、PlanListPage、TagManagementPage、风险详情/计划变更确认。时段与任务图形化可读，所有确认/锁定/撤销检查保持。
- [x] 账号与建立学期：AuthPage的登录/注册/恢复状态、SemesterPage、管理学期页。形成进入产品的连续流程，不增加新鉴权条件。
- [x] 课表导入：SchoolPickerPage、ImportPage、ImportPreview、ManualPage。选择/登录/核对流程；学校WebView内容由学校提供，不覆盖或绘制假的登录表单。
- [x] 输入与原文：CapturePage、MediaCapturePage、SourceViewPage、OperationPage，图片/语音/识别/错误/原文/确认均有对应布局；不修改识别或提交协议。
- [x] 主界面关联：所有详情入口与返回路径保持；Agent/统计已有设计作为基线，检查与内部页一致。
- [x] 逐页截图，普通和大字号，关键流程交互与错误恢复；没有渲染证据的页面不标为视觉验证完成。
- [x] Flutter全量/analyze、统一构建与逐页记录。原生复验受此前安装限制影响，仍如实记录，不以测试数量代替设计完成度。

## 设计变化标准

每页必须至少说明信息顺序、主要动作和一个独有内容表现形式。详情使用记录标题与时间/地点事实；编辑使用明确分组、可见标签与就地校验；来源使用文稿阅读；方案使用旧/新对比与影响；设置使用选项/状态与统一保存区。禁止仅在旧表单上添加一段介绍或另一个大横幅。

验收截图与清单放output/verification/inner-ui；上轮主要页面截图不计作本轮内部页覆盖。语音真人实测仍按用户要求暂缓。

交付证据见 docs/30-内部界面补齐与逐页覆盖.md。页面框架/组件实施与覆盖记录完成，原生WebView/新APK设备复验和真人语音仍明确未验证，不计入已完成的组件验证。
