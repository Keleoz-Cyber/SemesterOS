# 拾日（SemesterOS）

面向大学生的学期事务 App：将课表、通知、任务和考试放入同一套日程，通过助手查询与整理，检查时间余量，生成个人计划，并在现实安排变化后预览最小扰动重排。

## 当前状态与交付边界

源码使用 Flutter / Dart、FastAPI / Python、PostgreSQL 和 OR-Tools CP-SAT；界面实际采用 Forui、smooth_sheets 与 fl_chart。四个主入口为“今日／日程／任务／学期”，图片、语音和文字共用助手输入。已接入账号与恢复、学期和课程维护、河南工业大学与黑龙江大学本科教务导入、提醒、标签、统计及学习安排确认流程。

2026-10-07 已完成七项体验建议并接入实际页面，10-08 按用户提供的SVG更新启动及App内品牌图标，更新正常 **0.1.0+7 Release** 包。唯一交付文件是 `output/apk/拾日-0.1.0-手机测试.apk`，沿用原证书，包含三 ABI 并通过 16KB 对齐检查，已覆盖安装到模拟器。最新 APK 哈希、源码快照、正式服务、逐项行为和原生验证证据统一见[体验打磨与正式交付](docs/2026-10-07-体验打磨与正式交付.md)；带日期的前次验收记录保留用于追溯。

正式 API 地址为 `https://semesteros.keleoz.com`，当前 release 为 `history-leave-20261008-final`，迁移 0016；服务器操作与构建方式见[部署手册](docs/15-云端手机测试部署.md)。本轮按用户选择仅做模拟器验收；黑大真实账号已在正式 App 完成登录并读取 22 项预览（16 组课程、4 场考试、2 项实践），学校首周与 App 原设置的差异已提示，本次未确认覆盖原课表。有效语音识别、各型号手机性能与后台提醒触达仍需分别验证。

## 使用与数据规则

- 日程展示固定安排、课程、考试及个人学习计划；截止、仅日期、候选日期和未知时刻分别呈现。缺少地点、结束时刻或耗时可以保留，不补造确定信息。
- 助手查询与候选生成使用真实业务数据；修改、批量记录和计划应用展示具体对象、差异及影响。模型回复不能替代保存回执，旧候选和版本冲突须重新核对。
- “安排任务”补足选定目标，“重排”调整已有个人计划；锁定、已开始和不可行方案有独立处理。排入日历不代表完成，实际投入与剩余工作量由用户记录。
- 学校账号密码只在学校原页输入；导入先校对来源学期、学校钟点及变化范围，再确认保存。学校不同授课模式不按同名自动合并；未排实践与免听状态保持原语义。
- 图片与录音由服务端 OCR / ASR worker 处理，原媒体不发给文字模型；模型接收校对文字与业务上下文。来源、草稿、缓存和结果按账号、学期及版本隔离。
- 本机提醒的“已安排”表示同步状态，不保证已送达；完成、取消、退出账号及学期删除会处理相关提醒。厂商省电与后台限制仍需设备实测。

## 本机运行（PowerShell）

准备 Docker Desktop、Python 3.12、Flutter 和 Android SDK。已使用 Flutter 3.44.2 / Dart 3.12.2 验证；依赖版本以 `apps/mobile/pubspec.lock` 与 `services/api/requirements.lock` 为准。Gradle 构建 JVM 固定 Java 21，启动助手会定位本机 JDK，也可设置 `SEMESTEROS_JDK_HOME`；不需要修改全局 Java 配置。

在仓库根目录分别运行：

```powershell
# PostgreSQL、增量迁移和本机 API
pwsh -File scripts/dev.ps1 -Action Api

# 选择已连接 Android 设备；无设备时启动已有模拟器
pwsh -File scripts/dev.ps1 -Action Android

# 后端 PostgreSQL 测试、河南工大 JS 回归、Flutter 测试和静态分析
pwsh -File scripts/dev.ps1 -Action Test
```

API 监听 `127.0.0.1:8871`，Android 模拟器访问 `10.0.2.2:8871`；本机 PostgreSQL 映射到 `55439`。脚本首次生成私有 `.env`，不输出密码。文字模型在该文件配置 `DEEPSEEK_API_KEY`、`DEEPSEEK_MODEL`、`DEEPSEEK_BASE_URL` 后重启 API；未配置时仍可使用手工事务入口。

多个设备时使用 `-Device`；可用 `-Emulator` 指定已有模拟器，默认 `Medium_Phone_33`。启动记录保存在 `tmp/android-start/`。原生媒体插件改变后须完整运行，热重载不足以更新插件。

连接现有云端调试时，无需启动本机 API：

