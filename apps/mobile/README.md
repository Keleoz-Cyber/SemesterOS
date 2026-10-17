# 拾日 Flutter 客户端

拾日的移动端就在这儿。当前版本 `1.1.1+12`，正式包名 `cn.semesteros.semester_os`，最低 Android 7.0（API 24）。四个主页面是今日、日程、任务、学期，助手从面板或独立页面进。

日常怎么用看 [产品规则](../../docs/产品规则.md)；学校导入、图片和录音有什么限制看 [学校与媒体接入](../../docs/学校与媒体接入.md)；后端怎么起在仓库根目录的说明里。

## 先把环境弄好

要 Flutter、Android SDK、JDK、至少一个模拟器。`pubspec.yaml` 要求 Dart `^3.12.2`，所以 Flutter 版本得对得上。Android 的 Java 源码目标是 17，但仓库的启动脚本用 JDK 21 跑 Gradle，这一点容易踩。本机 JDK 21 不在默认位置的话，用 `SEMESTEROS_JDK_HOME` 指过去。

先看工具齐不齐：

```powershell
flutter doctor -v
flutter devices
```

依赖版本在 `pubspec.yaml` 和 `pubspec.lock` 里。拉依赖、静态检查、跑测试：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS\apps\mobile
flutter pub get
flutter analyze
flutter test
```

这几条只是“怎么查”。真跑出什么结果，得看你机器上这次跑出来的。

## 在模拟器上跑开发版

开发版默认连 `http://10.0.2.2:8871`。`10.0.2.2` 是模拟器访问你电脑回环地址的专用地址，所以后端必须先在本机起来。

开一个 PowerShell 跑后端：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS
.\scripts\dev.ps1 -Action Api
```

要有 Docker Desktop。这条会拉起本地 PostgreSQL、装后端依赖、跑迁移，然后监听 8871。第一次跑会比较久，别急着以为它卡死了。

再开一个窗口跑 App：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS
.\scripts\dev.ps1 -Action Android -Device emulator-5554 -Emulator Medium_Phone_33
```

脚本会找现成的设备，找不到就按名字起一个模拟器，然后交给 Flutter。名字不对就先看本机有哪些：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
```

模拟器已经开着，就直接给它的 ID，不用再指定 AVD：

```powershell
.\scripts\dev.ps1 -Action Android -Device emulator-5554
```

如果只是想打开装好的正式 App，不想重新编译：

```powershell
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
& "$androidSdk\emulator\emulator.exe" -avd Medium_Phone_33
```

起来之后另开一个窗口：

```powershell
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
& "$androidSdk\platform-tools\adb.exe" -s emulator-5554 shell am start -n cn.semesteros.semester_os/.MainActivity
```

上面这些设备 ID、模拟器名、“App 已经装了”都是前提，本机情况用 `adb devices` 和 `-list-avds` 自己核。

## 换个服务地址

也可以不用脚本，直接上 Flutter：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS\apps\mobile
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8871
```

正式构建的默认地址是 `https://semesteros.keleoz.com`。`API_BASE_URL` 是编译期常量，改完要重跑或重新构建。传的是服务根地址，`/api/v1` 前缀由客户端的请求代码自己加。

真机调试别把 `10.0.2.2` 当成电脑地址，它在真机上什么都不是。要么给一个手机能访问的服务地址，要么自己配 ADB 端口转发。改之前先看网络和 Android 的网络安全配置，别为了省事关掉正式版的 HTTPS 限制。

## 隔离的验证包

要跑合成数据或者接独立后端时，用 QA 包，别拿正式包去跑，免得把真实数据搅了：

```powershell
Set-Location D:\study\Contest\AIC\SemesterOS\apps\mobile
flutter build apk --debug --target-platform=android-x64 -PsemesterosQa=true --dart-define=API_BASE_URL=http://10.0.2.2:8874
```

出来的是给 x86_64 模拟器用的 Debug APK，包名 `cn.semesteros.semester_os.qa`，名字叫“拾日 · 验证”。它不是发行包，也不会顺手把 8874 的服务起起来。隔离后端用 `scripts/app_flow_qa_server.py` 起，数据库和媒体都落在 `output/verification` 下面的子目录里，用的是真实模型配置，里面没有学校账号，也没有用户数据。

