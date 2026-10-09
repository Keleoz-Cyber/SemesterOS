# 拾日（SemesterOS）

大学生学期事务 App：统一管理课表、通知、任务、考试和个人学习安排，助手查询真实记录，修改先预览、确认后保存。

## 1.0.0 发行

Android **1.0.0+8**，源码以 `main` / `v1.0.0` 为准。[GitHub Release](https://github.com/Keleoz-Cyber/SemesterOS/releases/tag/v1.0.0) 提供 APK 和校验文件。本机唯一交付包为 `output/apk/拾日-1.0.0.apk`，构建信息与最终检查在 `output/release/`。正式 API 为 `https://semesteros.keleoz.com`；实际发布、哈希和验收边界统一见 [交付说明](docs/交付说明.md)。

四个入口为今日、日程、任务、学期。支持河南工业大学和黑龙江大学本科教务导入及文字、图片、语音来源。未知时间按原精度保留；仅按已知时间事实核对冲突，不强迫整天请假。已请假课次在日常视图隐藏，原课和恢复入口保留。对话删除后不可恢复，已保存业务保留。

## 开发运行（PowerShell）

需要 Docker Desktop、Python 3.12、Flutter/Android SDK、JDK 21、Node.js 18+。版本以 lock 文件为准。

```powershell
pwsh -File scripts/dev.ps1 -Action Api
pwsh -File scripts/dev.ps1 -Action Android
pwsh -File scripts/dev.ps1 -Action Test
```

API 为 `127.0.0.1:8871`，模拟器使用 `10.0.2.2:8871`，本机数据库端口为 `55439`。首次运行会重建虚拟环境和锁定依赖。本机媒体模型按 [接入手册](docs/学校与媒体接入.md) 重新安装；云端客户端不依赖本机模型。

连接正式服务：

```powershell
. ./scripts/android-device.ps1
Set-SemesterGradleJava
$device = Resolve-SemesterAndroidDevice -ProjectRoot (Get-Location).Path -Device auto
Set-Location apps/mobile
flutter pub get
flutter run -d $device --dart-define=API_BASE_URL=https://semesteros.keleoz.com
```

## 构建与清理

```powershell
python scripts/build_release.py --build
# 不加 -Apply 只显示目标
pwsh -File scripts/clean.ps1
pwsh -File scripts/clean.ps1 -Apply -DeveloperCaches
```

发布工具在 Windows 上使用 JDK 21、Android SDK 和已有证书，检查三架构、签名及16KB对齐；默认沿用开发证书以兼容已安装版本，不生成或提交私钥。自有证书可通过参数指定，密码从环境变量读取。清理保留当前 APK、小体积发行记录、Git、源码、配置和原始媒体；删除历史输出、构建缓存及可重建本机依赖，不建立备份目录。

## 项目入口

| 内容 | 入口 |
| --- | --- |
| 当前手册、技术契约、部署与验收 | [docs/README](docs/README.md) |
| 产品、数据与无障碍规则 | [产品规则](docs/产品规则.md)、[MASTER](design-system/shiri/MASTER.md) |
| 视觉规范与生产组件 | [设计规范](design-system/shiri-v2/README.md)、`apps/mobile/lib/ui/v2/` |
| Flutter客户端与宣传工具 | `apps/mobile/lib/`、`apps/mobile/tool/` |
| API、规划、助手与迁移 | `services/api/app/`、`services/api/alembic/versions/` |
| 本机开发/隔离验证与云端运维 | `scripts/`、`deploy/` |

旧计划、重复参考实现和阶段报告已合并清理，历史变更可从 Git 查询。私有配置、凭据、课表及原始媒体不进入 Git；验证限制以交付说明为准。
