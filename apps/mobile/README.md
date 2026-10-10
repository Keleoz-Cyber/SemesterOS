# 拾日 Flutter 客户端

这里是拾日的移动端工程。当前版本为 `1.0.0+9`，Android 正常包名为 `cn.semesteros.semester_os`，最低 Android 版本为 7.0（API 24）。主要入口是今日、日程、任务、学期，助手以面板或独立页面打开。

日常使用说明见 [产品规则](../../docs/产品规则.md)，学校导入和图片、录音限制见 [学校与媒体接入](../../docs/学校与媒体接入.md)。后端部署由仓库根目录的说明负责。

## 准备开发环境

需要 Flutter、Android SDK、可用的 JDK 和 Android 模拟器。`pubspec.yaml` 要求 Dart `^3.12.2`；先使用带有对应 Dart 的 Flutter 版本。Android Java 源码目标为 17，仓库启动脚本要求 JDK 21 运行 Gradle。可通过 `SEMESTEROS_JDK_HOME` 指定本机 JDK 21 目录。

在 PowerShell 中检查工具：

```powershell
flutter doctor -v
flutter devices
```

依赖版本记录在 `pubspec.yaml` 和 `pubspec.lock`。获取依赖、运行静态检查和单元/组件测试：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS\apps\mobile
flutter pub get
flutter analyze
flutter test
```

这些是检查命令。本文件没有把过去一次测试通过当成当前环境已经通过。

## 在模拟器运行开发版

开发版默认连接 `http://10.0.2.2:8871`。其中 `10.0.2.2` 是 Android 模拟器访问电脑回环地址的入口，后端必须先在电脑启动。

从仓库根目录开一个 PowerShell 窗口运行后端：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS
.\scripts\dev.ps1 -Action Api
```

该命令需要 Docker Desktop，会启动本地 PostgreSQL、安装后端依赖并执行迁移，再监听 8871 端口。首次运行会花一些时间。

另开一个 PowerShell 窗口运行 App：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS
.\scripts\dev.ps1 -Action Android -Device emulator-5554 -Emulator Medium_Phone_33
```

脚本会查找已有设备或启动指定模拟器，再运行 Flutter。模拟器名称不同，可以先查看本机名单：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
```

设备已启动时，指定它的实际 ID：

```powershell
.\scripts\dev.ps1 -Action Android -Device emulator-5554
```

如果只想打开已经安装的正式 App，不需要重新编译：

```powershell
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
& "$androidSdk\emulator\emulator.exe" -avd Medium_Phone_33
```

模拟器启动后，在另一个窗口执行：

```powershell
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
& "$androidSdk\platform-tools\adb.exe" -s emulator-5554 shell am start -n cn.semesteros.semester_os/.MainActivity
```

这里的设备 ID、模拟器名称和“App 已安装”都是前提。用 `adb devices` 和 `-list-avds` 核对本机实际情况。

## 指定服务地址

也可以绕过启动脚本，直接使用 Flutter：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS\apps\mobile
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8871
```

正式构建的默认地址为 `https://semesteros.keleoz.com`。`API_BASE_URL` 在编译时确定，修改后需要重新运行或构建。API 前缀由客户端请求代码处理，传入的是服务根地址。

真机调试不能把 `10.0.2.2` 当成电脑地址。可以使用手机可访问的服务地址，或自行配置 ADB 端口转发；先检查网络和 Android 网络安全配置，不要为了方便取消正式版的 HTTPS 限制。

## 隔离验证包

需要跑合成数据或独立后端时，使用 QA 包，避免覆盖正式 App 的数据：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS\apps\mobile
flutter build apk --debug --target-platform=android-x64 -PsemesterosQa=true --dart-define=API_BASE_URL=http://10.0.2.2:8874
```

这条命令生成适合 x86_64 模拟器的 Debug APK，包名为 `cn.semesteros.semester_os.qa`，名称为“拾日 · 验证”。它不是正式发行 APK，也不会自动启动 8874 端口的服务。隔离后端可通过仓库的 `scripts/app_flow_qa_server.py` 启动，该脚本把数据库和媒体放在指定的 `output/verification` 子目录，使用真实模型配置，不自带学校账号或用户数据。

## 工程怎么分

| 目录 | 内容 |
| --- | --- |
| `lib/app` | App 启动、登录和学期会话、路由配置 |
| `lib/core` | HTTP 请求、本地缓存和会话存储 |
| `lib/features/home` | 今日信息、空档建议和首页设置 |
| `lib/features/calendar` | 周课表、按天列表、日程表单和冲突核对 |
| `lib/features/items` | 待办、考试等事项，以及 Android 提醒同步 |
| `lib/features/planning` | 学习时间、方案预览、学习安排和重排结果 |
| `lib/features/agent` | 助手聊天、历史对话、修改预览与回执 |
| `lib/features/import` | 学校选择、WebView、课表解析与导入核对 |
| `lib/features/media` | 图片、录音、系统分享和剪贴板提示 |
| `lib/ui` | 共用控件、弹层、时间选择器和兼容主题 |
| `lib/ui/v2` | 当前颜色、字体、间距及动效组件 |
| `android` | Android 权限、通知接收、系统分享和 WebView 兼容 |
| `test`、`integration_test` | 组件、行为和设备流程测试 |

## 改界面时注意什么

主题入口在 `lib/ui/v2/shiri_theme.dart`，数值在 `shiri_tokens.dart`。`campus_theme.dart` 和 `forui_theme.dart` 负责旧组件与现有控件的适配。新增页面尽量复用 `AppButton`、`AppField`、`AppTile`、统一弹层和时间选择器，不另写一套配色和确认方式。

四个主页面由 `IndexedStack` 保留，滚动位置按账号、学期和页面区分。隐藏页停止动画，避免后台计时持续重绘。周课表用 `PageView` 横向切周，不要改回整张课表淡出再重建。助手和录音入口的按下、长按与取消需要分别检查。

服务端确认成功后才能把任务显示成已完成。保存、撤销、冲突、未知时间、账号隔离属于业务行为，视觉改动不能绕过这些检查。

## 发布前的客户端检查

至少检查静态分析和测试；动了相关交互，还要在模拟器走对应流程。重点包括窄屏和放大字号、减少动画、周次连续切换、键盘遮挡、按住说话、保存和撤销、账号切换后旧请求返回。

正式 APK 的构建、签名和输出使用仓库 `scripts/build_release.py`，先查看脚本参数。不要把私钥、签名密码、教务凭据、`.env` 或临时 QA 数据库提交到仓库。正常构建和 QA 构建的包名用途不同，发行前核对版本、服务地址和签名。
