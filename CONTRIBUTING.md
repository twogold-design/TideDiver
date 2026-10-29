# 协作开发

## 第一次打开

1. 安装 **Godot 4.7.2 标准版**，使用 `src/project.godot` 打开工程。浏览器版本使用 GDScript，不需要 .NET。
2. 安装 **Node.js 20 或更高版本**。运行 `npm ci` 安装锁定版本的浏览器测试工具。仅预览已有网页时无需安装 npm 依赖。
3. 设置 `GODOT_BIN` 为本机 Godot 可执行文件，或向 `BuildWeb.cmd` / `Test.cmd` 传入 `-Godot`。项目已附带匹配的 Web 模板。
4. 直接双击根目录 `index.html` 试玩，或运行 `npm start` 并打开 `http://127.0.0.1:8060/` 验证网站模式。首屏点击“启程”即可开始。游戏支持电脑键鼠，浏览器需要 WebGL 2。

仓库从旧桌面工程迁移后，游戏入口现在位于 **`src/project.godot`**。请在合并前提交或暂存自己旧路径下的修改，再将玩法改动应用到 `src/scripts/` 对应文件。

## 修改位置

| 工作 | 路径 |
| --- | --- |
| 主流程、潜水、鼠标和自由镜头 | `src/scripts/main.gd` |
| 鱼群、鱼钩、海底与地形 | `src/scripts/fish_*`、`harpoon.gd`、`ocean_*`、`canyon_art.gd` |
| 埋沙鳐鱼、中空沉船与局部生态 | `src/scripts/ray_*`、`explorable_wreck.gd`、`wreck_fish_school.gd`、`thresher_shark.gd`、`stonefish_*` |
| 海床小动物、珊瑚鱼群和呼吸气泡 | `src/scripts/marine_life*`、`reef_fish*`、`coral_garden.gd`、`diver_bubbles.gd` |
| 环礁地貌、贝床与水流植物 | `src/scripts/atoll_art.gd`、`reef_vegetation.gd`、`ocean_config.gd` |
| 餐厅经营和数据规则 | `src/scripts/progression.gd`、`cuisine.gd`、`customer_feedback.gd` |
| 家具和角色模型 | `src/scripts/furniture_art.gd`、`restaurant_person.gd`、`diver_art.gd` |
| 游戏内界面 | `src/scripts/hud.gd`、`restaurant_ui.gd`、`layout_ui.gd` |
| 浏览器行为 | `src/scripts/web_platform.gd` |
| 网页加载页、说明、全屏 | `src/web/shell.html` |
| 本地双击资源加载 | `src/web/local-loader.js`、`tools/prepare_local.cjs` |
| 打包与测试 | `tools/`、`src/tests/`、`src/export_presets.cfg` |

改动以源码为准。根目录的 `index.*`、`local-loader.js` 和 `local-data.js` 是生成结果，修改网页时应编辑 `src/web/` 后重新构建。`index.pck`、`index.wasm`、`local-data.js` 发生冲突时，先合并源码，再用统一版本重新导出。

## 提交前

- `BuildWeb.cmd`：从源码重新生成根目录网页文件及双击资源。非 Windows 平台可在 Godot 编辑器中用已有的 Web 预设导出到根目录 `index.html`，然后执行 `node tools/prepare_local.cjs`。此步骤还处理引擎在本地文件模式下的 PWA 探测。
- `Test.cmd`：运行 27 套逻辑和图形回归，包含潜水方向动作、海底细节、潜点扩展、埋沙鳐鱼、沉船实际通行、概率长尾鲨、石头鱼伪装/接触/捕获、深度光照实测、随机宝箱、鱼游动与攻击、海床物种、GM无限气瓶量、呼吸气泡和场景切换；脚本、着色器错误或缺少PASS均会使验证失败。
- 保持预览服务器运行，执行 `npm run test:web`：使用独立浏览器环境验证潜水、暂停、持久化存档、布局操作及餐厅营业。默认使用已安装的 Edge；可设置 `TIDE_BROWSER_CHANNEL=chrome` 使用已安装的 Chrome。
- `npm run test:local`：通过真实 `file://` 地址运行同一套浏览器流程，检查直接打开 HTML、存档重载、声音资源加载，以及没有服务器或网络请求。
- `npm run test:marine`：用实际GM按钮开启/关闭无限气瓶量，读取渲染后的气瓶量条验证开关效果，保存珊瑚、杰克风暴、环礁和呼吸气泡截图，检查脚本和着色器错误。
- `npm run test:resolution`：验证高分屏原生渲染分辨率、全屏、窗口大小变化和屏幕缩放倍率变化；截图保存在工程同级工作目录。
- `npm run test:text`：用本机 Chrome 检查窗口模式下“出发潜水”页，验证画布位置及大小对齐实际像素，并保存中文文字截图供视觉检查。
- `npm run package`：将源码、素材、模板、测试、配置与网页发布文件打成完整工程包；自动检查未压缩与压缩后均小于 200 MB。
- 检查 `git diff`，只提交当前功能的源码、配置、必要素材和重新生成的网页文件。

多人并行修改时，尽量按上表划分文件范围，用功能分支提交；涉及同一份 `main.gd` 或存档结构时，先沟通改动范围。引擎版本升级应同步更新 `src/web/templates/` 并完整回归。

## 数据与提交范围

浏览器存档在站点 IndexedDB 中，不能当作工程素材提交。测试使用独立浏览器上下文或 `src/tests/temp/`。不要提交玩家存档、`.godot`、`node_modules`、本地日志和测试输出；已在 `.gitignore` 和打包过滤规则中排除。

构建运行数据写在工程同级的 `.TideDiver-web-work`，不会进入参赛包。授权文件随工程提供，新增外部素材时需要同时保留其许可及来源。
