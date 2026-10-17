# 原始测试文件

这里是 2026 年 10 月 9 到 10 号跑出来的原始东西：实际执行的输入、接口返回、模拟器截图。代码基线是 1.0.0+8，用的是新建的合成账号。各类记录见下面的目录，引用时保留当时的日期、版本和数据范围。

## 哪个文件是什么

| 文件或目录 | 里面是什么 |
| --- | --- |
| [environment.json](environment.json) | 当时的模拟器、App、后端、依赖版本 |
| [backend/backend-report.json](backend/backend-report.json) | 8 组后台测试的汇总，同目录下有每组的完整结果 |
| [backend/prerequisites-report.json](backend/prerequisites-report.json) | 3 组缺估时、开始条件不满足、方案被拒的测试 |
| [backend/replan-ablation.json](backend/replan-ablation.json) | 3 个场景、两种重排目标的对照 |
| [ui-report.json](ui-report.json) | 9 组模拟器主线检查 |
| [ui](ui) | 主线截图、界面结构、保存前后的数据 |
| [comparison/comparison-report.json](comparison/comparison-report.json) | 同一条任务分别用手工表单和 AI 录入的对照 |
| [comparison/preview/preview-report.json](comparison/preview/preview-report.json) | 另一个场景里的首次方案预览和拒绝 |
| [scripts](scripts) | 这轮实验用的工具源码 |
| [manifest.json](manifest.json) | 文件大小和 SHA-256，用来确认文件有没有被改过 |

JSON 是机器存的结果，PNG 是截图，XML 是当时的界面文字和控件。账号密码、访问令牌、模型密钥都不在交付材料里。

## 看截图前先知道这几件事

主线那次的目标日是 10 月 10 日，独立的“首次方案拒绝”测的是 10 月 11 日。两个账号的画面不是一条连续操作，别拼起来讲。

03、13、15、22 里有几张截图截在“处理中”，说明不了最终结果已经显示。04 是课程冲突的选择，22b 才是完整重排方案。20 是切换输入模式之后的旧画面，新活动对应的是 20b。保存到底有没有发生，得看对应的接口结果，不能只看画面。

已请假的课程在 API 里还留着原记录，只是日程界面把那一节藏了。界面上少一门课，不等于软件删了整门课程。

## 想自己再跑一遍

先照[部署说明](../../../部署与维护.md)把依赖装好，然后用本机的 8874 端口和一个新的临时 SQLite。脚本会自己建合成账户，别改成连正式数据服务。走真实模型的那几个用例要配好模型密钥，会真的调模型、真的花钱。

在仓库根目录开 PowerShell 起隔离服务：

```powershell
.\services\api\.venv\Scripts\python.exe .\scripts\app_flow_qa_server.py --data-dir .\output\verification\aic-repeat\runtime --port 8874
```

另开一个终端跑后台用例：

```powershell
.\services\api\.venv\Scripts\python.exe .\docs\参赛资料\验证证据\aic-20261009\scripts\backend_cases.py --execute-local --database .\output\verification\aic-repeat\runtime\qa.sqlite --output .\output\verification\aic-repeat\backend
```

不加 `--execute-local` 的话，这个脚本只打印、不发业务请求。别的参数用 `--help` 看。新结果往新目录写，这一批原始结果别覆盖。

UI 那个工具是一步步操作当前可见界面的，不是一键重跑全部场景的脚本。它只对 QA 包生效。里面那个中文输入工具只是往输入框里写字，不代表语音识别也测过了。

这些测试没测真人效率、总体识别准确率、Release 性能。文件多、检查条目多，也不等于独立功能就有那么多。
