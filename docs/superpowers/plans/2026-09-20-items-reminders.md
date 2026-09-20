# 事项记录与提醒实施计划

> **For agentic workers:** Use executing-plans to implement this plan task-by-task. Preserve the user's existing Android checkout and devtools_options.yaml.

**Goal:** 作业、考试、个人任务从录入确认到列表、详情、修改、完成及本机提醒形成可运行闭环；文字解析只在用户确认后保存。

**Architecture:** 在现有FastAPI/PostgreSQL中增加按用户和学期隔离的事项、提醒、修改记录；Flutter共用领域接口完成手工与解析候选确认。通知通过平台适配器串行校正，与账号会话绑定；没有模型配置时明确返回不可用并保留手工入口。

**Tech Stack:** Flutter、FastAPI、SQLAlchemy、Alembic、PostgreSQL、Android本机通知。

## 1. 事项与提醒合同
- [x] 新增`services/api/tests/test_items.py`，验证日期精度/未知耗时、跨账号访问、旧版本拒绝、幂等保存、过期及重复提醒、相对重算/绝对提醒核对、完成取消。
- [x] 运行`services/api/.venv/Scripts/python.exe -m pytest services/api/tests/test_items.py`，先观察缺失接口失败。
- [x] 新增`app/item_schemas.py`、`app/items.py`、`app/reminder_rules.py`，扩展`models.py`和迁移`0004_items_reminders.py`。锁学期后检查事项版本；修改历史、修订号和提醒更新同一事务。
- [x] 用独立PostgreSQL测试schema通过新旧测试，业务库只执行新增迁移。

## 2. Flutter事项闭环
- [x] 新增`features/items/`表单、详情、列表及状态管理；使用原有`SemesterApi`会话检查和本地缓存机制。
- [x] 快速记录入口增加作业/考试/个人任务，关联已有课程；日期/具体时间/周次/待确认独立保存。未知耗时保留null；关键时间核对直接展示。
- [x] 今日页显示近期事项，计划入口变为任务列表；支持编辑、明确完成、取消与来源查看。
- [x] 组件测试验证真实表单提交、日期精度、大字体、未知耗时和编辑版本；状态测试验证旧账号迟到结果不写缓存。

## 3. 本机提醒
- [x] 通知适配器实现权限查询/按需申请、稳定标识、替换和撤销；开机由平台插件恢复，App恢复前台后校正。
- [x] 保存事项时一并确认提醒；详情支持独立增加、修改、停用多条提醒。显示触发时刻和系统权限/最近同步状态。
- [x] 测试确认取消或修改不会留下旧通知；拒绝权限仍保留规则。退出账号撤销本机提醒和清理缓存。
- [x] Android模拟器用合成QA事项验证通知投递、点击及撤销，不修改用户真实事项。

## 4. 文字解析与交付
- [x] 通过可配置服务端适配器调用真实文本模型；schema和课程ID白名单校验，保留原文/证据，候选不写正式事项。未配置时明确不可用，禁止假模型成功。
- [x] 原文输入→处理中阶段文字→核心字段确认/更多设置→同一事项保存接口；图片、语音留待后续批次。
- [x] 独立审查、Flutter/后端/脚本回归、静态分析、Android构建及可见UI验证。
- [x] 更新验证记录和调试包，提交并推送现有开发分支。真实模型所需配置若缺失，单独记录阻塞，其他功能照常交付。
