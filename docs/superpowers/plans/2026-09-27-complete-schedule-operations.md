# 日程操作与标签完整交付计划

> **For agentic workers:** Use subagent-driven-development for independent implementation/review and executing-plans for integrated steps. Continue through the authorized local endpoint; no per-task user acceptance gate.

**Goal:** 完成助手中的课程/考试通知、分组多事项录入、可核验撤销和标签管理，再统一交付验收。用户已明确要求“全做好再给我验收”。

**Architecture:** 复用现有业务校验，提取不自行提交事务的命令函数。AgentRun保存预览和回执，所有写入在最终确认事务中执行；批量按用户选择的分组原子保存，现实变更与个人计划仍分开确认。标签保留稳定ID和别名，重命名/合并同步历史关联与统计。

**Tech Stack:** Flutter/Riverpod/GoRouter、FastAPI/Pydantic/SQLAlchemy/PostgreSQL、现有LangGraph及OR-Tools；沿用已锁定依赖。

## 交付约束

- 不改产品版本、不部署云端、不制作公开发布包；保留之前未提交的全部工作及用户的`devtools_options.yaml`。
- 不再逐个小功能交给用户验收。语音实测由用户明确暂缓；缺实体设备时不声称真机通过。
- 调课必须绑定明确课次和通知来源；缺日期/时段不猜。考试复习截止是否随改期调整由用户确认。
- 批量保存不能部分成功后假称全部成功；重复确认返回同一结果；后续改动或依赖冲突时不能强行撤销。
- 验收以“收到通知→核对→保存→提醒/影响→个人重排→撤销→统计一致”为主线。

## Task 1 课程与考试业务工具

Files: 新增`services/api/app/agent_education.py`；修改`changes.py`、`exam_planning.py`、`agent_tools.py`、`agent_runtime.py`；新增`tests/test_agent_education.py`。

- [x] 先补课程移动、停课、暂定考试新增、考试改期/复习截止依赖的失败用例。
- [x] 将旧路由的业务写入提取为命令，旧HTTP包装继续提交，新Agent调用不提交：
  课程使用 `apply_change_command`，考试使用 `apply_exam_command`。
  命令须保留归属、版本、来源、固定冲突确认及提醒依赖校验；事务由调用方提交。
- [x] 增加`query_course_occurrences(course_id, from_date, to_date)`、`prepare_course_change`、`prepare_exam_change`工具；考试新增使用经过校验的`prepare_item(kind='exam')`。课次查询返回真实课次ID及原时间，写工具只接收已查询且消歧的目标。
- [x] 预览返回旧/新时间、来源与冲突影响；默认不修改个人计划，也不擅自同步复习截止。
- [x] 验证：准备前后学期版本不变；确认后仅对应课次/考试改变；重复确认幂等，来源过期和他人ID被拒绝。

## Task 2 多事项分组预览与原子保存

Files: 新增`agent_batches.py`、`tests/test_agent_batches.py`；修改`agent_tools.py`、`agent_api.py`、`agent_runtime.py`。

- [x] 工具契约：
  ```python
  class BatchGroup(Input):
      title: str
      operations: list[BatchOperation]
  class BatchRequest(Input):
      groups: list[BatchGroup]
  ```
  限定组数和总操作数（最多8项），不允许嵌套批量、规划或撤销；组内目标不得互相覆盖。
- [x] `prepare_batch`通过既有单项准备函数生成子预览，来源版本一致；每组显示将添加/修改什么及缺项，不将点名给别人的工作分配给用户。
- [x] `Decision`接受所选分组ID与明确的固定冲突确认。未选组不执行，重复请求若更改分组选择则返回幂等冲突。
- [x] 在同一事务中执行所选组；开始时核对原学期版本和对象版本，内部修订号推进仅由服务器处理。需要查看组合作用时用可回滚的模拟事务计算影响，不暴露模拟记录为已保存事实。
- [x] 用故障注入验证第2项失败时第1项也不落库；验证只选一组、固定冲突组合、同一来源、多标签和重复确认。

