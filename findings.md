# 工作发现

## V2重设计

- 第一批高保真独立于旧流程原型，路径docs/prototypes/v2-hifi。统计合成数据按标签并集去重，实际时长与已安排分开，完全未记录用破折号表示，类别分项亦如此。
- 数字和条形图支持中断并以最后选择为准；无真实模型、录音或外部请求。2026-09-26离线Chrome17项验证通过，不能当作Flutter真机性能结果。

- 原型已实现四页面、通知候选／重排／回执／撤销、学校搜索、周选择和模块配置；交互均为本地合成状态，不是真实AI。
- 调研结果：保留当前deepseek-flash，官方Tool Calls页面可读且使用该名称。LangGraph为候选首选、PydanticAI为备选；calendar_view2.0.0精确锁版本试验优先，kalender因开发期兼容风险保留备选。
- 浏览器截图首次截到转场中间态，使用animations:disabled截取静止结果后复查。离线Chrome验证通过，生产与Flutter性能尚未测试。

- 官方调研：LangGraph提供持久化检查点与PostgreSQL后端；PydanticAI提供deferred tools和DeepSeek provider。审批机制不代替业务鉴权，仍需服务端绑定用户、候选和版本。
- DeepSeek工具调用官方旧链接两次返回内部错误，改从官网首页／搜索获取实际页面；不据此假定工具调用已兼容。PydanticAI示例模型名与当前生产deepseek-flash不同，不自动变更现有模型配置。
- 暂拟LangGraph作为Agent编排首选、PydanticAI作为备选；最终安装版本和现有模型兼容需在隔离技术验证中锁定，本轮不引入生产依赖。

- 已读取首轮24项反馈与用户补充定位。Agent需查询真实日程并调用业务工具，不能只解析字段再让用户找功能。
- 现有后台已使用OR-Tools 9.15.6755，scheduler与replanner分别处理新计划和最小扰动；优先复用，不能把已有求解能力说成V2新引入。
- 固定日程缺失、多个入口重复、学期页状态重建、公共提示语义混淆已静态确认；解析失败根因及掉帧仍未做运行诊断。
- V2使用新文档和独立HTML原型，现有01/02/03为历史基线，不将新方案冒充已实现。
- calendar_view官方当前页面为2.0.0，提供日／周／月视图，MIT许可证，并明确要求2.x精确锁版本。实际Flutter兼容性还需验证。
- 当前后端为semesteros.keleoz.com；调研与原型无需请求真实用户数据或调用生产模型。

## 首次部署检查记录 历史

- SSH可用，Ubuntu 24.04，4核，约3.7GB内存，2GB swap，系统盘可用26GB。
- Docker Compose已安装。现有博客项目在/opt/keleoz-continuum，应用仅监听127.0.0.1:8080。
- Nginx负责80/443，keleoz.com及www.keleoz.com已有有效证书；拟增加独立路径，不修改博客根路由。
- 学期OS本机API监听127.0.0.1:8871；现有APK默认10.0.2.2:8871，Flutter引擎仅x86_64，不适用于普通ARM手机。
- 后端已有Dockerfile与开发Compose，但尚缺云端重启策略、独立worker和预置OCR模型。
- 本地已有SenseVoice int8与RapidOCR ONNX模型，可校验后传至服务器，避免首次请求下载。
- 现有博客域名经过EdgeOne，Nginx已有客户端IP解析；学期OS转发必须重写X-Forwarded-For并对响应设置private/no-store，防止跨用户缓存。
- API、worker及数据库实际空闲内存约155MB、605MB、44MB；原博客保持运行。已实测云端OCR/ASR和AI，不仅是健康检查。
- 云端数据库没有迁移私人数据；只包含验证时创建的隔离合成账号，新账号学期为空。
