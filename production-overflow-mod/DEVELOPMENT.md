# 开发与验收

## 当前验收状态

面向 PC 版 FS25 1.25.0.0，modDesc descVersion 114。玩家 README 只写功能和操作；验收状态集中记录在这里。

- 2026-10-25 首次实现：离线行为测试和多人模拟通过，四个脚本通过本机 `work/tools/fs-utils-bin/fs-luau-compile.exe` 编译。尚未在游戏内测试，下方 POF-01 至 POF-18 全部待维护者执行。
- 1.0.0.0：维护者 2026-10-25 确认已实机测试，未提供逐项记录（包括主机/客户端），下方 POF 清单不据此逐项标为通过。
- 首个正式版为 1.0.0.0（见“1.0.0.0 发布准备”），已登记到 `tools/ci.py` 的 `MODS` 和根 README 的 Mod 列表；之后的改动记录在 CHANGELOG 的 Unreleased。
- 名称 Production Overflow / 生产余量处理 由维护者 2026-10-25 确定，不再是工作名。
- 截图和封面图尚缺：README 没有截图，维护者之后提供游戏内截图。

## 1.0.0.0 发布准备

2026-10-25：维护者确认已实机测试（“已经实机测试过了都”，与 Map Helper、Fill Type Selector 一并确认，未提供逐项记录），确定名称 Production Overflow / 生产余量处理，要求以正式版发布 1.0.0.0，与这两个 Mod 的 1.0.0.0 及 Animal Products Manager 1.0.0.4 一起并入 PR #6（dev → main）。发布提交 6f482b4 只改 `modDesc.xml` 版本、`release.json`（`"prerelease": true` 改为 `false`）、CHANGELOG 标题和 README，脚本与已测构建一致，包内只有版本号不同；`FS25_ProductionOverflow.zip` SHA256 `1cdea1c528da8c5150d197705b730f129d54ae9b5babfc9b582ce22919e4f3db`。CHANGELOG 的 Unreleased 条目移到 `## 1.0.0.0 — 2026-10-25`，空的 `0.1.0.0` 占位标题已删除。已登记到 `tools/ci.py` 的 `MODS` 和根 README 的 Mod 列表，CI Release plan 显示 `production-overflow-v1.0.0.0` 为新的正式版。合并由维护者执行。截图和封面图待维护者提供。

## 功能与决定

维护者批准的设计：在原版生产菜单（`InGameMenuProductionFrame` 的“更改输出模式”）中，按生产点和产出物料新增两种模式，原版“分配”不变。

| 本 Mod 编号 | 常量 | 界面文字 | 每游戏小时，在原版分配之后 |
| --- | --- | --- | --- |
| 0 | `KEEP` | 原版 `ui_production_output_storing` | 原版 |
| 1 | `SELL` | 原版 `ui_production_output_selling` | 原版 |
| 2 | `DISTRIBUTE` | 原版 `ui_production_output_distributing` | 原版 |
| 3 | `DISTRIBUTE_STORE` | Mod 文本 `po_mode_distribute_store` | 剩余按原版储存规则生成满托盘 |
| 4 | `DISTRIBUTE_SELL` | Mod 文本 `po_mode_distribute_sell` | 剩余全部按出售价格卖出（仅服务器） |

中文界面文字由维护者指定；英文与 Animal Products Manager 的同名挡位一致，27 种语言的文字也沿用那里以原版词条为基础的译法。

### 原版行为（1.25.0.0 核对）