## Task 3 统一撤销与操作回执

Files: 新增`agent_undo.py`、`tests/test_agent_undo.py`；修改`agent_api.py`、`agent_tools.py`、`agent_runtime.py`。

- [x] 在应用事务中保存可撤销业务快照及应用后的版本，内部快照不发送给模型。保留业务审计，新增事项撤销采用取消而非删除来源历史。
- [x] 撤销也生成独立AgentRun预览，统一走`decision`确认，不另开不受保护的应用入口：
  ```text
  POST /agent/runs/{id}/request-undo → needs_confirmation
  list_recent_actions → 当前账号学期内可定位的操作
  prepare_undo(run_id) → 撤销预览
  ```
- [x] 检查受影响对象的后续版本及新增依赖；后续编辑、进度、关联计划等不能被悄悄覆盖。撤销个人重排只还原该轮个人计划，保留已确认的会议/课程事实。
- [x] 撤销后递增当前版本、生成回执及提醒更新；重复确认不再撤销一次。不支持的历史旧回执明确说明可手工修改。
- [x] 测试新增/修改/提醒/批量/课程/考试/计划、重复撤销、他人回执及后续修改冲突。

## Task 4 Flutter统一结果与后续操作

Files: `features/agent/{agent_page,agent_controller}.dart`及新增结果卡文件；相关`items_controller.dart`；`test/agent_*_test.dart`。

- [x] 课程和考试的预览显示原课次/考试、变化日期、范围、正式/暂定、复习依赖和固定冲突确认。
- [x] 批量按组展示，勾选组后一次确认；不把工具内部步骤逐个弹窗。提交中锁定选择，失败保留待核对内容。
- [x] 已保存结果提供统一“撤销这次操作”，打开撤销预览，结果保留原始回执与范围。
- [x] 用户可在同一面板补充“周四不行”或改分组内容；移除来源、换账号/学期、页面关闭等仍守住现有隔离。
- [x] 保存/撤销刷新课程、事项、计划、提醒和统计；检查大字号、键盘、空结果和失败恢复。

## Task 5 标签管理与历史一致性

Files: 新增`services/api/app/taxonomy.py`及迁移`0012_tag_aliases.py`、`tests/test_taxonomy.py`；修改`models.py`、`event_store.py`、`insights.py`。Flutter新增`features/tags/tag_management_page.dart`及测试，由统计/学期次级入口进入。

- [x] 标签稳定ID不变；新增用户范围别名与合并映射，保留用户命名优先。查询、录入和统计都解析到同一规范标签。
- [x] 重命名/合并先返回受影响事项、学期和版本摘要，用户一次确认后执行；重名进入合并流程，不创建两个同义标签。
- [x] 合并把关联映射到目标ID并去重，保留别名防止AI再次创建旧名；历史记录、计划和实际进度按当前分类一致汇总，跨用户不可引用。
- [x] 标签变动使相关学期统计失效，不凭标签修改日程时间、优先级或任务完成量。
- [x] 测试重命名ID稳定、同义名录入、合并前后总时长一致、OR标签去重、旧筛选ID兼容、旧预览失效、重复确认和并发校验。

## Task 6 最终整体验证

- [x] PostgreSQL业务回归、Flutter全套、教务JS及静态分析；迁移从现有head到新head并检查旧数据。
- [x] 真实模型覆盖一条混合通知、补充更改、课程调课、考试改期、选择部分组、撤销、标签别名与统计，保留结构化证据，不保留真实学生消息或密钥。
- [ ] 自己完成可执行的完整模拟器流程；需要安装时集中到完整候选包，不再将每个子功能交给用户验收。
- [x] 更新27之后的实现/验收记录，逐条说明已验证和外部未验证项。用户暂缓的语音与未连接的真机不得冒充通过。

当前证据与唯一设备安装门槛见 `docs/28-日程操作与标签统一候选.md`。新候选包未安装，原生复验条目保持未勾选；语音暂缓，不宣称全App完成。