## 代码怎么分的

| 目录 | 里面是什么 |
| --- | --- |
| `lib/app` | 启动、登录和学期会话、路由 |
| `lib/core` | HTTP 请求、本地缓存、会话存储 |
| `lib/features/home` | 今日、空档建议、首页设置 |
| `lib/features/calendar` | 周课表、按天列表、日程表单、冲突核对 |
| `lib/features/items` | 待办和考试、Android 提醒同步 |
| `lib/features/planning` | 学习时间、方案预览、安排和重排结果 |
| `lib/features/agent` | 助手对话、历史、修改预览和回执 |
| `lib/features/import` | 选学校、WebView、课表解析、导入核对 |
| `lib/features/media` | 图片、录音、系统分享、剪贴板提示 |
| `lib/features/tags` | 标签推断、整理、跨学期查看 |
| `lib/features/centers` | 课程、考试、学期 |
| `lib/features/changes` | 调课、停课、请假这类课次变化 |
| `lib/features/accounts`、`profile`、`search`、`insights` | 数据与反馈、个人资料、搜索、统计 |
| `lib/ui` | 共用控件、弹层、时间选择器、兼容主题 |
| `lib/ui/v2` | 现在的颜色、字体、间距和动效组件 |
| `android` | 权限、通知接收、系统分享、WebView 兼容 |
| `test`、`integration_test` | 组件、行为、设备流程测试 |

账户和说明类的路由都集中在 `lib/app/semester_app.dart`。

## 改界面时要注意的

主题入口是 `lib/ui/v2/shiri_theme.dart`，具体数值在 `shiri_tokens.dart`。`campus_theme.dart` 和 `forui_theme.dart` 是给旧组件和 forui 控件做适配的，不要在里面直接改业务颜色。新页面尽量复用 `AppButton`、`AppField`、`AppTile`、统一弹层和时间选择器，别又整一套配色和确认方式出来。

四个主页面用 `IndexedStack` 留着，滚动位置按账号、学期、页面分开记。隐藏的页面把动画停掉，否则后台计时器会一直重绘。周课表用 `PageView` 横向切周，别改回“整张课表淡出再重建”，那个闪烁很明显。助手和录音的按下、长按、取消是三种状态，都得单独试。

服务端点头之后，任务才能显示成已完成。保存、撤销、冲突、未知时间、账号隔离是业务规则，视觉上怎么改都不能绕过去。

## 标签和系统入口

`features/tags/tag_intelligence.dart` 在本机推断标签，不调模型。词表是共享的，源头在 `services/api/app/data/tag_rules.json`，改完从仓库根目录跑：

```powershell
python scripts/generate-tag-rules.py
```

生成 `apps/mobile/lib/features/tags/tag_rules.g.dart`。两端词表一致不一致，后端测试会管。标签页会自动整理旧标签，搜索认旧名字；点名称那行打开关联事项，右边菜单里是手动重命名和合并。`tag_records_page.dart` 管跨学期、分页和历史，别的学期的详情要放进对应的编辑会话里，不然改出来的东西会串到当前学期。

Android 那边的入口靠 `lib/core/device_surfaces.dart` 和 `DeviceSurfaces.kt` 配合，桌面日程卡、快速记录、进行中通知、系统设置、JSON 导出都在这条线上。本地闹钟和提醒按钮还走 `features/items/android_notifications.dart` 和 `reminder_sync.dart`。动其中一种入口，另外两种得一起看。

## 发版前

至少把静态分析和测试跑一遍；动了交互就在模拟器上把对应流程走一遍。重点看窄屏和放大字号、减少动画、连续几周来回切、键盘挡住输入框、按住说话、保存和撤销、切完账号之后旧请求才返回这几种。

正式 APK 用仓库的 `scripts/build_release.py`，参数先看清楚再敲。私钥、签名密码、教务凭据、`.env`、临时 QA 数据库都不要进仓库。正常包和 QA 包的包名用途不同，发行前把版本、服务地址、签名都核一遍。

发版时要加 `pubspec.yaml` 的构建号，同时让后端 `version.py` 和 `personal_data_page.dart` 里反馈用的版本号保持一致——这次是 `1.1.1+12`。打完包再核一次包名、地址、签名和版本，然后覆盖装到已有的 App 上，确认账号数据还在。