- `ProductionPoint.OUTPUT_MODE`：KEEP 0、DIRECT_SELL 1、AUTO_DELIVER 2，`OUTPUT_MODE_NUM_BITS = 2`（DC ProductionPoint.lua:6-10）。模式存在 `outputFillTypeIdsDirectSell` / `outputFillTypeIdsAutoDeliver` 两个集合中（:121-122），`setOutputDistributionMode` 先清两个集合再按模式写入，未知模式打印错误并返回（:920-937），然后发 `ProductionPointOutputModeEvent`。`getOutputDistributionMode` 由两个集合推出（:944-954）。`toggleOutputDistributionMode` 用 `table.hasElement(OUTPUT_MODE, cur + 1)` 循环（:955-964）。
- 存档只写 `directSellFillType` / `autoDeliverFillType`（:812-819），读档用 `setOutputDistributionMode`（:781-794）；加入时 `writeStream`/`readStream` 同样只传这两个集合（:423-490）。
- `ProductionChainManager:update`（DC24 misc/ProductionChainManager.lua:179-202）每帧轮流调用一个生产点的 `updateProduction`；整点后先完整轮一遍，每个已拥有的生产点在服务器上执行 `claimProductionCosts`、`directlySellOutputs`、`updateBalaceDirectlySoldOutputs`，再下一轮开始时调用 `distributeGoods()`（:206-241，只在服务器）：遍历每个农场的生产点，AUTO_DELIVER 集合中的物料按接收方空余容量比例送往同农场接收该输入的生产点，按距离 × `DIRECT_DELIVERY_PRICE` 向接收方农场扣运费（`g_currentMission:addMoney(..., MoneyType.PRODUCTION_COSTS, true)`），只读写各自的 `storage`。
- `updateProduction`（DC ProductionPoint.lua:575-685）：任一产出本 tick 放不下（`storage:getFreeCapacity`），整项生产 `NO_OUTPUT_SPACE` 停止、不消耗输入。托盘循环（:660-684）只在服务器、已拥有、冷却结束且没有等待中的托盘时运行，跳过 DIRECT_SELL 和 AUTO_DELIVER 集合中的物料；其余物料库存 ≥ `outputFillTypeIdsToPallets[ft].capacity` 时 `palletSpawner:spawnPallet(farmId, ft, self.palletSpawnRequestCallback, self)`。回调（:525-554）把当时的全部库存交给 `pallet:addFillUnitFillLevel`，按实际装入量扣减库存；没有托盘时设 15 秒冷却。`palletSpawnRequestCallback` 在发起时从实例查找，因此类上的覆盖会生效。
- `outputFillTypeIdsToPallets` 来自 `palletSpawner:getSupportedFillTypes()`（:292-298），值是 PalletSpawner 的托盘描述，`capacity = FillUnit.getCapacityFromXml(托盘 XML)`（DC24 placement/PalletSpawner.lua:63-94）。
- `directlySellOutputs`（:749-757）：`DIRECT_SELL_PRICE_FACTOR (0.9) × 库存 × getPricePerLiter`，`self.mission:addMoney(revenue, ownerFarmId, MoneyType.SOLD_PRODUCTS, true)`，然后 `storage:setFillLevel(0, ft)`。

以上 InGameMenuProductionFrame、ProductionChainManager、ProductionPointOutputModeEvent、PalletSpawner、PlaceableProductionPoint、Storage、LoadingStation 在 1.24 → 1.25 字节码未变（`work/analysis/update-1.25.0.0/comparison.json`），因此用 1.24 反编译核对；ProductionPoint 在 1.25 有变化（新增 `isPrimary`），用 1.25 反编译核对。

### 状态表示：原版 AUTO_DELIVER + 本 Mod 的标记

两种新模式在原版层面就是“分配”：物料留在 `outputFillTypeIdsAutoDeliver` 中，本 Mod 在生产点上另存 `poState.rest[fillType] = 3 或 4`。

- 原版 `distributeGoods`、存档、加入同步、DLC 和其他 Mod 读到的都是“分配”，无需改动。
- 卸载 Mod 后存档中只剩原版的 `autoDeliverFillType`，自然退回“分配”，不丢库存。
- 任何原版途径修改该物料的模式（原版事件、控制台 `gsProductionPointSetOutputMode`、读档、其他 Mod）都会经过被覆盖的 `setOutputDistributionMode`，本 Mod 先清掉标记和放行量，再交给原版。所以标记永远只存在于原版 AUTO_DELIVER 之上。

**偏离建议之一：不覆盖 `getOutputDistributionMode`。** 它继续返回原版值（新模式返回 AUTO_DELIVER），本 Mod 用自己的 `ProductionOverflow.getMode` 给界面和切换使用。原因：原版界面、Pumps n' Hoses 的界面扩展和其他 Mod 都把它与原版常量比较（`== AUTO_DELIVER`），返回 3/4 会让它们把新模式当成别的东西；`getMode` 遇到 0-2 以外的原版值（别人新增的模式）返回 nil，避免与本 Mod 的 3/4 撞号。

### 不扩展 `OUTPUT_MODE` 和 `OUTPUT_MODE_NUM_BITS`

评估了“加载时把两个值加入 `ProductionPoint.OUTPUT_MODE` 并提高位数、沿用原版事件”的做法，没有采用：

