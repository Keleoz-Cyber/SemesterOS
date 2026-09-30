# Flutter开源组件库调研

调研时间：2026-09-27。目的：寻找可以改善拾日视觉与交互质量的成熟实现。当前App Flutter 3.44.2 / Dart 3.12.2；正式依赖未修改。

后续状态：用户批准后，Forui 0.25.0、smooth_sheets 1.2.0、flutter_animate 4.5.2已加入正式依赖并用于公共控件、弹层和转场。以下内容保留调研时的比较，接入与验证见docs/34-组件库接入与同页识别.md。

## 建议

优先验证 **Forui 0.25.0 + smooth_sheets 1.2.0 + flutter_animate 4.5.2**。基础控件选择一个体系，定制蓝绿校园主题；复杂弹层和动效作为辅助。不能直接套默认黑白主题，也不能把接入组件库当成完成视觉设计。

| 候选 | 适用范围 | 核对结果与取舍 |
| --- | --- | --- |
| [Forui](https://forui.dev/) | 页签、表单、选择器、列表、日期与时间输入、主题体系 | 优先候选。0.25.0要求Flutter>=3.44，适配现有SDK；当前最新0.27.2要求Flutter>=3.47、Dart>=3.13，不能直接安装最新版。代码MIT，字体资源OFL |
| [shadcn_ui](https://pub.dev/packages/shadcn_ui) | 基础组件替代方案 | 0.57.1声明Flutter>=3.41、Dart>=3.11；MIT。可与Material共存，但不要与Forui同时作为基础组件体系 |
| [smooth_sheets](https://pub.dev/packages/smooth_sheets) | 助手输入、详情编辑、筛选等底部面板 | 优先候选，支持拖拽、吸附、内部导航和键盘相关行为；MIT。仍需原生手势与键盘测试 |
| [flutter_animate](https://pub.dev/packages/flutter_animate) | 状态切换、列表增删与转场编排 | 辅助候选，BSD-3-Clause。按操作使用动效，保留减少动画偏好；不会自动解决布局问题 |
| [WoltModalSheet](https://github.com/woltapp/wolt_modal_sheet) | 多页弹层、响应式模态框 | MIT，有产品使用背景；作为smooth_sheets替代。其样式和页索引导航与smooth_sheets有所不同，避免两套并存 |
| [Kalender](https://pub.dev/packages/kalender) | 日/周/月/议程，拖动改期、缩放和事件尺寸 | MIT。0.32.0仍在1.0前，官方明确小版本可能有破坏性变更。当前已真实使用calendar_view，不为换库立即迁移；先以重叠课程/跨日/大字号/锁定课程对照测试 |
| [TDesign Flutter](https://github.com/Tencent/tdesign-flutter) | 中文移动端控件、图标和主题 | MIT，有中文移动设计参考价值；稳定版0.2.7 pubspec锁定image_picker 1.1.2，与项目固定1.2.0冲突。先作为视觉/交互参考，不能直接整包加入 |
| [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) | 另一套独立shadcn组件体系 | 与shadcn_ui不是同一个包。当前0.0.54要求Flutter>=3.47、Dart>=3.13，不作为现阶段直接接入候选 |

## 项目现状

- calendar_view 2.0.0在features/calendar/schedule_grid.dart实际使用。
- fl_chart 1.2.0在features/insights/insights_page.dart实际使用。
- 因而优先解决基础控件的一致性、弹层和交互细节，图表仍需内容组织与视觉定制。

## 本次验证

- 阅读上述项目官方仓库、pub.dev包页和发布元数据；查看Forui官方网站组件展示与Tabs页面。
- 用项目pubspec.yaml/pubspec.lock副本做隔离依赖解析；正式App依赖不变。
- Forui 0.25.0 + smooth_sheets 1.2.0 + flutter_animate 4.5.2：`flutter pub add --dry-run`退出0，日志output/ui-library-research/forui-resolution.log。
- shadcn_ui 0.57.1 + smooth_sheets 1.2.0：同样退出0，日志output/ui-library-research/shadcn-resolution.log。
- 初次空目录dry-run因Flutter后置工具缺少package_config退出1；在副本运行baseline pub get后重新dry-run成功。两次均没有改正式项目。
- 这里只验证元数据与依赖共存，尚未接入页面、编译候选库或做原生性能/无障碍实测。

后续接入应以真实详情、输入、统计三类页面检验同一套视觉规则，确定组件适配后统一替换。课程固定时间、来源确认和保存边界不由组件库决定。

## 版本依据

- [Forui 0.25.0及SDK要求](https://pub.dev/packages/forui/versions/0.25.0)
- [Forui当前包与SDK要求](https://pub.dev/packages/forui)
- [shadcn_ui Material混用说明](https://mariuti.com/flutter-shadcn-ui/)
- [smooth_sheets功能与键盘行为](https://pub.dev/packages/smooth_sheets)
- [Kalender迁移与1.0前变更说明](https://pub.dev/packages/kalender)
- [TDesign发布包元数据](https://pub.dev/api/packages/tdesign_flutter)
