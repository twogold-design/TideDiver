# 验证记录

## V0.6 九种鱼模型与渔猎接入（2026-10-23）

最终完整运行 `Test.cmd`，十套测试共 **748项通过**：22进度数据、59餐厅数据、52潜水集成、53餐厅流程、61布局规则、165布局流程、103家具目录、51重新开始、55生活世界、127渔猎。全部使用项目指定 Godot 4.7.2，图形套件使用 NVIDIA GeForce RTX 3060 Ti / OpenGL Compatibility。

- 九种鱼已接入独立轮廓与部件，包括灯笼诱饵、河豚棘刺、狮子鱼扇鳍、海鳗关节和灰礁鲨吻部。河豚护甲、海鳗摆动与鱼尾动画由实际状态驱动。
- 渔猎专项验证实际射击与九鱼捕获、20米距离边界、规范价值/重量、重复捕获保护、九鱼入库/出售/救援、独立JSON重载和旧档迁移。
- 实测慢游/冲刺警觉、附近鱼受惊、河豚膨胀与4秒脆弱窗口、海鳗/灰礁鲨预警和固定方向冲刺、伤害冷却、狮子鱼中毒与到期、暂停和再次出航清理。
- 增补实体遮挡测试：隔墙不能射中、捕食者不能隔墙发现玩家、长步长冲刺被墙截停、毒棘不能隔墙扣氧；命中的捕食者可在普通警觉距离外反击。
- 实测千米边界、249条鱼、六点海床高度与物理射线一致；实际仓库翻页/出售按钮覆盖三页11种物资。

修复旧潜水测试：原救援测试坐标位于新海床内部，导致位置修正后深度不再是26米；将测试放到开放水域，仍断言精确深度与捕鱼记录，未放宽验收标准。

已生成并实际查看 [九鱼模型](../artifacts/fish_catalog.png)、[渔猎界面](../artifacts/hunting_hud.png)、[仓库第二页](../artifacts/warehouse_new_fish.png)。确认120米深度尺、猎物耐久、低氧/攻击/中毒提示与翻页按钮可读、无主要重叠。截图为隔离进度下的展示布置，未进行长时间人工游玩平衡测试。

完整回归前后玩家 `saves/progress.json` 的 SHA256 均为 `ED95D0A7F8106DBB6E60AAD3406EBCD97DB3190E367028415888A095ADBC43AA`。应用数据、缓存、临时文件、截图和日志均写入M盘项目目录，测试存档位于 `tests/temp/`。Git保留模型、测试、文档及三张检查截图，不提交玩家存档和运行数据。以下保留开发中快照及旧版本记录。

## 开发中快照记录（2026-10-23，已由上方最终回归取代）

本次 Git 快照保存家具扩展、角色反馈、重新开始游戏，以及进一步扩大海域和九种鱼的未完成开发进度。当前海域配置为 1000×1000 米；九种鱼数据、仓库分页与部分渔猎逻辑已写入，独立鱼类模型及完整渔猎验收仍待完成。下方 V0.5 的通过记录属于此前版本，不能作为当前快照全套通过的证明。

最近运行 `Test.cmd`：进度数据 22 项通过，餐厅数据 59 项通过；潜水集成 52 项中 51 项通过，`Rescue records depth and fish statistics` 失败。脚本在该失败处退出，后续套件（包括渔猎测试）此次未执行。此快照尚未达到全套验证通过状态。

项目文件和本次运行数据保存在 M 盘项目目录；玩家存档、引擎缓存、临时目录和测试日志不纳入 Git。

## V0.5 角色反馈与扩展海域（2026-10-22）

九套测试的最新结果共 **621项通过**：22+59+52+53+61+165+103+51+55。完整Test.cmd执行前七套通过；新游戏测试发现旧人口数断言仍写33条鱼/11个采集点，更新为共享海域契约后单独重跑51项通过；生活世界集成最终重跑55项通过。

新增 `tests/test_living_world.gd` 并接入Test.cmd，实际检查：

- 六个外海目的地拥有真实鱼群与资源，四个远角海底有实体碰撞；四向移动边界使用共享范围，远处珍珠可实际采集。
- 主厨待机→制作→待出餐与真实关节变化、顾客关节活动；潜水/营业暂停冻结玩家、鱼群、主厨、顾客与离席反应。
- 及时上菜、等待较久、超时和提前打烊分别产生对应评价；重复上菜或结算不重复收入或评价。
- 当场最近3条反馈、账单分类计数、独立JSON保存加载；下场营业与新游戏清空旧反馈、反应角色与状态。