- Pumps n' Hoses 在加载时用同样方式注册自己的 `AUTO_DISTRIBUTION`：取 `ProductionPoint.OUTPUT_MODE` 与自身表的最大值 + 1，必要时把 `OUTPUT_MODE_NUM_BITS` 提到 3（`dlc/pumpsAndHosesPack/decompiled/src/sandbox/objects/SandboxProductionPoint.lua:3-24`），但只把值放进自己的 `SandboxProductionPoint.OUTPUT_MODE`。它的 `toggleOutputDistributionMode` 用 `getOutputDistributionMode + 1` 判断是否进入自己的模式（:386-397）。DLC 先加载时它是 3，我们只能用 4/5，原版 `cur + 1` 从 2 跳不到 4；本 Mod 先加载时我们占了 3/4，DLC 变成 5，它自己的循环从 2 再也到不了 5，等于破坏 DLC 的沼气分配切换。
- `OUTPUT_MODE_NUM_BITS` 由原版事件和 DLC 共用，再提高位数虽然安全，但没有必要：本 Mod 的两个值只在自己的事件里传输。
- 原版 `commandSetOutputMode`（DC24 ProductionChainManager.lua:317-349）用 `table.hasElement(OUTPUT_MODE, tonumber(mode))` 校验后把字符串原样交给 `setOutputDistributionMode`；值不加入 `OUTPUT_MODE` 时控制台命令只接受原版的 0-2，行为与原版一致。

因此本 Mod 的 3/4 只是内部编号，`POModeEvent` 用自己的 `PO.MODE_NUM_BITS = 3` 传输，从不交给原版代码。

### 切换顺序

覆盖 `ProductionPoint:toggleOutputDistributionMode`：储存 → 出售 → 分配 → 剩余自动储存（只在 `palletSpawner` 存在且 `outputFillTypeIdsToPallets[ft]` 有托盘时）→ 剩余自动出售 → 储存。没有本 Mod 状态的生产点（Pumps n' Hoses 沙盒生产、加载失败、已删除）和本 Mod 不认识的原版模式交给原版切换。原版界面只对所选生产的 `primaryProductFillType` 切换（DC24 InGameMenuProductionFrame.lua:509-520），按钮只在非工厂生产且主产品已知时显示（:200-210），这些不变。

“剩余自动出售”之后回到储存，不会再走到其他 Mod 可能追加在 `OUTPUT_MODE` 中的值。

### 网络

- 切换不在客户端本地先生效：客户端发送 `POModeEvent(生产点, 物料, 目标模式)`，服务器检查后执行 `applyMode` 并广播给所有客户端（`g_server:broadcastEvent(event)`，不排除发送方），所有机器按服务器顺序收敛。原版切换是客户端先生效再发原版事件，两位经理同时切换同一物料时可能不一致；本 Mod 走服务器裁决，代价是客户端要等服务器回包才看到新模式。为此收到事件后置 `PO.uiDirty`，被追加的 `InGameMenuProductionFrame:update` 在下一帧调用 `updateProductionLists()`，不必等原版 5 秒刷新。
- 服务器检查：生产点有本 Mod 状态、已拥有（不是 `AccessHandler.EVERYONE`）、请求者农场等于所有者（`g_currentMission:getFarmId(connection)`），且有 `manageProductions` 权限（`getHasPlayerPermission("manageProductions", connection, farmId)`，与原版生产菜单的按钮检查同一权限；原版事件本身在服务器上不检查）。模式必须对该物料可用。被拒绝时不广播；客户端本来就没有先行修改，不需要纠正。
- 应用模式时原版部分一律 `noEventSend = true`，本 Mod 事件里的模式是完整的 0-4，客户端照样在本地设置原版部分，所以选原版模式也只有一个事件。
- 加入：本 specialization 的 `onWriteStream`/`onReadStream` 排在 `PlaceableProductionPoint` 之后（同一类型中后添加的 specialization 事件监听器后执行，Placeable.lua:665-697），先由原版同步两个集合，再写 `UInt8 数量 + 每项（fillType SEND_NUM_BITS 位，模式 3 位）`。只同步 3/4；放行量只在服务器使用，不同步。客户端只在原版已是 AUTO_DELIVER 且该模式可用时接受。生产点加载失败的放置物写 0 项，保持流对齐。
- 出售和生成托盘只在服务器（`manager.isServer` 且 `point.isServer`、`point.isOwned`）。

### 存档

`placeables.placeable(?).FS25_ProductionOverflow.productionOverflow.output(?)`，在 `registerSavegameXMLPaths` 注册（Placeable.lua:138-146 按 specialization 名注册到 `Placeable.xmlSchemaSavegame`）：

