# 拾日 · 晴日 v2 界面素材包

给 App 大改版用的完整素材：设计方向、设计变量、可交互原型、效果图、Flutter 参考代码、SVG 插画与图标，以及交给 Codex 的提示词。视觉语言来自新的 App 图标（天蓝→青→薄荷渐变、金色太阳、白色通透底板、柔和波浪）。

## 怎么看
1. **效果图**：`screens/`，2 倍分辨率。
   - `today`、`dawn`、`dusk`、`night`：今日页一天中的四种天空；
   - `today-gap-preview` / `today-gap-saved`：空档"安排这项"的就地预览和保存后；
   - `schedule`、`list`、`detail`：周课表、列表、课程详情；
   - `tasks`、`semester`、`assistant`：任务、学期、助手；
   - `board-components`、`board-motion`：组件板和动效板。
2. **可交互原型**：用 Chrome 打开 `prototype/index.html`。
   - 每台手机都能点：切换页签、勾选完成、"安排这项"、点课程块进详情、点胶囊开助手、确认添加、按住麦克风；
   - 顶部滑块可以拖动"今日时间"，看天空变化；
   - "组件 / 动效"两页可以逐个播放动效。
3. **矢量资源总览**：`assets/preview.png`。
4. **Flutter 组件实拍**：`flutter/previews/`。

## 目录
| 路径 | 内容 |
|---|---|
| `DESIGN.md` | 设计规范：现状诊断、方向、色彩、字体、材质、动效（12 个编排模式）、组件、页面蓝图、插画与图标、护栏、验收 |
| `tokens/tokens.json` | 设计变量，唯一的数值来源 |
| `prototype/` | 原型（styles.css 就是可运行的视觉规范） |
| `screens/` | 原型渲染图 |
| `flutter/` | Flutter 参考实现（analyze 0 问题，渲染测试通过）及接入说明 |
| `assets/` | 13 张插画、30 个图标、品牌标志、太阳/月亮/波浪，以及生成脚本 |
| `CODEX-PROMPT.md` | 交给 Codex 的改版提示词 |

## 和现有规范的关系
`design-system/shiri/MASTER.md` 里的产品规则、数据语义、无障碍底线**继续有效**。v2 只替换外观、布局和动效。