额外工程检查（不计入621项套件总数）：扩大海床、六区地标、24个远海采集点未埋入实体等70项几何检查通过；新旧V4账单及反馈保护8项审核通过。审核曾发现外海鱼群和水母穿入岩柱，已改为经验证的开放水域生成点；90条外海鱼121秒轨迹采样未发现进入实体，6个新增水母出生点均不在实体中。日志分别为 `artifacts/ocean-geometry-tests.log`、`ocean-population-review.log` 和 `feedback-review.log`。

真实图形后端已查看 `artifacts/living_service.png`、`feedback_bill.png`、`outer_ocean.png`：主厨料理、顾客催单与持盘品尝、正确上菜按钮、三类账单统计和建议、导航与深度尺互不遮挡。这里是程序驱动的图形检查和姿态测试，不等于长时间人工游玩或专业骨骼动画制作。

玩家真实存档开发前后SHA256一致，记录为 `.runtime/living-world-save-baseline.json` 与 `living-world-save-after.json`。所有引擎运行显式将应用数据、临时目录和日志重定向至M盘项目内。以下保留早期版本的验证记录。

验证日期：2026-10-22（V0.4最终回归；保留V0.2/V0.3历史证据）。引擎：指定的 Godot 4.7.2，Windows / OpenGL Compatibility；实际图形后端为 NVIDIA GeForce RTX 3060 Ti。

## 重新开始游戏验证

在码头与潜水暂停菜单加入“重新开始游戏”。只在点击“确认重新开始”后清空进度并保存新周目；取消和Esc不改旧档，Enter不默认确认。存档写入失败时保留原内存进度并在确认页显示错误。

`tests/test_new_game.gd` **51项通过**，涵盖全字段恢复初始值、独立文件重开后再次加载、主档损坏时备份仍为新周目、非法路径失败、取消与确认保护、暂停中重开、装修瞬态清理、返回旧店和再次潜水。测试只使用内存进度与 `tests/temp/new_game.json`，不重置真实玩家档。

本轮最终完整执行Test.cmd八套 **566项通过**：22+59+52+53+61+165+103+51。原V0.4的515项保持通过，新日志为 `artifacts/new-game-tests.log`。已实际查看 `artifacts/new_game_confirmation.png`，确认重置范围、覆盖存档说明及取消/确认按钮清晰。玩家存档前后校验一致，记录保留在 `.runtime/save-before-new-game.json` 与 `.runtime/save-after-new-game.json`。

以下V0.4记录保留此前家具版本的详细验证范围。

## V0.4 已执行验证

最新七套测试合计 **515项通过**，覆盖潜水回归、仓库、装修、餐厅营业、自由布置与持久化。测试是程序驱动的实际场景和数据检查，不等同于长时间人工游玩。

| 套件 | 结果 | 最新实际日志 |
| --- | --- | --- |
| 进度、升级与返航 | 22 项通过 | `artifacts/progression-tests.log` |
| 餐厅经济、存档与救援 | 59 项通过 | `artifacts/restaurant-tests.log` |
| 潜水实际图形回归 | 52 项通过 | `artifacts/integration-display-test.log` |
| 餐厅实际场景与界面流程 | 53 项通过 | `artifacts/restaurant-flow-tests.log` |
| 家具、放置规则与旧布局兼容 | 61项通过 | `artifacts/layout-tests.log` |
| 自由布置实际场景与鼠标流程 | 165项通过 | `artifacts/layout-flow-tests.log` |
| 十五款家具目录、V4存档与扩大边界 | 103项通过 | `artifacts/furniture-catalog-tests.log` |

先执行Test.cmd全套424项并通过，随后仅扩展和重跑布局流程：增加十五款真实商店按钮/收纳列表回调90项，以及旋转撤销预览同步1项，布局流程最终165项通过。以上七份标准日志合计最新515项（22+59+52+53+61+165+103），不累计中间复跑次数。V0.3的294项为历史版本结果，不与本次计数累加。

实际验证包含：