| 属性 | 类型 | 含义 |
| --- | --- | --- |
| `#fillType` | STRING | 物料名 |
| `#mode` | STRING | `storeRest` 或 `sellRest` |
| `#releasedLiters` | FLOAT | 仅 `storeRest`：上一次整点分配后剩下、还可以生成托盘的量；不超过当前库存 |

只写设了新模式的物料，按生产点自己的 `outputFillTypeIdsArray` 顺序。读档在 `loadFromXMLFile` 中只收集，`onLoadFinished`（Placeable.lua:487，在所有 specialization 读档之后）再应用：原版读档已是 AUTO_DELIVER 且模式可用时才设标记（原版存档说别的模式时以原版为准；没有托盘的物料存了 `storeRest` 时忽略），放行量只对 `storeRest` 接受有限正数，使用时再截到库存。未知物料名、未知模式忽略。`reset` 时不读取。

### 剩余自动储存：放行量与托盘

问题：原版托盘循环跳过 AUTO_DELIVER 集合中的物料，而“剩余自动储存”的物料一直在这个集合里；同时整点之后新产出的部分不能马上变成托盘，要先等下一次分配。

做法（服务器）：

1. 整点分配之后（被追加的 `distributeGoods`），把该物料当时的全部库存记为放行量 `poState.released[ft]`。
2. 覆盖 `ProductionPoint:updateProduction`：调用原版之前先把放行量截到当前库存；生产点已拥有、有托盘生成器、冷却结束、没有等待中的托盘，且放行量 ≥ 该物料的托盘容量时，把该物料暂时移出 `outputFillTypeIdsAutoDeliver`（先记在 `poState.exposed` 中），调用原版 `updateProduction`，之后立即放回。这样由原版自己的托盘循环、轮转、冷却和托盘上限处理生成；原版生产部分不读这个集合。
3. 覆盖 `palletSpawnRequestCallback`：记录回调前后的库存，托盘装走多少，放行量就减多少（不低于 0）。原版回调把全部库存交给托盘、托盘最多装满自身容量，所以单个托盘只取放行量里的一托盘；回调异步到达期间新增的产量也只算一次，因为扣的是实际装走量，而且之后会截到库存。
4. 结果：只生成满托盘；不足一托盘的余量留在工厂，下一小时先参与分配，再重新计算放行量；整点后的新产出没有放行，等下一次分配。被托盘位置挡住或达到托盘上限时，原版冷却后重试，放行量保留。

其他规则：切换到别的模式或从别的模式切到“剩余自动储存”时清空该物料的放行量（新的“剩余自动储存”等自己的整点）；生产点易主（被追加的 `setOwnerFarmId`）时清空全部放行量，模式与原版一样保留。放置时（包括读档后）`PlaceableProductionPoint:onFinalizePlacement` 第一次设置所有者，那时放行量已从存档读入，不能清掉：本 specialization 在 `onPostFinalizePlacement`（Placeable.lua:537-538，在 onFinalizePlacement 之后）记下当时的所有者，之后只有所有者真的变化才清空。

错误恢复：原版 `updateProduction` 抛错时集合暂时缺项，`poState.exposed` 仍有记录；下一次 `updateProduction`、原版 `saveToXMLFile`/`writeStream` 之前（前置钩子）、`distributeGoods` 之前（前置钩子）和任何 `setOutputDistributionMode` 之前都会先放回。放回只针对仍有本 Mod 标记的物料，原版之后改过的模式不会被覆盖。脚本不捕获错误，让它进入游戏日志（仓库约定）。

**偏离建议之二：** 建议中的放行量方案原样采用；托盘仍由原版循环生成，没有另写生成逻辑。为让原版循环能看到该物料，需要在单次调用期间临时修改 AUTO_DELIVER 集合，这一点建议中没有提到，已在上面说明并加了恢复。

### 剩余自动出售

被追加的 `ProductionChainManager:distributeGoods` 之后，对每个已拥有、有本 Mod 状态的生产点：`DIRECT_SELL_PRICE_FACTOR × 库存 × economyManager:getPricePerLiter(ft)`，`g_currentMission:addMoney(收入, 所有者农场, MoneyType.SOLD_PRODUCTS, true)`，然后 `storage:setFillLevel(0, ft)`。与原版 `directlySellOutputs` 的价格、记账类型、`addChange` 和顺序相同（原版用 `self.mission`，即 `g_currentMission`）。库存为 0 时不记账。没有生产点接收该物料时等于全部出售。

