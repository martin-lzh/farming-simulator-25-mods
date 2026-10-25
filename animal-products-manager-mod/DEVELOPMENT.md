# 开发与验收

## 当前验收状态

面向 PC 版 FS25 1.25.0.0，modDesc descVersion 114。玩家 README 只写功能和操作；验收状态集中记录在这里。

- 0.1.2.0 核心逻辑：用户于 2026-10-18 实测确认通过。
- 0.1.3.1 单弹窗显示和修改：用户实测确认通过。
- 0.1.3.3 按活动产品筛选：维护者安装后反馈“没什么问题了”，未提供逐项记录。
- 1.0.0.0 英文界面：维护者 2026-10-18 游戏内截图确认入口和弹窗显示正常（更名前的构建 4c9df07）；其余 26 种语言的游戏内文字和布局未逐一复测。
- 1.0.0.0 全面更名（ZIP、specialization、存档字段、事件和界面 ID）：维护者 2026-10-18 游戏内测试反馈“没问题”，未提供逐项记录。
- 1.0.0.1（新图标、ModHub 描述、移除 pcall）：维护者 2026-10-18 游戏内测试反馈没有问题，未提供逐项记录。
- 联机：10 组离线模拟通过，真实双机验收待执行（步骤见“同农场经理同时操作”）。
- 存档回读、联机客户端、第三方畜舍及其他自动出售/分配 Mod 的组合：尚无逐项测试记录。
- 1.0.0.4 分配挡位拆分（见下节）：维护者 2026-10-25 确认已实机测试，未提供逐项记录。

## 分配挡位拆分（1.0.0.4）

2026-10-25：维护者批准把“分配”拆成两个挡位。版本保持 1.0.0.3，改动记在 CHANGELOG 的 Unreleased；2026-10-25 随 1.0.0.4 发布。

| 值 | 常量 | 界面文字 | 每游戏小时 |
| --- | --- | --- | --- |
| 0 | `KEEP` | 原生 `ui_production_output_storing` | 不变 |
| 1 | `SELL` | 原生 `ui_production_output_selling` | 不变 |
| 2 | `DISTRIBUTE_STORE` | Mod 文本 `apm_mode_distribute_store` | 先分配；剩余按原生方式储存 |
| 3 | `DISTRIBUTE_SELL` | Mod 文本 `apm_mode_distribute_sell` | 先分配；剩余（畜舍库存加恢复缓冲）按出售挡位价格卖出 |

值 2 沿用旧“分配”的存档值，旧存档自动成为“剩余自动储存”。挡位 3 在同一个 source 上先 `APMDistribution.distribute` 再 `APMDistribution.sell`，价格为 `getPricePerLiter × ProductionPoint.DIRECT_SELL_PRICE_FACTOR`，记账类型 `MoneyType.SOLD_PRODUCTS`，与挡位 1 共用同一个出售函数；没有接收生产点时 distribute 返回 0，全部出售；价格为 0 或非有限值时剩余继续隐藏，下一小时重试（与挡位 1 相同）。

### 挡位 2 的剩余

- 液体（牛奶）：分配后调用 `source.restore()`，把恢复缓冲放回畜舍储罐；储罐本来就是原生储存，余量留在原地。储罐放不下的部分照旧留在恢复缓冲，下一小时继续处理。
- 托盘类产品：对照本机 1.25 `PlaceableHusbandryPallets.lua` 与 `PalletSpawner.lua`。`updateOutput` 每帧把产量加进 `pendingLiters` 并调用 `updatePallets`；`updatePallets` 在 `numSpawnsPending == 0` 且某物料 `pendingLiters > 5` 时调用 `getOrSpawnPallet`。找到未满的现有托盘或达到托盘上限时回调同步执行，否则在之后几帧异步执行。`getPalletCallback` 读取回调时刻的全部 `pendingLiters` 填入托盘，按实际填入量扣减，剩余仍大于 5 时再次调用 `updatePallets`。
- 因此新增每个物料的“已放行量” `apmState.released[fillType]`（仅服务端使用）。小时结算中，挡位 2 分配并 restore 后，把当时剩余的全部 `pendingLiters` 记为放行量；大于 5 时在结算标记清除后调用一次 `self:updatePallets()`，由原生代码生成托盘。
- `withStoredPalletsHidden` 的隐藏规则：储存挡位不隐藏；挡位 1、3 隐藏全部 pending；挡位 2 只隐藏 `pending − min(pending, released)`，即放行量保持可见，之后的产量继续隐藏，直到下一小时分配。地上或车上已有的托盘不参与分配（原生 pending 之外）。
- 记账不按“消耗多少减多少”，而是在每层调用结束、放回隐藏量之前执行 `clampReleased`：`released = min(released, 当前 pending)`。这时 pending 只含可见部分，原生只会从可见部分取货，所以剩下的可见量就是剩下的放行量。嵌套的同步回调每层都做同样的截取，外层不会重复扣减；回调期间其他代码新增的 pending 不会被算成放行。浮点残量（例如 1e-12）可能留在放行量里，低于原生 5 L 阈值，无害，下一小时随新产量重新计算。
- 下一小时挡位 2 先对全部 pending 分配（包括还没变成托盘的放行量，例如出生点被挡或达到托盘上限时），再重新设置放行量，不会重复计数。
- 调用被错误中断时，`recoverAbortedCalls` 在放回隐藏量之前同样执行 `clampReleased`，再按原逻辑把隐藏量放回 pending（或保存时放进恢复缓冲）。最多多放行中断后同一帧新增的产量，只发生在错误路径上。

