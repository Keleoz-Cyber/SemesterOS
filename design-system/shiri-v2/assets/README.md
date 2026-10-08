# 晴日 v2 · 矢量资源

全部是 SVG，**兼容 flutter_svg**：不含 filter、mask、pattern、style、text 或外链。由 `build_assets.py` 生成（品牌标志、太阳、月亮三个文件除外），想调整颜色或造型时改脚本后执行 `python build_assets.py` 重新生成。总览见 `preview.png`。

## 插画 `illustrations/`
所有插画都是透明底，自带一团淡淡的光晕底和地面阴影，可以直接放在 bg #F3F7FC 上。分组 id 统一为 `bg / ground / wave / main / sun / sparkle`，方便以后做局部动画。

| 文件 | 尺寸 | 用在哪里 | 建议显示宽度 |
|---|---|---|---|
| empty-today.svg | 240×180 | 今日没有安排；周课表这一天为空 | 200–220 |
| all-done.svg | 240×180 | 待办全部完成 | 200 |
| empty-tasks.svg | 240×180 | 任务列表为空 | 200 |
| empty-week.svg | 240×180 | 学期页选中周没有记录 | 200 |
| no-results.svg | 240×180 | 搜索、筛选无结果 | 180 |
| offline.svg | 240×180 | 网络或加载失败（配原因 + 重试） | 180 |
| import-timetable.svg | 240×180 | 还没导入课表、导入入口 | 220 |
| assistant-hello.svg | 240×180 | 助手新对话 | 180 |
| semester-start.svg | 240×180 | 还没建学期、学期未开始 | 220 |
| reminder-permission.svg | 240×180 | 申请通知权限 | 200 |
| onboard-collect.svg | 320×240 | 登录页、引导第 1 屏（把散落的通知拾起来） | 280–320 |
| onboard-plan.svg | 320×240 | 引导第 2 屏（空档放进任务） | 280–320 |
| onboard-adapt.svg | 320×240 | 引导第 3 屏（调课后只改必要的） | 280–320 |

## 图标 `icons/`
- **双色图标（24×24）**：主色 #2E6FE0，辅色 #8DC2FF。共 22 个：course、exam、task、event、plan、deadline、reminder、location、gap、reschedule、cancelled、voice、image、notice、import、stats、tag、semester、sparkle、today、schedule、tasks。
  - 需要按课程色着色时，用 `SvgPicture.asset(..., colorFilter: ...)` 会把两种颜色压成一种。要保留双色，可以复制一份改 `fill/stroke` 值，或者改 `build_assets.py` 后重新生成。
- **导航图标（24×24）**：`nav-{today,schedule,tasks,semester}` 和对应的 `-filled` 版本，共 8 个。使用 `currentColor`，例如：
  ```dart
  SvgPicture.asset('assets/icons/nav-today-filled.svg',
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn), width: 24, height: 24)
  ```
  线性版和填充版的轮廓完全一致，切换时只做一次轻弹（见 DESIGN.md §6.2-5）。

## 品牌与图案
| 文件 | 用途 |
|---|---|
| brand/mark.svg | 不带底板的品牌标志（十 + 屋顶 + 日历 + 太阳），用于登录页、关于页、今日页头的品牌行 |
| patterns/sun-mark.svg / moon-mark.svg | 今日页头的太阳和月亮、下拉刷新指示 |
| patterns/wave-hero.svg | 页头底边的两层波浪，曲线取自 App 图标；`preserveAspectRatio="none"`，可以横向拉伸 |

## 接入 Flutter
1. 在 `pubspec.yaml` 加入 `flutter_svg`；把需要的目录复制到 `apps/mobile/assets/`，并在 `flutter: assets:` 里声明。
2. 插画：`SvgPicture.asset('assets/illustrations/empty-today.svg', width: 200, excludeFromSemantics: true)`。插画是装饰性的，旁边的文字承担信息。
3. 可选：用 `vector_graphics_compiler` 把 SVG 预编译成 `.vec`，首帧更快。
