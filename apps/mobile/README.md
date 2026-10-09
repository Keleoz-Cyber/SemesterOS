# 拾日 Flutter 客户端

版本见 `pubspec.yaml`。运行、签名发布、清理和验收统一见 [项目README](../../README.md) 与 [当前手册](../../docs/README.md)。

- `lib/features/` 是业务页面，`lib/ui/` 是共用组件。
- `assets/` 是运行素材与学校读取脚本，`tool/` 是资源生成和匿名宣传导出。
- `test/` 为单元/Widget回归，`integration_test/` 为隔离Android操作验证。

宣传导出使用生产Widget和匿名合成数据。设置独立的 `PROMO_OUT`、`UI_PREVIEW_FONT`、`UI_PREVIEW_ICONS` 后运行 `flutter test tool/export_promo_plates.dart`。宣传图不是真实业务记录，固定时钟不能覆盖发布包时间。