### 挡位切换与易主

- `applyMode` 只要挡位实际改变就清除该物料的放行量：切到 1/3 时全部 pending 由出售处理；切到储存时原生本来全部可见；从其他挡位切到 2 时，放行要等到它自己的下一小时结算。重复设置同一挡位不清除。
- 易主时 `modes` 与 `released` 一起清空，服务端照旧调用 `updatePallets` 让积压按储存生成托盘。
- 切回储存时恢复缓冲照旧在下一小时返还。

### 存档与网络

- 存档：`product(?)#releasedLiters`（FLOAT，已注册到 schema）只在挡位 2 且放行量大于 0 时写入，写入值截取到当前 pending。原生 `pendingLiters` 照旧单独保存并且已经包含这部分，所以放行量只是“允许变成托盘”的上限，不是额外库存，不会重复计数。读取时只接受挡位 2 的有限正值；使用时始终截取到 pending，因此与原生读取顺序无关。旧版本 Mod 读取时忽略这个属性；旧存档没有它，挡位 2 的积压在载入后的第一个小时先分配，剩余随后生成托盘（CHANGELOG 已向玩家说明）。
- 网络：加入同步和 `APMModeEvent` 仍用 2 bit 传挡位，3 正好装得下，格式不变。放行量只在服务端使用，不同步。旧版本客户端的 `isMode` 不接受 3，会在本地显示为储存；README 已要求所有玩家使用同一版本。

### 界面与本地化

- 弹窗第 1、2 项继续使用原生翻译，第 3、4 项为新增的 `apm_mode_distribute_store` / `apm_mode_distribute_sell`，按 `g_i18n:getText(key, modName)` 读取（与 `apm_title` 相同）。27 个语言都已补齐：简体中文按维护者指定为“分配，剩余自动储存 / 分配，剩余自动出售”，英文保留维护者文案，其他语言以各自原生“分配”译名开头。`apm_explanation` 与 27 种 modDesc 简介同步改为四种挡位。
- 原生 `fs25_multiTextOptionText` 为 16px、大写、单行、仅聚焦时滚动。名称更长后，挡位选择框从 350px 加宽到 430px，产品名从 330px 缩到 290px（行宽 760px 内仍有间距）。区分两种分配的词位于文字前部，未聚焦时即使被截断也能分辨；各语言实际显示需在游戏里检查。

### 验证（2026-10-25）

- 新增/修改行为测试：`isMode` 只接受 0–3；挡位 3 先分配再出售剩余和恢复缓冲；无接收点时全部出售（托盘与牛奶）；零价保留；挡位 2 牛奶余量和缓冲留在储罐；挡位 2 托盘放行量对原生可见而后续产量隐藏，异步回调逐步消耗；旧存档积压先分配；嵌套同步回调只扣一次；中断调用后的放行量（下一帧与保存两种收尾）；挡位切换/易主清除放行量；放行量保存、读取、截取和忽略非挡位 2 的值；挡位 3 的加入同步与事件。多人模拟新增挡位 3（40 L 工厂、其余出售）。75 项行为测试、11 组多人模拟通过。
- 六条仓库验证命令均通过（42 项工具单元测试）；5 个脚本通过本机 fs-luau-compile，输出在 `work/validation/luau/`。构建 `outputs/FS25_AnimalProductsManager.zip` 仍为白名单 8 个文件，包内版本 1.0.0.3。未安装构建。

### 游戏内待测

1. 弹窗：四个挡位文字在中文、英文及几种长语言（德语、俄语、越南语）下的显示和截断，键鼠与手柄切换；旧存档中“分配”显示为“分配，剩余自动储存”。
2. 挡位 3：有接收工厂时先送满再出售余量，核对工厂库存、运费和出售收入；无接收工厂时全部出售。牛奶与鸡蛋/羊毛各测一次。
3. 挡位 2 托盘：整点后分配剩余生成托盘；两个整点之间新产量不生成托盘；托盘出生点被挡或达到上限时余量不丢失，下一小时重新分配。牛奶余量留在储罐。
4. 带积压的旧存档（旧“分配”挡位下的鸡蛋/羊毛）：第一个整点先分配，剩余生成托盘。
5. 托盘生成过程中切换 2↔3、2→1、2→储存及易主：无重复产出、负数或库存丢失。
6. 挡位 2 在放行量尚未全部生成托盘时保存、重新载入，确认继续生成且不多出产品；联机主机与客户端各确认一次挡位 3 的同步与结算只发生一次。

## FS25 1.25 接口检查（2026-10-20）

本机日志确认游戏为 1.25.0.0，Steam build 25879111。对照 2026-10-17 留存的 1.24 参考与更新后的安装包，只读游戏目录。官方在线 LuaDoc 此时仍为 1.20，版本差异以随游戏 SDK 和本机脚本为准。完整清单、哈希、差异及反编译材料保存在被忽略的 `work/analysis/update-1.25.0.0/`，新版参考在 `work/reference/1.25.0.0/`，旧版参考保留。

