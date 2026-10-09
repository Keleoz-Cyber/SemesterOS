# 拾日 · 晴日设计规范

此目录仅保留当前规范和变量；旧原型、截图、重复资源与参考代码已清理。

- [MASTER](../shiri/MASTER.md)：产品、数据和无障碍约束。
- [DESIGN](DESIGN.md)：视觉、布局和动效模式。
- [tokens.json](tokens/tokens.json)：颜色、尺寸和动效数值。
- [生产实现](../../apps/mobile/lib/ui/v2/)：唯一组件实现。
- [运行素材](../../apps/mobile/assets/)：当前加载资源。
- [生成器](../../apps/mobile/tool/build_assets.py)：13张插画、8个导航SVG，可用 `--output-dir` 隔离核对。

启动图标由 `apps/mobile/tool/export_brand.cjs` 从 `app_icon.svg` 导出，界面使用 `mark.svg`。调整素材后运行客户端检查，避免资源与实现不一致。