### 每小时钩子与已知限制

- 出售和放行只在整点后的分配之后执行一次，不是持续执行；工厂在一小时内装满时仍会 `NO_OUTPUT_SPACE` 停到整点（维护者已接受）。
- 与原版分配一样只看生产点自己的 `storage`。带 `loadingStation` 的生产点，输出从共享装货站被取走时库存下降，放行量随之截取；`findStorageExtensions` 找到的扩展仓储不参与原版分配，本 Mod 也不处理。
- 原版 `distributeGoods` 遍历 `farmIds` 中的生产点；本 Mod 遍历 `manager.productionPoints` 并只处理已拥有的，结果相同。
- 原版放置物以外、不用 `PlaceableProductionPoint` 的生产点没有本 Mod 状态，保持原版。

### 界面

追加 `InGameMenuProductionFrame:populateCellForItemInSection`：在产品列表（`productsList`）中，所选生产的主产品处于新模式时，把 `activity` 文字换成 Mod 文本（`g_i18n:getText(key, modName)`）。其他列表、没有本 Mod 状态的生产点、非产出物料不动。生产点信息框（`updateInfo`）原版不显示输出模式，本 Mod 也不加。

### 失败保护与注册

- `Register.lua` 在安装任何钩子之前检查所需的类、函数和常量（包括 `OUTPUT_MODE` 的三个值必须是 0/1/2），缺少任一项时写一次警告 `Production Overflow disabled: game function ... not found` 并完全不安装，生产点保持原版。
- 钩子按 Mod 名加键存在类表上，重复载入地图不叠加；当前存档没有激活本 Mod（`g_modIsLoaded`）时全部直通原版。
- 在 `TypeManager.validateTypes` 之前把 specialization `FS25_ProductionOverflow.productionOverflow` 加到所有带 `PlaceableProductionPoint` 的放置物类型；注册名不符时报错并跳过。脚本加载顺序：`extraSourceFiles`（ProductionOverflow、ModeEvent、Register，mods.lua:997-1002）先于 `placeableSpecializations`（mods.lua:1036-1043，`SpecializationManager:addSpecialization` 在 :86 `source` 文件），所以 specialization 类放在单独的 `ProductionOverflowPlaceable.lua`，Register 只在 `validateTypes` 时引用它。

## 兼容性

- **Pumps n' Hoses（`dlc/pumpsAndHosesPack`）**：沙盒生产（发酵罐、发电厂）使用 `SandboxPlaceableProductionPoint`，前提是 `SandboxPlaceable`（`SandboxPlaceableProductionPoint.lua:22-24`），不含 `PlaceableProductionPoint`，因此没有本 Mod 状态，切换、存档、同步全部交给 DLC 和原版。DLC 的 `SandboxProductionPoint` 覆盖 `toggle/set/getOutputDistributionMode` 并调用父类，父类方法即本 Mod 覆盖后的版本，没有状态时直通。DLC 的界面扩展用 `inj_populateCellForItemInSection` 包装同一函数，只在 `getOutputDistributionMode == AUTO_DISTRIBUTION` 时改文字，与本 Mod 互不影响，包装先后无关。DLC 提高的 `OUTPUT_MODE_NUM_BITS` 不影响本 Mod 事件。没有 DLC 覆盖 `updateProduction`、`palletSpawnRequestCallback` 或 `distributeGoods`。
- **共享装货站 / 储存扩展**：见上节。原版本来就只分配 `storage` 中的库存。
- **Animal Products Manager**：它在畜舍 `onHourChanged` 时直接写入生产点 `storage` 的输入物料，不调用本 Mod 覆盖的任何函数；本 Mod 只处理生产点的产出物料。两者不共享代码，同时安装时畜舍先送货，生产点在稍后的原版分配之后再处理产出，没有冲突。
- **其他 Mod**：同样覆盖 `updateProduction`、托盘回调或输出模式的 Mod（如生产点改造类）可能冲突；README 建议先在单独存档试用。已安装的 FS25_BetterContracts、FS25_FieldDetailInfos 不涉及这些函数。

## FS25 1.25 接口核对

路径前缀：DC = `work/reference/1.25.0.0/decompiled/scripts/`（1.25 变更文件的反编译），DC24 = `work/reference/decompiled/dataS/scripts/`（1.24 反编译，1.25 字节码未变的文件），GS = `work/reference/1.25.0.0/gameSource/dataS/scripts/`（官方 SDK，部分实现省略），PNH = `work/reference/1.25.0.0/dlc/pumpsAndHosesPack/decompiled/src/`。

