# V2 本地交互原型

直接用浏览器打开`index.html`。同目录`style.css`和`app.js`必须保留。无需后端或网络。

原型覆盖今日、日程、计划、学期、组会新增与计划重排、撤销、学校选择、模块编辑、离线示意。固定合成时间为2026-09-23 11:40，主要场景只预置第4周。品牌名称和图标未定稿。

没有调用模型、云端API、教务或麦克风，不会修改真实数据。语音／图片只说明交互入口。原型中显示的提醒与保存结果是本页状态，关闭页面后不会保留。

## 验证

`verify.cjs`使用Playwright库和已安装Chrome的headless模式，将HTML／CSS／JS加载到内存，不启动HTTP服务；页面所有网络请求都被阻断。运行前用`PLAYWRIGHT_MODULE`指定本机已安装的Playwright模块，或使用Node能正常解析到的`playwright`。

从项目根目录运行：

```powershell
node docs/prototypes/v2/verify.cjs
```

输出到`output/v2-prototype/`：页面截图、交互验证JSON、单文件HTML。它验证浏览器原型，不能替代Flutter测试、真实模型调用、Android通知或真机性能检查。