- 官方 SDK Lua：952 → 961 个文件，新增 9、变化 82、删除 0；核心脚本字节码：1,842 → 1,879 个文件，新增 37、变化 173、删除 0。文件变化数不等于接口破坏数。SDK `scriptBinding.xml` 与 `scriptBindingChanges.txt` 均未变。
- `PlaceableHusbandry`、Milk/Pallets、`Storage`、`Farm`、`ProductionChainManager`、经济价格、类型注册、网络节点序列化及主要弹窗控件的字节码未变。`ProductionPoint` 新增输出 XML 的 `isPrimary` 标记，不改变本 Mod 使用的库存、出售比例和运费接口。
- `FSBaseMission` 新增动物雇工系统；`Placeable` 新增删除前消息；`MessageCenter` 修正一次性订阅移除；`FocusManager:removeElement` 改为先清理子元素。未发现这些变化破坏本 Mod 的调用方式。`FocusManager`、`InputBinding` 的反编译全文未通过语法检查，前者以 SDK 完整实现交叉核对；后者的可见差异为手柄方向键常量调整，不能据此声称已验证真实手柄行为。
- 发现菜单冲突：新版 `InGameMenuAnimalsFrame` 在可用时插入 `animalWorkerButtonInfo`，使用 `MENU_EXTRA_1`。原 Mod 固定使用相同 action；在同时支持产品与雇工的畜舍会重复绑定。`Register.lua` 现在检查原生按钮列表：已有 `MENU_EXTRA_1` 时使用 `MENU_EXTRA_2`，否则保持原快捷键。两个 action 均在本机 SDK 中声明。常规无产品马厩不出现本 Mod 按钮；羊驼及第三方混合畜舍的实际行为未验收。
- Mod 版本保持 1.0.0.2，`descVersion` 保持 114；新版接受 90–115，无需仅因上限升高而提高本 Mod 的最低格式要求。27 种简介移除固定 X 键指引，README 指引使用按钮旁显示的键。
- 验证：仓库检查、Python/JSON/XML 语法、CI validate/build、35 项工具单元测试、63 项 Lua 行为测试、10 组多人模拟均通过；5 个 Mod 脚本通过本机 Luau 编译器。新增菜单回归覆盖雇工/产品各自回调、重复刷新、在有无雇工按钮之间切换；存档与网络格式未改。构建仍为白名单内的 8 个文件，SHA256 `b42be60e9027b48086a815f7d499f497ce16dc9944d121e300cd416c481dcb9b`。
- 环境处理：工具单元测试的 TEMP/TMP 指向 `work/validation/tmp`。标准 `uv run animal-products-manager-mod/tests/run.py` 先受缓存写权限及 PyPI DNS 限制；以已有 Lupa 2.6 环境运行 `uv run --offline --no-project --active python animal-products-manager-mod/tests/run.py` 通过，再将已缓存的 Lupa 2.6 复制到工作目录的脚本环境，使标准 uv 命令及完整 `python tools/ci.py build` 也通过。UV_CACHE_DIR 指向 `work/uv-cache`，构建设置 UV_OFFLINE=true。日志在 `work/validation/update-125-*.log`。
- 游戏内验收待维护者执行：1.25 中的菜单、键鼠/手柄、整点出售/分配、保存回读，以及有动物雇工的畜舍两按钮共存。未安装构建、未修改存档、未启动或关闭游戏。

2026-10-20：维护者随后明确要求安装测试包。确认没有 FarmingSimulator 进程后，将原 1.0.0.1 ZIP（SHA256 `0a40347822a35383de7734909ba98528481887f43d50f85b0269aea87924f0be`）备份到 `work/backups/FS25_AnimalProductsManager-before-1.25-test.zip`。写入用户 mods 目录被当前执行环境拒绝，复查原 ZIP 哈希未变，因此安装未完成。Git 暂存同样因 `.git/index.lock` 写权限被拒绝，尚未提交或推送；测试包基于 `e4d5505` 加本次未提交修改，以以上包 SHA256 区分。

2026-10-20 接手复核：维护者确认已自行安装；只读核对 mods 目录中的 ZIP，其 SHA256 与上述测试包及重新构建的包一致。游戏正在运行，未替换文件或操作游戏。重新执行全部六条仓库验证命令均通过（35 项工具测试、63 项行为测试、10 组多人模拟），本次执行无需之前的环境绕行。修复保留在 Unreleased，版本仍为 1.0.0.2，游戏内验收结果待维护者反馈。

## 1.0.0.4 发布准备

2026-10-25：维护者确认“分配”挡位拆分（剩余自动储存／剩余自动出售及旧存档迁移）已实机测试，要求以正式版发布 1.0.0.4，并入 PR #6。本次发布准备只更新版本元数据和文档，脚本与已测构建一致。`release.json` 保持正式版，合并由维护者执行。

## 1.0.0.3 发布准备

2026-10-20：维护者确认 FS25 1.25 修复构建“实测没问题”，要求发布 1.0.0.3 并开 PR 到 main。实测源码对应 `11dffed`，已安装包 SHA256 为 `b42be60e9027b48086a815f7d499f497ce16dc9944d121e300cd416c481dcb9b`（包内版本仍为 1.0.0.2）。本次发布准备只更新版本元数据和文档，脚本与已测构建一致；维护者未另行提供主机/客户端逐项测试记录。`release.json` 保持正式版，合并由维护者执行。

## 构建

从仓库根目录执行：

```powershell
uv run animal-products-manager-mod/tests/run.py
python animal-products-manager-mod/tools/build.py
```