| 接口 | 位置 | 用途 |
| --- | --- | --- |
| `ProductionPoint.OUTPUT_MODE`、`OUTPUT_MODE_NUM_BITS`、`DIRECT_SELL_PRICE_FACTOR`、`DIRECT_DELIVERY_PRICE` | DC objects/ProductionPoint.lua:4-10；GS 同名文件 | 检查与计价 |
| `outputFillTypeIds`、`outputFillTypeIdsArray`、`outputFillTypeIdsDirectSell`、`outputFillTypeIdsAutoDeliver`、`outputFillTypeIdsToPallets` | DC ProductionPoint.lua:119-123、193-194、292-298 | 只读；单次调用中临时移出 AUTO_DELIVER |
| `palletSpawnCooldown`、`waitingForPalletToSpawn`、`isOwned`、`ownerFarmId`、`storage`、`palletSpawner` | DC ProductionPoint.lua:65-107、280-302、502-524 | 只读 |
| `ProductionPoint:setOutputDistributionMode(ft, mode, noEventSend)` | DC :920 | 覆盖：先清本 Mod 标记 |
| `ProductionPoint:getOutputDistributionMode(ft)` | DC :944 | 只调用 |
| `ProductionPoint:toggleOutputDistributionMode(ft)` | DC :955 | 覆盖：新循环 |
| `ProductionPoint:updateProduction()` | DC :575（托盘循环 660-684） | 覆盖：放行时让原版循环处理 |
| `ProductionPoint:palletSpawnRequestCallback(pallet, status, fillType)` | DC :525 | 覆盖：按装走量减放行量 |
| `ProductionPoint:directlySellOutputs()` | DC :749 | 出售规则的依据 |
| `ProductionPoint:setOwnerFarmId(farmId, noEventSend)` | DC :502 | 追加：清放行量 |
| `ProductionPoint:saveToXMLFile` / `loadFromXMLFile` | DC :797 / :759 | 前置：恢复集合；原版存档格式 |
| `ProductionPoint:writeStream` / `readStream` | DC :460 / :423 | 前置：恢复集合；原版同步内容 |
| `ProductionPoint:getOwnerFarmId()` | Object | 农场 |
| `ProductionPointOutputModeEvent` | DC24 objects/ProductionPointOutputModeEvent.lua | 原版事件；本 Mod 不使用，经 set 覆盖清标记 |
| `ProductionChainManager:update` / `distributeGoods` | DC24 misc/ProductionChainManager.lua:179 / 206 | 前置：恢复集合；追加：出售与放行 |
| `ProductionChainManager.productionPoints`、`isServer` | DC24 :19-28、GS misc/ProductionChainManager.lua | 遍历 |
| `ProductionChainManager:commandSetOutputMode` | DC24 :317 | 只核对（控制台仍只接受 0-2） |
| `PalletSpawner:getSupportedFillTypes` / `spawnPallet`，托盘 `capacity` | DC24 placement/PalletSpawner.lua:92 / 95、74 | 托盘容量 |
| `PlaceableProductionPoint`（`spec_productionPoint.productionPoint`，onLoad/onReadStream/onWriteStream/loadFromXMLFile/saveToXMLFile） | DC24 placeables/specializations/PlaceableProductionPoint.lua:46、100、108、116、122 | specialization 前提、取生产点、顺序 |
| Placeable 存档注册、读档、`onLoadFinished`、`onFinalizePlacement`/`onPostFinalizePlacement`、存档、流 | DC24 placeables/Placeable.lua:138-146、461-466、487、537-538、767-768、655-697 | 本 Mod 的存档、所有者记录与同步 |
| `InGameMenuProductionFrame:populateCellForItemInSection` | DC24 gui/InGameMenuProductionFrame.lua:296（文字 354-365） | 追加：新模式名称 |
| `InGameMenuProductionFrame:onButtonToggleOutputMode` / `updateMenuButtons` | DC24 :509 / :176（按钮 44-50、200-210） | 只核对 |
| `InGameMenuProductionFrame:update` / `updateProductionLists` | DC24 :218 / :553（`UPDATE_INTERVAL` 5000，:3） | 追加：收到模式后立即刷新 |
| l10n `ui_production_changeOutputMode`、`ui_production_output_*`、`ui_ingameMenuProductionChains`、`ui_permissions_manageProductions` | `work/reference/1.25.0.0/dataS-archive/l10n/l10n_*.xml` | 玩家文档和译文用词 |
| `FSBaseMission:getFarmId(connection)` / `getHasPlayerPermission(permission, connection, farmId)` / `addMoney(amount, farmId, moneyType, addChange)` | DC FSBaseMission.lua:1069 / 2072 / 2006 | 服务器检查与记账 |
| `Farm.PERMISSION.MANAGE_PRODUCTIONS = "manageProductions"` | DC24 farms/Farm.lua:19 | 权限名 |
| `AccessHandler.EVERYONE = 0` | DC24 farms/AccessHandler.lua:2 | 未拥有 |
| `MoneyType.SOLD_PRODUCTS` | DC24 MoneyType.lua:77 | 记账类型 |
| `Server:broadcastEvent(event, sendLocal, ignoreConnection, ...)` | DC24 network/Server.lua:542 | 广播 |
| `Utils.appendedFunction` / `prependedFunction` / `overwrittenFunction` | DC24 utils/Utils.lua:380 / 387 / 394 | 钩子 |
| `TypeManager.validateTypes`、mod 代理 `g_placeableSpecializationManager` | DC mods.lua:583-610、1036-1043；DC24 specialization/SpecializationManager.lua:68-93 | 注册 |
| Pumps n' Hoses 输出模式、切换、界面扩展 | PNH sandbox/objects/SandboxProductionPoint.lua:3-24、386-416；sandbox/gui/inGameMenuProductionFrameExtension.lua:106-199；sandbox/placeables/specializations/SandboxPlaceableProductionPoint.lua:22-24 | 兼容 |

