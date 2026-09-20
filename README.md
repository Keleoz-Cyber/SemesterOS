# 学期OS（SemesterOS）

面向大学生的学期事务管理 App：将课表、作业、考试和临时通知转为可追溯的事项，分析时间余量，生成个人计划，并在现实安排变化后进行最小扰动重排。

## 当前状态

当前为 **0.1.0 课表导入测试版**，已实现 Android 工程、注册登录与恢复、学期设置、手工录课、教务原站读取入口、导入预览确认、周课表/列表和按账号隔离的本机缓存。第一版面向 Android，iOS 后续适配。

已接入 Flutter、FastAPI 和 PostgreSQL，依赖锁在`apps/mobile/pubspec.lock`及`services/api/requirements.lock`。AI解析、提醒、个人任务和 OR-Tools 规划尚未实现；这些仍按设计文档推进。真实教务登录后的课表读取尚待本人验证，不能把已打开登录页或手工录课成功算作真实导入成功。

## 项目文档

- [01｜产品需求与功能设计](docs/01-产品需求与功能设计.md)
- [02｜技术设计](docs/02-技术设计.md)
- [03｜UI与交互设计](docs/03-UI与交互设计.md)
- [04｜测试与比赛说明](docs/04-测试与比赛说明.md)
- [05｜需求确认与教务接入调研](docs/05-需求确认与教务接入调研.md)
- [AI生成的视觉参考图](docs/预览图/)：仅供样式参考，业务规则以文档为准。
- [第一批开发与验证记录](docs/06-第一批开发与验证记录.md)

## 本机运行（PowerShell 7）

先启动 Docker Desktop，并准备 Python 3.12、Flutter 和 Android Studio 模拟器。根目录执行：

```powershell
# 终端1：创建本地私有配置、启动PostgreSQL、迁移并运行API
pwsh -File scripts/dev.ps1 -Action Api

# 终端2：先在Android Studio启动模拟器，再运行App
pwsh -File scripts/dev.ps1 -Action Android -Device emulator-5554

# 验证：PostgreSQL独立测试schema + Flutter测试及静态分析
pwsh -File scripts/dev.ps1 -Action Test
```

API使用`http://127.0.0.1:8871`，模拟器通过`http://10.0.2.2:8871`访问；PostgreSQL只绑定本机`55439`端口，避免占用已有项目的`55432`。首次运行脚本生成`.env`，不输出密码。API已在运行时无需重复启动同端口服务。

用 Android Studio 打开`apps/mobile`目录。当前验证设备为`Medium_Phone_33`（Android 13）。本次导出的调试包只含x86_64，用于该模拟器；物理手机需另构建适合其架构的包。调试包允许本地HTTP，正式发布需要HTTPS入口和独立签名配置；本批不发布正式签名包。

完整容器运行配置在`deploy/compose.yaml`，可执行`docker compose --env-file .env -f deploy/compose.yaml up --build`；当前实测组合为PostgreSQL容器加本机Python API，API镜像构建未作为本批完成证据。

## 教务与导入边界

- 正常流程：注册自己的学期OS账号 → 创建并核对学期/节次 → 记录 → 从学校教务导入 → 学校原页自行登录 → 进入个人课表查询 → 读取 → 核对来源学期和课程 → 确认保存。
- 只从`jwglxt.haut.edu.cn`已登录课表页读取白名单字段；统一认证的其他跳转域名尚未实测，当前会阻止未知跳转。
- 空响应或无法识别的周次/节次不会当作导入成功；首次读取真实数据后还需检查学校的实际返回格式。
- 本批支持新增和精确重复检查；教务同一课程的时间模式变化会标为待核对，暂不自动应用调课。明确手工添加的另一次授课允许保存。
- 离线可看已缓存的周次，已知过期或从未缓存的周次会提示需联网；退出账号清理该账号本机缓存与教务会话。
- 测试账号和手工构造课程用于验证，不作为真实学生试用数据。

## 工具链兼容性

已实测Flutter 3.44.2 / Dart 3.12.2，使用本机已有的Gradle 8.14、AGP 8.11.1、Kotlin 2.2.20；工程保留HTTPS Maven镜像与官方源。Windows跨盘Kotlin增量缓存存在路径错误，因此本项目关闭该增量缓存并使用进程内编译，未修改其他项目。

构建JVM由`apps/mobile/android/gradle/gradle-daemon-jvm.properties`固定为 **Java 21**，需要本机安装JDK 21。它优先于Android Studio自带JBR和`JAVA_HOME`选择Gradle构建进程，因此IDE升级到JBR 25后仍使用兼容的构建JVM；不修改全局Flutter或Java配置。本机已检测到`C:\Program Files\Microsoft\jdk-21.0.4.7-hotspot`，仓库不硬编码这个路径。若出现只写着`25.0.x`的构建异常，先检查此配置是否存在；依赖列表的“有新版本”提示不是同一个问题。[Gradle JVM规则](https://docs.gradle.org/current/userguide/gradle_daemon.html#sec:daemon_jvm_criteria)

固定`material_ui`/`cupertino_ui` 1.0.0以适配当前Flutter SDK；较新版本引用了此SDK没有的注解。Drift 2.28.2与sqlite3_flutter_libs 0.5.39避免当前网络下SQLite 3.x原生资源下载失败。更新依赖需重新验证，不能直接清除锁文件升级。

## 数据与开发约定

- 教务密码、Cookie、模型密钥和签名密钥不进入仓库。
- 临时文件、设备配置和构建产物由 `.gitignore` 排除。
- 合成演示数据与真实试用数据分开；示例导入不视为真实认证导入成功。
- 保留来源、版本和确认记录；AI失败后基础事务仍应可管理。