- 正常返航入库且不加钱、货物不能重复入库、单件/全售/贵重物交易、失氧救援35%取整。
- 从0金币开始，带回12kg货物，出售筹得226G，用210G修复基础店面，再备菜、接客、制作、上菜和结账。
- 无钱/缺前置/重复装修拒绝；菜单钳制库存、开业预留、重复收入保护和提前打烊退料。
- 三种菜3/4/5秒的前后边界；等待、制作中和待上菜各阶段的超时；软装实收46/79/132G。
- 2/4个实际三维顾客，扩座拒绝第5位并发顾客；8客目标自动打烊并退回多余备料。
- 暂停15秒不推进制作、耐心或迎客计时；当日禁止重复开业，再潜水返航后允许营业。
- V1/V2/V3旧档保留原有进度，V4保存家具款式、配色和墙地板样式；缺少款式的旧家具迁移为basic；已有装修补齐对应赠品；独立文件写入/备份与损坏档回退；营业中断只退未分配食材，不重复收入或退款。
- 潜水相机、鼠标捕获、鱼叉遮挡、真实海床碰撞、采集、氧气、暂停和再次出航回归。
- 自由布置的非持久化草稿、取消回滚、购买保存只扣一次、0.5格吸附、非法落点不改原位、旋转/配色/收纳/撤销和默认还原守恒。
- 真实相机投影与鼠标点选/放置、侧栏不误放、桌下地毯及优先选桌、R/G/Delete/Ctrl+Z/Esc输入；至少1桌开业，顾客使用自定义桌位和朝向。

逐条验收方法、证据与验证边界见 [RESTAURANT_ACCEPTANCE.md](RESTAURANT_ACCEPTANCE.md)。尚未逐项人工点击所有六种装修，也未人工关闭正在营业的窗口后重启；相关逻辑由自动测试、独立文件恢复测试与代码检查覆盖，不能把它们描述为已人工演练。

- 五类十五款的价格、资金不足、独立文件存读和款式兼容；main三档购买取消不扣真金币，保存一次合计扣370G，重载不丢失variant。
- 五类十五款逐一触发真实商店Button.pressed，检查新增kind/variant/数量、准确草稿价格；“我的家具”ItemList逐款显示具体名称并经item_selected选择正确UID，逐次取消不动真实内存进度或保存次数。
- 旋转后撤销再按G，预览角度与恢复的家具角度一致。
- 新增地面(9,7.5)真实鼠标投影放置；两种新视口边界、Tab折叠、中键平移与区外释放、相机移动范围、滚轮和F回中，均不改家具草稿。

## 实际查看的画面

V0.4最终实际查看 [家具与商店总览](../artifacts/furniture_collection.png) 和 [折叠侧栏近景](../artifacts/furniture_detail.png)。前者展示单左栏、家具分类、三维商品预览和扩大地面；后者移开桌下地毯以对比十五款模型。桌椅、花器、地毯纹样、灯具与展柜细节可辨，中文及价格无主要重叠。沙地/台面曝光与木纹已调整；当前为原创低多边形视觉。

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

数据测试使用内存对象或 `tests/temp/` 内独立存档及其备份/临时文件；真实场景测试在启动前替换内存进度；截图与 smoke 入口在读取存档前禁用持久化。

V0.4最终运行的 `.runtime/save-before-v04.json` 与 `.runtime/save-after-v04.json` 记录相同真实玩家存档SHA256：

```text
24C31E088ED5792EA0F1C5BA089F1ED84173B4885FEE8DD103540116B55C9844
```

V0.3历史运行的 `artifacts/save-before-layout.json` 与 `artifacts/save-after-layout.json` 记录相同真实玩家存档SHA256：

```text
53E463C3D2875E01ACAFFEF9781080B6A753212CDD6A1811254CB8AEF6B08B4C
```

V0.2历史运行的 `artifacts/save-before-restaurant.json` 与 `artifacts/save-after-restaurant.json` 当时的SHA256同样一致：

```text
C308DBE4A637158FDE06180099F3DAE1C0843CAB482E582AAE22D40F76A79F5B
```

启动器将应用数据、引擎缓存与临时目录指向项目 `.runtime/`；导入缓存 `.godot/`、存档 `saves/`、日志与截图 `artifacts/` 均保留在项目内。

## 复现

双击 **Test.cmd** 运行当前测试套件。图形测试会短暂开启窗口并自动关闭；入口会统一将最新结果写入 `progression-tests.log`、`restaurant-tests.log`、`integration-display-test.log`、`restaurant-flow-tests.log`、`layout-tests.log`、`layout-flow-tests.log` 和 `furniture-catalog-tests.log`。

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
Launch.cmd -- --capture-furniture
Launch.cmd -- --capture-furniture-closeup
```

这些入口使用演示进度，生成对应截图后自动退出，不加载或修改玩家档。潜水截图入口仍为 `--capture-dock`、`--capture`、`--capture-deep`。

## 环境备注

部分运行日志包含 Godot 无法读取 Windows 根证书库的环境提示；项目无联网功能，测试已实际完成并输出PASS。它不替代对脚本错误的检查。当前交付仍使用指定的本地引擎运行，未制作独立安装包。