输出 `outputs/FS25_AnimalProductsManager.zip`，由维护者放入游戏 mods 目录，或在维护者明确要求时由代理复制进去。构建不安装、不修改存档，也不启动游戏。ZIP 只含白名单内的 8 个原创文件（modDesc、脚本、GUI 和图标），不含反编译文件、第三方代码、测试依赖或分析材料。

README 截图在 `assets/screenshots/`：维护者 2026-10-18 的游戏内截图（英文界面，FS25 1.24 PC；01 和 03 为 1.0.0.1 构建 d555c5f，02 为 1.0.0.0 构建 4c9df07，顶部性能叠加层已裁掉），原图在被忽略的 `outputs/animal-products-manager/screenshots/1.0.0.0/`，仅缩放到 1600 px 宽并转为 JPEG，未改内容。它们不在 build.py 白名单内，不进 ZIP。

Mod 识别产品依靠原生 milk / pallets specialization 声明的 fillType，不硬编码动物品种。未生成托盘的产量沿用原生 `pendingLiters` 缓冲和存档。

## ModHub 提交准备（Unreleased，计划版本 1.0.0.1）

2026-10-18：维护者要求上架 GIANTS ModHub，指定下一版为 1.0.0.1，由主会话改版本号并发布；在此之前改动记在 CHANGELOG 的 Unreleased，modDesc 保持 1.0.0.0。依据：[ModHub Guidelines - Farming Simulator 25](https://forum.giants-software.com/viewtopic.php?t=209169)（2026-03-19 更新）。

- 图标（fad4089）：`icon_animalProductsManager.dds`，512×512 BC1、单级无 mipmap，与本机 mods 目录中 10 个 ModHub DDS 图标的格式一致；build.py 检查尺寸、无 mipmap 和数据长度。
- modDesc 简介：27 种语言均按 Script Mod 模板写成 CDATA，含“说明 / 快捷键 / GitHub 链接”。入口是动物页面底栏的 MENU_EXTRA_1 按钮（维护者截图显示键盘默认 X）；手柄按键未截图核对，简介写“旁边显示的按键”。挡位、页面和确认按钮名称取自本机 1.24 的 `l10n_*.xml` 原生翻译。
- 标题：TestRunner 要求标题每个单词首字母大写（本机 ModHub Mod 也这样写，如 “Quantum Und TC816”），19 种语言的标题因此改为逐词大写。
- 脚本、GUI、存档和网络格式未改。

官方 TestRunner v0.9.22（GDN downloadId 162，GIANTS Software GmbH 签名，SHA256 `eb557ddfc638f7f9c1a06b0cbfa5e2760909e1ee05e7b9c5c3ab058db3667cad`）放在被忽略的 `work/tools/testrunner/`。本机未装 GIANTS Editor，因此用 `--skipGuiPrograms` 并以占位路径满足 `-e` 参数，跳过只检查 i3d 和着色器的 EditorCheck / ShaderCheckEditor（本 Mod 没有 i3d 和着色器）。只对 `work/validation/testrunner/` 下解压的构建运行，不碰游戏目录。

- 1.0.0.0 发布包基线：ModDescCheck 失败（descVersion、19 个标题大小写、27 个简介无 CDATA、图标 10 级 mipmap 且不叫 icon_*.dds），PublicLuaCheck 失败（8 处 pcall）。
- 7503e25：图标、标题和 CDATA 问题全部消失。
- 之后维护者要求去掉 PublicLuaCheck 标出的 8 处 pcall（AnimalProductsManager.lua 5 处、Distribution.lua 3 处）。改为“先记账、后调用”并按帧号收尾（见“结构”），存档格式和网络事件不变。PublicLuaCheck 通过；构建 SHA256 `5b4400e357bfc7734911710e7814f97e139b9cfe36c2f98e5911a9f34c0efcf6`（版本号仍为 1.0.0.0）。五个脚本用本机 fs-luau-compile 编译通过。脚本行为改变，发布前需维护者在游戏内复测出售、分配、托盘和保存重载。
- 仍剩一项：`descVersion '114' outside allowed range`（min/max 113）。本机 1.24.0.0 的 `main.lua` 中 `g_maxModDescVersion = 114`，TestRunner 0.9.22 的更新记录也写着已升到 114，判断为工具范围未同步；保持 114，在提交备注中说明。

## 1.0.0.2 发布准备

2026-10-18：维护者要求为许可变更发补丁版。1.0.0.2 只改许可（PolyForm Noncommercial 1.0.0）、modDesc 作者名（Zhaohan Liu）和文档，脚本、界面和图标不变。`release.json` 仍为正式版。维护者于 2026-10-19 以脚本、界面和图标未改为由免除此构建的游戏内测试。

## 1.0.0.1 发布准备

2026-10-18：维护者选择按规则发布 1.0.0.1（不替换已发布的 1.0.0.0）。内容：fad4089 无 mipmap 新图标、7503e25 ModHub 详细描述、0f18416 移除 pcall（TestRunner PublicLuaCheck）。descVersion 按维护者决定保持 114。`release.json` 仍为正式版。因脚本行为改变，发布前需维护者在游戏内测试出售、分配、托盘及保存重载。

2026-10-18：按维护者明确要求，在游戏关闭时把 1.0.0.1 构建（提交 d555c5f，SHA256 `0a40347822a35383de7734909ba98528481887f43d50f85b0269aea87924f0be`）复制进 mods 目录，替换此前的图标测试构建（SHA256 `8d287d85…`）。游戏内测试待维护者反馈。

2026-10-18：维护者反馈 1.0.0.1 构建（d555c5f，SHA256 `0a403478…24f0be`）游戏内测试没有问题（此前请其覆盖出售、分配、托盘产品和保存重载，未提供逐项记录）。维护者截图确认：动物页面底栏显示“Product destinations”，牛棚弹窗列出 Milk（Distributing）和 Buffalo Milk（Selling），说明换行正常、箭头未裁切。对应 log.txt 显示载入 Animal Products Manager 1.0.0.1，无本 Mod 的 Lua 错误或调用栈；唯一 Error 为与本 Mod 无关的“Startup with port while already running”。真实双机联机仍未单独验收。

## 1.0.0.0 首次发布

2026-10-18：维护者表示 Mod 可以进入发布流程，指定首个发布版本为 1.0.0.0。`release.json` 改为 `prerelease: false`，以正式版发布；0.1.x 均未在 GitHub 发布，CHANGELOG 中保留为开发历史。相对 dev 上 00d5dc5（含更名后的 0.1.4.0），1.0.0.0 只改版本号、`release.json` 和文档，不改脚本或界面。合并到 `main` 前，维护者需确认已在游戏内测试此构建（以提交和 SHA256 标识）。

2026-10-18：维护者表示 1.0.0.0 已在游戏内测过，要求开 dev → main 的 PR。核对 mods 目录时发现当时安装的是 0.1.3.3（英文名仍为 Animal Product Distribution，SHA256 `c35691443b1377559b9c26a2e03c1437f7d59fe08f49db2b8045eb1d66b0b65b`），因此按维护者明确要求，在游戏关闭时把 1.0.0.0 构建（提交 4c9df07，SHA256 `14388f873019d63b6bf2f957e0bfdb0b287b7c40c63e6f1c1512b6b32f53905d`）复制进 mods 目录替换旧 ZIP，再由维护者复测。

维护者随后提供三张英文界面截图：鸡舍的动物页面底栏显示 “Product destinations” 入口；鸡舍弹窗只列出 Eggs（Distributing）；牛棚混养水牛和奶牛时列出 Milk（Distributing）和 Buffalo Milk（Selling）。说明文字在弹窗内换行，挡位箭头未被裁切。另一张截图显示一处生产点的鸡蛋进料为 2,396 / 2,400 L，与分配挡位一致，但没有记录结算前后的数量和余额。这四张截图的原图复制在被忽略的 `outputs/animal-products-manager/screenshots/1.0.0.0/`，留作上传 Mod 的素材，不提交（含游戏画面）。记录为 1.0.0.0 英文界面实测通过；其余语言、存档回读、结算数量和真实双机联机未在本次截图中覆盖，下方“游戏内验收”清单不据此标为全部通过。

2026-10-18：维护者要求 Mod 名称、文件名和文档统一为 Manager，并选择连同 ZIP 名和存档内部名称一起改（1.0.0.0 尚未发布，此时代价最小）。改名对照：仓库目录与发布标识 `animal-product-distribution` → `animal-products-manager`（标签 `animal-products-manager-v1.0.0.0`）；ZIP `FS25_AnimalProductDistribution.zip` → `FS25_AnimalProductsManager.zip`；specialization `animalProductDistribution` → `animalProductsManager`，类与脚本 `AnimalProductDistribution(.lua)` → `AnimalProductsManager(.lua)`；Lua 前缀 `APD`/`apd` → `APM`/`apm`（含 `APMModeEvent`、`APMProductDialog`、`apmState`、`apm_title`、`apm_explanation` 和弹窗元素 ID）；`releases/` 开发记录文件同步改名。`Distribution.lua` 指分配挡位，不是 Mod 名，保持不变。

影响：FS25 以 ZIP 名识别 Mod，存档中的设置保存在 Mod 名与 specialization 名下。旧测试存档里的挡位不会带到新 ZIP，全部回到储存；旧 ZIP 名下等待恢复的数量也不会转移。测试者需删除旧的 `FS25_AnimalProductDistribution.zip`，放入新 ZIP 后重新设置；两个 ZIP 同时启用会重复注册。脚本行为未改，60 项行为测试和 10 组联机模拟通过；更名后的构建需维护者重新在游戏内确认加载、入口、弹窗、保存和重载。

2026-10-18：按维护者明确要求，在游戏关闭时把更名后的构建（提交 5568b6a，`FS25_AnimalProductsManager.zip`，SHA256 `6fce8dc8eec46bd06657445fcacc2b97d352f973683ec500787f61f5cce9c80c`）复制进 mods 目录；旧的 `FS25_AnimalProductDistribution.zip` 已不在目录中，无需删除。维护者随后反馈已进游戏测试，没有问题。测试那次的 log.txt 已被之后的启动覆盖；之后的日志列出该 Mod（1.0.0.0），没有本 Mod 的错误。逐项结果（单人以外的主机/客户端、保存重载数量）未单独记录。

## 0.1.4.0 本地化

`modDesc.xml` 的 title、description、apm_title 和 apm_explanation 均覆盖本机 FS25 1.24 游戏资源中的 27 个语言代码：en、de、cs、br、ct、cz、da、ea、es、fc、fi、fr、hu、id、it、jp、kr、nl、no、pl、pt、ro、ru、sv、tr、uk、vi。注意 cs 是简体中文，ct 是繁体中文，cz 是捷克语；jp、kr 使用游戏自身代码。地区变体分别保留独立文案。

挡位继续使用原生 ui_production_output_storing、ui_production_output_selling 和 ui_production_output_distributing；产品名称与确认/返回也沿用游戏翻译。无需新增 Lua 逻辑或翻译文件，ZIP 白名单仍为 8 个文件。沿用弹窗的原生文字测量和自动换行；新增语言的实际字体与布局仍需在游戏里切换检查。

2026-10-18：维护者在安装 0.1.3.3 后反馈“没什么问题了”，并要求补齐其他语言。记录为当前测试反馈，不推定所有语言或全部联机角色已逐项验收。本次改动先记录在 Unreleased；0.1.3.3 从未发布，dev 上的 Release plan 因此报错。维护者随后指定本地化作为新版本 0.1.4.0（beta，release.json 保持 prerelease true），0.1.3.3 不单独发布。发布前需维护者在游戏内测试 0.1.4.0 构建并切换语言检查文字和布局。

同版本内维护者要求更换名称：modDesc 的 en 标题、release.json displayName 和日志前缀改为 Animal Products Manager，其余 26 个语言的标题同步改为“产品管理”含义（简体“动物产品管理”、繁体“動物產品管理”）。当时 ZIP 名、目录名、脚本文件名和 specialization 名保持旧名 AnimalProductDistribution，以免存档中的 Mod 设置失去对应；1.0.0.0 发布前已全部改名，见“1.0.0.0 首次发布”。

同版本内按仓库规则重写玩家 README：English 在前、中文在后，各自完整；移除 specialization、pendingLiters 等开发术语和验收状态，改记于本文件“当前验收状态”和“构建”。根 README 同样改为 English 在前。

## 结构

- `scripts/Distribution.lua`：与引擎分离的挡位常量（0 储存、1 出售、2 分配后储存剩余、3 分配后出售剩余）、容量分配和出售结算。
- `scripts/AnimalProductsManager.lua`：畜舍 specialization、原生库存适配、保存、加入同步及按小时处理。
- `scripts/ModeEvent.lua`：客户端请求与服务端权威广播，校验所有权、权限、输出类型和挡位。
- `scripts/ProductDialog.lua`、`gui/ProductDialog.xml`：原生 MessageDialog、ScrollingLayout 和 MultiTextOption 控件组成的单窗口编辑器，暂存选择并统一确认。
- `scripts/Register.lua`：向支持的 placeable 类型追加 specialization，并在动物页面加入操作按钮。
- `tests/`：原创引擎替身及行为测试；不会加载或执行反编译文件。
- `tools/build.py`：白名单打包，不安装。
- `tools/make_icon.py`：用代码绘制原创图标（奶罐、鸡蛋，分叉箭头指向仓库、硬币和工厂三个徽章，对应储存、出售、分配；不使用 AI 生成图像，符合 ModHub 对 AI 图片的禁令）；PNG 制作源保存在 `assets/icon.png`，运行时使用 `icon_animalProductsManager.dds`。按 ModHub 指南的 `icon_*.dds` 命名和“BC1 without mipMaps”要求，使用 Microsoft DirectXTex 的 texconv 生成 512×512 BC1/DXT1、只有一级（`-m 1`）的纹理，`tools/build.py` 检查尺寸、无 mipmap 和数据长度。运行 `uv run animal-products-manager-mod/tools/make_icon.py --texconv <texconv.exe路径>`。默认查找 PATH 或被忽略的 `work/tools/directxtex/texconv.exe`。工具不纳入仓库及安装包。

本机接口核对材料位于被忽略的 `work/analysis/animal-products-manager-api.md`，全部游戏参考留在 `work/`。修改前重新核对目标版本和调用时机，反编译文本中的控制流不能直接复制或作为正确性的唯一依据。

正常库存存储在原生字段，自定义存档记录物料名称、模式、异常返还被拒绝时的恢复数量，以及挡位 2 尚未变成托盘的放行量。初始数据流同步所有模式，后续通过事件更新。只在畜舍完成放置后、原生 onHourChanged 事件中结算；处理中的回调不可再次进入结算。

每小时仅服务端修改库存和农场收支，扣取/接收量通过实际库存变化计算。调用原生 addMoney 时临时替换 `g_messageCenter.publish`：本农场的 MONEY_CHANGED 到达时（原生 `Farm:changeBalance` 已改余额、尚未调用订阅者），先移除替换、记下这次余额变化并完成本次记账，再调用原订阅者；订阅者引起的还贷、借款、嵌套结算及其报错都不计入本次成交。变化小于 1 时原生不发布通知，addMoney 返回后按余额差记账。直接替换入账实现、不经过该通知的第三方逻辑不在这一兼容保证内。

脚本不使用 pcall/xpcall（ModHub TestRunner 的 PublicLuaCheck 要求），游戏或其他 Mod 抛出的错误照常进入日志并中断本次调用。守恒靠“先记账、后调用”：原生 `Storage:setFillLevel` 先改库存再调用监听器，`Farm:changeBalance` 先改余额再发布通知，因此每次调用外部代码前，本 Mod 先按调用成功记下结果，正常返回后再按实际变化修正。取出的产品在售出或送达前一直记在畜舍自己的恢复缓冲（`refundLiters`，随存档保存）里；外部代码报错时，未售出的数量仍属于畜舍，下一小时继续出售/分配，切回储存时返还。处理中标记、托盘隐藏层数和临时余额通知替换都记下当前帧号 `g_updateLoopIndex`；错误越过清理代码后，下一帧的调用（托盘更新、小时结算、余额变化、保存）识别出遗留状态并收尾，被隐藏的托盘库存放回原生 `pendingLiters`，保存时则放进恢复缓冲。

已知取舍：第三方代码若在改动库存或余额之前就报错（原生代码不会这样），本次已按成功记下的数量会丢失；运费在送达之后扣，若接收方监听器在送达时报错，这一次不扣运费。

目标仅部分接收时返还差额，未付运费的交付尝试回退。恢复缓冲按物料名保存，返还后扣除，避免重复恢复；存档所有者赋值和重复的相同所有权通知不会清空模式。已完成加载的畜舍易主后，服务端重置挡位并重新调用原生 updatePallets；客户端和存档加载过程不生成托盘。如果在托盘同步回调中切回储存或易主，在最外层库存隐藏解除后补调原生生成，仍遵守原生大于 5 升的生成阈值。

原生 `ProductionChainManager:distributeGoods()` 同时进行全链路分配、库存写入和扣费，不是只返回数量的工具函数。本 Mod 保留针对畜舍的处理器，没有额外调用当前任务的整个生产链管理器；以原生函数做隔离对照，校验容量比例和原生费率。测试工具及原生函数证据仅保留在 work/。

## 离线验证

运行 `uv run animal-products-manager-mod/tests/run.py`，使用固定版本 Lupa 执行原创 Lua 测试。当前 62 项测试覆盖容量分配、物料守恒、溢出、空接收列表、价格系数、重复结算、托盘异步回调、异常前后实际变更、入账失败、回调重入、恢复数量持久化、模式保存/读取、加载时所有者赋值、加入同步、事件序列化、跨农场请求、权限、客户端不结算、转移所有权及菜单回调。新增回归覆盖同步还贷/借款及其抛错、嵌套通知、其他畜舍和农场结算、拒绝入账、发布函数恢复、易主后的托盘恢复和原生挡位翻译。单窗口回归另覆盖批量修改、取消草稿、仅提交改动行、避免覆盖其他玩家修改的未编辑行、重复确认、权限变化、窗口复用和客户端请求。活动产品回归覆盖山羊/绵羊独立列表、混养及动物变更、奶类子类型零产量、空列表与字段缺失的区别、去重，以及隐藏行的模式/恢复数量持久化、完整加入同步和遗留库存结算。

本机另有 `uv run work/scripts/check_distribution_native.py`：500 组与原生分配方法的数量/余额对照、官方 SDK 托盘方法的 50 轮保存/重载及异步回调核对。该工具仅在提供本机参考资料的工作区可用，全部结果位于 work/analysis/，不打包或提交原生代码。其引擎对象为替身，仍不能替代真实游戏验收。

`uv run animal-products-manager-mod/tests/run.py` 还执行 `tests/multiplayer.py` 的 10 组联机模拟。服务器与两位客户端各用独立 Lua 环境，通过对象 ID 序列化实际 Mod 事件，并控制跨客户端请求的到达顺序。覆盖同产品冲突的两种顺序、不同产品草稿并存、旧草稿覆盖、主机与客户端交错修改、请求在途时权限/农场/对象变化、专用服务器无本地玩家时的出售和分配，以及服务器模式保存回读、加入快照与加入后修改。新增山羊畜舍与绵羊畜舍的不同对象 ID 在双经理事件广播后仍保留各自产品和挡位的回归。去掉 pcall 后，错误路径测试改为让错误传到调用方，并验证下一帧收尾、保存时把隐藏库存放进恢复缓冲、遗留的余额通知替换被移除；62 项行为测试及 10 组联机模拟均于 2026-10-18 通过。

模拟传输采用有序消息队列；权限、引擎对象和经济系统使用替身，不覆盖原生库存网络同步。加入测试只验证静止快照，不模拟引擎暂停、对象创建/确认或真实断线恢复，不能作为双机联机验收通过的依据。

用本机 Luau 编译工具检查五个运行时脚本的语法，输出到 `work/`。这仅验证可解析，不表示能调用游戏引擎。构建脚本验证 XML、引用文件和 ZIP 白名单。

## 同农场经理同时操作

0.1.3.2 按产品接受服务器最后处理的有效设置，没有编辑锁或版本冲突提示。两位同农场经理均有权限；服务器广播也发给请求者，客户端不提前应用请求。不同产品独立修改；弹窗只提交相对于打开时发生变化的行，未修改行不覆盖他人设置。一次确认包含多行时，每行是独立事件，不是整张表的事务。

打开的弹窗保留本地草稿，不随其他经理的修改刷新。重新打开会读取已收到的服务器状态；若两人都实际修改同一行，后到的请求覆盖先到的设置。设置冲突不触发额外小时结算；库存和余额只由服务器处理。

本机 FS25 1.24.0.0 原生流程确认：玩家进入同步阶段时暂停主机，所有同步完成后才尝试恢复。加入快照测试因此不注入同步期间的玩家操作或小时推进，不能把“主机同步期间照常操作”当作已确认的丢更新问题。

双机实测仍待执行，主机和客户端都安装相同版本，并加入同一农场、设为经理：

1. 双方同时打开同一畜舍的产品去向，分别选择同一产品的不同挡位，先后确认；双方重新打开，确认最终均为服务器最后接受的挡位。交换确认顺序再测。
2. 在支持多产品的畜舍分别修改不同行，确认两项都保留；验证未编辑行不会用旧草稿覆盖他人修改。仅一项产品的畜舍可改用不同畜舍验证独立操作。
3. 分别使用出售和分配，在整点前记录畜舍库存、工厂库存和农场余额，整点后核对只有一份成交/交付及对应收入/运费。核算新增产量，排除正常生产对余额和库存的影响。
4. 保存、重新载入并让第二位经理重新加入；等待原生同步结束后，双方重新打开检查挡位和原生库存，随后修改一次确认后续广播正常。检查两端日志。

## 0.1.3.3 活动产品筛选

原生羊/山羊畜舍的托盘配置可以同时声明 WOOL 和 GOATMILK；`fillTypes` 是建筑支持能力，不代表当前动物的产出。原生 milk/pallets specialization 的 `onHusbandryAnimalsUpdate` 根据本畜舍动物群更新 `activeFillTypes`，原生信息界面也使用活动列表。0.1.3.3 菜单和弹窗调用 `APM.products(placeable, true)` 选择活动产品，不读取其他畜舍或农场的产品。

未传入筛选参数的 `APM.products` 仍返回完整支持列表，继续供保存、初始数据流、支持验证和小时结算使用。活动产品为空时不展示入口；字段缺失时对第三方实现保留原兼容行为。字段存在但为空不能回退成全部产品，也不能按当前每小时产量是否大于零筛选，否则幼龄、缺料时无法设置。

已不存在的动物产出仍保留其旧挡位，遗留库存按该挡位处理；这次没有改变结算、存档格式或网络事件格式。隐藏旧行不代表清空它的数据。游戏内需分别用只养山羊、只养绵羊和混养畜舍复测；双方更换相同 0.1.3.3 ZIP 后再验证联机，不能把离线模拟等同实际双机通过。

## 游戏内验收（尚未完成）

1. 在测试存档中启用 Mod，检查日志没有 specialization、XML、事件或菜单错误。确认现有牛棚、山羊棚、鸡舍、羊圈均出现产品去向按钮；其他动物不会出现空入口。检查中文、英文及键鼠/手柄操作。
2. 默认储存：记录产量、储罐和新托盘，与未启用 Mod 的同条件基线比较。取消弹窗不修改模式。
3. 出售：记录结算前后数量、经济价格、余额，在一个游戏小时后核对数量乘原生系数；再过一小时确认旧库存不重复出售。零价时保留库存。
4. 分配：准备同农场乳品厂/纺织厂，分别测试空仓、满仓、多厂不同剩余容量、无接收厂和暂停生产。核对来源减少量等于目标增加量，运费与原生距离费率一致；外农场工厂不应收到货物。
5. 保留地上和车上的既有蛋/羊毛托盘，确认不被抽取；在托盘生成中切换挡位，检查无重复产出、负数或库存丢失。切回储存后让积压正常生成。
6. 保存并退出，再载入；确认不同畜舍的模式和原生库存持久化。禁用 Mod 后确认原生库存可用。不要在未处理完积压时删除畜舍来测试恢复。
7. 多人主机、客户端及专用服务器：新加入同步，授权成员修改模式，未授权成员和其他农场不能修改；只结算一次，所有客户端显示一致。转移所有权应重置模式。
8. 测试第三方畜舍、其他产出自动处理 Mod、不同游戏速度和跨日/月；确认保存、饲料、动物健康和原生产量不受影响。

完成上述步骤并记录游戏日志和数量/余额后，才能宣布游戏内验收通过。

2026-10-18：0.1.2.0 在用户自建多人存档中已加载，用户已打开入口并操作挡位；截至所读日志未发现本 Mod 的 Lua 错误。日志有 PNG 图标性能提示，不能据此判定数量守恒或保存验证通过。0.1.3.0 单窗口界面仍待游戏内检查，需确认键鼠/手柄导航、滚动和确认/返回。

2026-10-18 用户验收反馈：0.1.2.0 测试完成，核心逻辑没有问题，记录为核心逻辑实测通过。未提供上述清单的逐项结果，因此不将联机客户端、第三方组合等所有场景一并标为通过。0.1.3.0 仅调整界面交互，新弹窗仍待验收。

2026-10-18 布局修复：用户截图确认 0.1.3.0 的右箭头被裁切。0.1.3.1 在克隆产品行后按滚动区域实际宽度定宽，弹窗按最多四行和说明文字测量高度调整。新增布局边界回归；本机 `work/scripts/check_product_dialog_layout.py` 使用原生 GuiElement 几何方法，在五档缩放下复现旧宽度越界并验证修复。此为隔离几何验证，真实游戏截图复测仍待执行。

2026-10-18 用户验收更新：0.1.3.1 单弹窗显示和修改均正常，记录为实测通过。

0.1.3.2 图标使用 512×512 BC1/DXT1 DDS，包含到 1×1 的 10 级 mipmap，消除 PNG raw format 和 CPU mip generation 警告的来源。构建检查验证格式、尺寸、级数与完整压缩数据长度，ZIP 不含 PNG。真实游戏启动日志仍需复查。转换工具为 Microsoft DirectXTex texconv 2026.5.8.1（may2026）；[官方参数文档](https://github.com/microsoft/DirectXTex/wiki/Texconv)说明 `-f BC1_UNORM` 和 `-m 0` 的用途。本机 SDK 地图图标也使用 DXT1；本 Mod 额外包含完整 mipmap。