## 改名

名称已于 2026-10-25 确定，本节只说明以后若要改名涉及的位置。显示名在 `modDesc.xml` 的 `<title>`、README 标题、`release.json` 的 `displayName`。ZIP 名和存档键另有影响：

- ZIP 名 `FS25_ProductionOverflow`（`tools/ci.py` 的 `MODS`、`tools/build.py` 的 `OUTPUT`）同时是 Mod 名，决定存档键 `FS25_ProductionOverflow.productionOverflow`、l10n 环境和钩子键。1.0.0.0 发布后改 ZIP 名，玩家的新模式会退回原版“分配”。
- 目录 `production-overflow-mod/` 与 `MODS` 的 slug 对应标签名 `production-overflow-v*`，README 中的发布链接也用它。
- 脚本中的 `ProductionOverflow`、`ProductionOverflowPlaceable`、`POModeEvent`、`po_*` 文本键只在代码内部使用，不必随显示名改。

## 构建与测试

从仓库根目录执行：

```powershell
uv run production-overflow-mod/tests/run.py
python production-overflow-mod/tools/build.py
```

输出 `outputs/FS25_ProductionOverflow.zip`。ZIP 只含白名单内的 6 个原创文件：modDesc.xml、`icon_productionOverflow.dds`、`scripts/ProductionOverflow.lua`、`scripts/ModeEvent.lua`、`scripts/Register.lua`、`scripts/ProductionOverflowPlaceable.lua`。构建不安装、不修改存档、不启动游戏。

- `tests/engine_mock.lua`：原创的引擎替身。ProductionPoint 替身只复现本 Mod 依赖的原版规则（两个模式集合、原版切换、`NO_OUTPUT_SPACE`、跳过分配/出售物料的托盘循环、按实际装入量扣库存的回调、原版存档和同步内容），ProductionChainManager 替身复现按空余容量分配和运费，托盘生成器异步完成；不加载游戏文件。
- `tests/behavior.lua`：切换循环（含无托盘物料、未知模式、无本 Mod 状态）、原版改模式清标记、剩余出售的价格与记账、剩余储存只生成满托盘、整点后的新产出等待、异步托盘不重复计数、无空位重试、与储存挡位托盘共存、库存被取走时截取、换模式和易主清放行量（读档后放置不算易主）、原版调用出错后的恢复、客户端与未拥有生产点不结算、存档格式和两种读档顺序、无效存档项、卸载后原版读档为“分配”、加入同步、事件位数与服务器检查、客户端只发请求、界面文字与刷新、主机按钮循环、Mod 未激活时直通、重复载入不叠加、specialization 只添加一次、缺少接口时完全停用。
- `tests/multiplayer.py`：服务器和两个客户端各自独立的 Lua 环境，用真实事件经有序传输：客户端走完全部模式、两位经理同时修改两种到达顺序、主机与客户端修改的两种执行顺序、权限/农场/对象变化后拒绝、原版事件在所有机器上结束新模式、两种新模式重复整点只在服务器结算一次、服务器存档重载后新客户端加入并继续修改。
- 图标：`uv run production-overflow-mod/tools/make_icon.py --texconv <texconv.exe路径>`，默认查找 PATH 或被忽略的 `work/tools/directxtex/texconv.exe`。代码绘制（工厂、分叉箭头、托盘和硬币），PNG 源在 `assets/icon.png`，运行时使用 512×512 BC1、无 mipmap 的 `icon_productionOverflow.dds`，由 build.py 检查。

