# 验证记录

验证日期：2026-10-22（V0.3最终回归；保留V0.2历史证据）。引擎：指定的 Godot 4.7.2，Windows / OpenGL Compatibility；实际图形后端为 NVIDIA GeForce RTX 3060 Ti。

## V0.3 已执行验证

最新六套测试合计 **294项通过**，覆盖潜水回归、仓库、装修、餐厅营业、自由布置与持久化。测试是程序驱动的实际场景和数据检查，不等同于长时间人工游玩。

| 套件 | 结果 | 最新实际日志 |
| --- | --- | --- |
| 进度、升级与返航 | 22 项通过 | `artifacts/progression-tests.log` |
| 餐厅经济、存档与救援 | 59 项通过 | `artifacts/restaurant-tests.log` |
| 潜水实际图形回归 | 52 项通过 | `artifacts/integration-display-test.log` |
| 餐厅实际场景与界面流程 | 53 项通过 | `artifacts/restaurant-flow-tests.log` |
| 家具、放置规则与V3存档 | 61项通过 | `artifacts/layout-tests.log` |
| 自由布置实际场景与鼠标流程 | 47项通过 | `artifacts/layout-flow-tests.log` |

最终已重新执行 Test.cmd，以上六份标准日志对应本次最新结果（22+59+52+53+61+47）。

实际验证包含：

- 正常返航入库且不加钱、货物不能重复入库、单件/全售/贵重物交易、失氧救援35%取整。
- 从0金币开始，带回12kg货物，出售筹得226G，用210G修复基础店面，再备菜、接客、制作、上菜和结账。
- 无钱/缺前置/重复装修拒绝；菜单钳制库存、开业预留、重复收入保护和提前打烊退料。
- 三种菜3/4/5秒的前后边界；等待、制作中和待上菜各阶段的超时；软装实收46/79/132G。
- 2/4个实际三维顾客，扩座拒绝第5位并发顾客；8客目标自动打烊并退回多余备料。
- 暂停15秒不推进制作、耐心或迎客计时；当日禁止重复开业，再潜水返航后允许营业。
- V1/V2旧档保留原有进度，V3保存家具、配色和墙地板样式；已有装修补齐对应赠品；独立文件写入/备份与损坏档回退；营业中断只退未分配食材，不重复收入或退款。
- 潜水相机、鼠标捕获、鱼叉遮挡、真实海床碰撞、采集、氧气、暂停和再次出航回归。
- 自由布置的非持久化草稿、取消回滚、购买保存只扣一次、0.5格吸附、非法落点不改原位、旋转/配色/收纳/撤销和默认还原守恒。
- 真实相机投影与鼠标点选/放置、侧栏不误放、桌下地毯及优先选桌、R/G/Delete/Ctrl+Z/Esc输入；至少1桌开业，顾客使用自定义桌位和朝向。

逐条验收方法、证据与验证边界见 [RESTAURANT_ACCEPTANCE.md](RESTAURANT_ACCEPTANCE.md)。尚未逐项人工点击所有六种装修，也未人工关闭正在营业的窗口后重启；相关逻辑由自动测试、独立文件恢复测试与代码检查覆盖，不能把它们描述为已人工演练。

## 实际查看的画面

V0.3已实际查看 [自由布置画面](../artifacts/restaurant_layout_custom.png)：默认缩放25完整显示可布置地面，左侧五家具商店说明不重叠，右侧收纳列表、配色/墙地板操作与顶部保存/取消均可读。草稿余额与本次新增支出清晰；截图不代表已人工拖放每种家具。

所有以下餐厅图片均已实际查看，尺寸1280×800，由1440×900设计界面缩放；中文和按钮无主要溢出，场景与界面状态对应。

| 图片 | 核对内容 |
| --- | --- |
| `artifacts/restaurant_old.png` | 0G、空仓库、破旧地板与杂物、缺钱及前置原因 |
| `artifacts/restaurant.png` | 厨房、四组座位、招牌、绿植/地毯/灯串与装修栏 |
| `artifacts/restaurant_menu.png` | 三种菜、库存、份数加减和开业按钮 |
| `artifacts/restaurant_service.png` | 四位顾客、三种菜、耐心、制作倒计时、含小费46G上菜按钮 |
| `artifacts/restaurant_bill.png` | 收入336G、满意4位、流失0、退库1份与关闭按钮 |
| `artifacts/return_inventory.png` | 正常返航0G、5件入库、五种货物分两行明细与餐厅入口 |

潜水历史图形产物为 `artifacts/dock.png`、`gameplay.png`、`deep.png`；V0.1原有51项显示后端检查现已被52项潜水回归更新。

## 玩家存档与路径

数据测试使用内存对象或 `tests/temp/restaurant_v2.json`、`tests/temp/layout_v3.json` 及其备份/临时文件；真实场景测试在启动前替换内存进度；截图与 smoke 入口在读取存档前禁用持久化。

V0.3最终运行的 `artifacts/save-before-layout.json` 与 `artifacts/save-after-layout.json` 记录相同真实玩家存档SHA256：

```text
53E463C3D2875E01ACAFFEF9781080B6A753212CDD6A1811254CB8AEF6B08B4C
```

V0.2历史运行的 `artifacts/save-before-restaurant.json` 与 `artifacts/save-after-restaurant.json` 当时的SHA256同样一致：

```text
C308DBE4A637158FDE06180099F3DAE1C0843CAB482E582AAE22D40F76A79F5B
```

启动器将应用数据、引擎缓存与临时目录指向项目 `.runtime/`；导入缓存 `.godot/`、存档 `saves/`、日志与截图 `artifacts/` 均保留在项目内。

## 复现

双击 **Test.cmd** 运行当前测试套件。图形测试会短暂开启窗口并自动关闭；入口会统一将最新结果写入 `progression-tests.log`、`restaurant-tests.log`、`integration-display-test.log`、`restaurant-flow-tests.log`、`layout-tests.log` 和 `layout-flow-tests.log`。

通过 **Launch.cmd** 启动游戏，**Editor.cmd** 打开编辑器。需要生成隔离进度截图时，可在项目目录运行：

```text
Launch.cmd -- --capture-old-shop
Launch.cmd -- --capture-restaurant
Launch.cmd -- --capture-menu
Launch.cmd -- --capture-service
Launch.cmd -- --capture-bill
Launch.cmd -- --capture-return
Launch.cmd -- --capture-layout
Launch.cmd -- --capture-layout-custom
```

这些入口使用演示进度，生成对应截图后自动退出，不加载或修改玩家档。潜水截图入口仍为 `--capture-dock`、`--capture`、`--capture-deep`。

## 环境备注

部分运行日志包含 Godot 无法读取 Windows 根证书库的环境提示；项目无联网功能，测试已实际完成并输出PASS。它不替代对脚本错误的检查。当前交付仍使用指定的本地引擎运行，未制作独立安装包。