```powershell
$projectRoot = (Get-Location).Path
. .\scripts\android-device.ps1
Set-SemesterGradleJava
$deviceId = Resolve-SemesterAndroidDevice -ProjectRoot $projectRoot -Device auto -Emulator Medium_Phone_33
Set-Location (Join-Path $projectRoot 'apps/mobile')
flutter run -d $deviceId --dart-define=API_BASE_URL=https://semesteros.keleoz.com
```

首次准备语音模型：

```powershell
& services/api/.venv/Scripts/python.exe scripts/setup_media_models.py
```

私有媒体、模型分别保存在 `.local-data/media`、`.local-data/models`；容器运行配置见 `deploy/compose.yaml`，云端 API / worker / 数据库使用 `deploy/compose.cloud.yaml`。模型、媒体和数据库须按部署手册持久化。

## 验证工具

`dev.ps1 -Action Test` 需要 Node.js 18 或以上。黑大教务读取脚本可单独检查：

```powershell
node --test apps/mobile/test/hlju_reader_test.cjs
```

真实 Android 操作回归使用独立 QA 包和本机隔离服务；会创建合成账号并操作 QA 数据，使用前核对模拟器。运行方法与已验证范围见[App 流程实测](docs/2026-10-01-App流程实测.md)。例如在根目录先启动服务，再于另一终端运行流程：

```powershell
& services/api/.venv/Scripts/python.exe scripts/app_flow_qa_server.py --data-dir output/verification/manual-app-flow
pwsh -File scripts/test-app-flows.ps1 -Workflow records -Device emulator-5554
```

`scripts/verify_*_api.py` 与模型 smoke 是按需入口，部分会调用配置的真实模型，结果写入 `output/verification/`。`capture_phone_frames.py`、`capture_phone_timeline.py` 和 `analyze_phone_timeline.py` 用于明确启用帧探针的 Profile 构建；帧耗时不能直接当作稳定 FPS 或全设备体验结论。共享 Android UI helper 在 `scripts/android_qa.py`，隔离 QA 操作在 `verify_device_qa.py`。

## 文档与源码入口

[10 月 4 日代码审查与清理](docs/代码审查与清理.md)：对应阶段的删除清单、修复内容及验证范围。

| 目的 | 入口 |
| --- | --- |
| 当前交付、七项建议实现与验证边界 | [体验打磨与正式交付](docs/2026-10-07-体验打磨与正式交付.md)、[后端边界与随意提问审查](docs/2026-10-07-后端边界与随意提问审查.md)；当前包哈希与源码快照以交付记录为准 |
| 产品规则、技术基线与比赛要求 | [产品需求](docs/01-产品需求与功能设计.md)、[技术设计](docs/02-技术设计.md)、[测试与比赛说明](docs/04-测试与比赛说明.md)；这些是设计基线，实际实现以当前源码和测试为准 |
| 用户原始反馈及产品 / Agent 取舍 | [首轮反馈](docs/16-首轮体验反馈与重设计建议.md)、[产品交互方案](docs/17-V2产品与交互方案.md)、[Agent 架构](docs/18-V2技术选型与Agent架构.md)；后两份保留设计依据，不作为当前完成记录 |
| 当前 UI 与时间输入规则 | [拾日设计系统](design-system/shiri/MASTER.md) |
| 学校与媒体接入 | [河南工大调研](docs/05-需求确认与教务接入调研.md)、[黑大前期适配](docs/2026-10-03-黑龙江大学教务适配验收.md)、[黑大正式 App 登录与预览](docs/2026-10-07-体验打磨与正式交付.md)、[媒体模型与来源边界](docs/12-图片语音与来源恢复验证.md) |
| 维护、通知与助手契约 | [学期与课程维护](docs/37-学期与课程基础维护闭环.md)、[通知与身份契约](docs/superpowers/specs/2026-09-30-notice-assistant-design.md)、[助手操作边界](docs/2026-10-01-助手操作边界审查.md) |
| 运行、发布与前期接入证据 | [部署手册](docs/15-云端手机测试部署.md)、[App 前期流程实测](docs/2026-10-01-App流程实测.md)、[组件实际接入](docs/2026-10-02-Milestone组件接入验收.md)、[清理前包验收](docs/2026-10-04-交互层级与极简时间细化.md)、[10 月 4 日发布验收](docs/2026-10-04-发布与流程验收.md) |

客户端入口为 `apps/mobile/lib/main.dart`，业务页面在 `apps/mobile/lib/features/`，共用 UI 在 `apps/mobile/lib/ui/`；API 入口为 `services/api/app/main.py`，数据库增量迁移在 `services/api/alembic/versions/`。`.env`、密码、Cookie、模型密钥、签名密钥、私人课表、原图和录音不进入 Git。原始比赛 PDF 与用户反馈保留，合成验证数据不作为真实学生使用成绩。