## 游戏内回归清单

每条记录构建提交与 SHA256。建议用一条有托盘产出的链（例如面包房的面包由下游超市或 Mod 生产点接收）和一条液体产出的链（例如油厂）。

| 编号 | 场景 | 预期 |
| --- | --- | --- |
| POF-01 | 生产链页面选择自己的工厂，连续按“更改输出模式” | 储存 → 出售 → 分配 → 分配，剩余自动储存 → 分配，剩余自动出售 → 储存；产品列表显示对应文字 |
| POF-02 | 没有托盘的产出（液体）连续切换 | 分配之后直接是“剩余自动出售” |
| POF-03 | 下游未满时的“剩余自动出售” | 整点后下游收到货，扣运费；剩余卖出，财务记为“产品销售”，金额 = 90% × 当前价格 × 剩余 |
| POF-04 | 下游已满或没有接收方，“剩余自动出售” | 整点后工厂库存清零并全部卖出；工厂恢复生产 |
| POF-05 | 下游已满，“剩余自动储存”，工厂有 2.5 托盘的库存 | 整点后生成 2 个满托盘，0.5 托盘留在仓储；整点前不生成 |
| POF-06 | POF-05 之后等待一小时，期间有新产出，下游腾出空间 | 新产出和余量先送往下游，剩下的再生成满托盘；整点之间不出现新托盘 |
| POF-07 | 托盘生成区被挡住或达到托盘上限 | 不报错；清出空间后托盘出现，数量不超过整点时剩余的满托盘数 |
| POF-08 | 同一工厂一个产出设“储存”、另一个设“剩余自动储存” | 储存产出照常随时生成托盘；两种托盘轮流生成 |
| POF-09 | 原版“分配” | 与未安装 Mod 时相同，不生成托盘、不出售 |
| POF-10 | 设好新模式后保存并重新载入 | 模式保留；“剩余自动储存”整点时剩下、尚未成托盘的部分在载入后继续生成 |
| POF-11 | 设新模式后停用本 Mod 载入存档并保存，再启用 | 停用时显示“分配”，库存不变，无报错；停用期间保存过的存档重新启用后为“分配”，可重新选择 |
| POF-12 | 生产点卖掉再买回（或改归属） | 不报错；模式保留，整点前不生成托盘 |
| POF-13 | 多人：主机和客户端分别切换 | 双方产品列表文字一致；客户端按下后很快显示新模式 |
| POF-14 | 多人：没有“管理生产点”权限的成员 | 原版提示无权限，模式不变 |
| POF-15 | 多人：设新模式后新玩家加入 | 加入的玩家看到相同模式 |
| POF-16 | 多人：整点结算 | 只有服务器记一次收入、生成一次托盘；客户端金额和托盘与服务器一致 |
| POF-17 | Pumps n' Hoses：沙盒发酵罐/发电厂切换输出模式 | 与未安装 Mod 时相同（含 DLC 的自动分配模式），没有新模式 |
| POF-18 | 同时安装 Animal Products Manager，畜舍分配到使用本 Mod 的工厂链 | 畜舍送货、工厂产出处理各自正常，无报错 |

## 结构

- `scripts/ProductionOverflow.lua`：模式、切换、应用与请求、托盘放行、整点结算、界面钩子的回调。
- `scripts/ModeEvent.lua`：`POModeEvent`。
- `scripts/Register.lua`：接口检查、在原版类上安装钩子、给生产点放置物类型添加 specialization。
- `scripts/ProductionOverflowPlaceable.lua`：放置物 specialization，创建状态、存档和加入同步。

## 待确认

名称已确定（见“当前验收状态”）。以下两项维护者尚未另行表态，1.0.0.0 按括号中的当前行为发布：

- “剩余自动出售”是否也应对价格为 0 的物料出售（目前与原版“出售”一致：照样清空，收入为 0）。
- 生产点易主后是否应把新模式重置为原版“分配”（目前与原版模式一样保留）。
