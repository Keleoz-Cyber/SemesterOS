# 原始测试文件

这里保存2026年10月9—10日的实际测试输入、接口结果和模拟器截图。代码基线为1.0.0+8，使用新建合成账号。测试内容的解释见[测试报告](../../拾日模拟器验证与算法测试报告.md)。

## 文件怎么找

| 文件或目录 | 内容 |
| --- | --- |
| [environment.json](environment.json) | 当时的模拟器、App、后端和依赖版本 |
| [backend/backend-report.json](backend/backend-report.json) | 8组后台测试汇总；同目录中有每组完整结果 |
| [backend/prerequisites-report.json](backend/prerequisites-report.json) | 3组缺估时、开始条件和拒绝方案测试 |
| [backend/replan-ablation.json](backend/replan-ablation.json) | 3个场景中两种重排目标的对照结果 |
| [ui-report.json](ui-report.json) | 9组模拟器主线检查结果 |
| [ui](ui) | 主线截图、界面结构和保存前后的数据 |
| [comparison/comparison-report.json](comparison/comparison-report.json) | 同一条任务用手工表单和AI录入的对照 |
| [comparison/preview/preview-report.json](comparison/preview/preview-report.json) | 独立场景中的首次方案预览和拒绝 |
| [scripts](scripts) | 本轮实验工具源码 |
| [manifest.json](manifest.json) | 文件大小和SHA-256清单，便于检查文件是否改变 |

JSON是机器保存的结果，PNG是截图，XML是当时的界面文字和控件信息。账户密码、访问令牌和模型密钥不在交付材料中。

## 看截图时注意什么

主线目标日是10月10日，独立的首次方案拒绝测试目标日是10月11日，不能把两个账号的画面当成一条连续操作。

03、13、15和22的部分截图仍在处理，不能证明最终结果已经显示。04显示课程冲突选择，22b显示完整重排方案。20是输入模式切换后的旧画面，新活动对应20b。保存是否发生，要同时看相应接口结果。

API中仍保留已请假课程的原记录，日程界面只是隐藏对应课次。看到界面少了一门课，不代表软件删除了整门课程。

## 重新运行

先按[部署说明](../../../部署与维护.md)安装依赖，再使用本机8874端口和新的临时SQLite。脚本会创建合成账户，不应改成连接正式数据服务。真实模型测试需要已配置的模型密钥，会实际调用模型。

在仓库根目录的PowerShell中启动隔离服务：

```powershell
.\services\api\.venv\Scripts\python.exe .\scripts\app_flow_qa_server.py --data-dir .\output\verification\aic-repeat\runtime --port 8874
```

另开终端执行后台测试：

```powershell
.\services\api\.venv\Scripts\python.exe .\docs\参赛资料\验证证据\aic-20261009\scripts\backend_cases.py --execute-local --database .\output\verification\aic-repeat\runtime\qa.sqlite --output .\output\verification\aic-repeat\backend
```

不加`--execute-local`时该脚本不会发出业务请求。其他脚本参数用`--help`查看。新结果写到新的输出目录，保留本次原始结果。

UI工具用于分步操作当前可见界面，不是一个可以自动重跑全部场景的脚本。它只操作QA包；中文输入工具仅用于向输入框写字，不代表语音识别已经通过测试。

这些测试没有测量真人效率、总体识别准确率或Release性能，文件数量和检查条数也不等于独立功能数量。
