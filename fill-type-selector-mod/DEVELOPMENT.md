# 开发与验收

## 当前验收状态

面向 PC 版 FS25 1.25.0.0，modDesc descVersion 114。玩家 README 只写功能和操作；验收状态集中记录在这里。

- 2026-10-21 首次实现：离线行为测试和多人模拟通过，三个脚本通过本机 fs-luau-compile 编译。尚未在游戏内测试，下方 FTS-01 至 FTS-14 全部待维护者执行。
- modDesc 中的 `0.1.0.0` 只是占位，首个正式版本号由维护者决定；CHANGELOG 中的 `0.1.0.0` 标题同样待调整。
- 本 Mod 尚未登记到 `tools/ci.py` 的 `MODS`，CI 不会构建或测试它。

## 功能与决定

问题：原版 `Sprayer:getExternalFill` 在料箱为空（`FillType.UNKNOWN`）时只会按“液态肥料 → 固态肥料 → 除草剂”挑选购买类型，从不选石灰。因此纯石灰撒布机空箱时 AI 帮手直接因缺料停机，肥料+石灰撒布机空箱时总是买肥料；玩家只能先装一点石灰“标记”料箱（外部购买时不消耗料箱内容，所以标记一直有效）。

做法：给所有带 Sprayer 的车辆类型追加 specialization `fillTypeSelector`，为每台喷洒机具保存一个“选定喷洒类型”。

- 候选类型：喷洒机具自身料箱（`spec_sprayer.fillUnitIndex`）支持的、在 SprayTypeManager 中登记为喷洒类型的 fillType，按索引排序。排除 LIQUIDMANURE 和 DIGESTATE：原版对粪浆/沼渣总是自行决定（先买粪浆），选择没有作用。只有一种候选时不提供按键。
- 唯一候选且原版不会自动选它（目前即石灰，或其他 Mod 新增的喷洒类型）时，把它当作默认选择，纯石灰撒布机无需按键即可购买石灰并设置 AI 地块条件。唯一候选是 MANURE、LIQUIDFERTILIZER、FERTILIZER、HERBICIDE 时保持原版。
- 生效条件：自身料箱为空，且没有连接的储箱（fillTypeSources）装着喷洒类型的内容。原版此时会先用连接储箱的内容，本 Mod 不干预。
- 料箱有内容：使用实际内容，按键设为不可用（帮助中隐藏），选择保留；料箱再次为空时选择重新生效。不自动用内容覆盖选择，以免玩家临时装了别的东西后选择被改掉。
- 没有选择且有多个候选：完全保持原版行为。

按键规则（维护者决定）：组合（`rootVehicle.childVehicles`）中如果已有东西使用 Y，就用新动作 `FTS_SELECT_FILL_TYPE`（默认 Alt+Y），否则用原版 `TOGGLE_SEEDS`（Y）向前、`TOGGLE_SEEDS_BACK`（Shift+Y）向后，后者与原版播种机一样不在帮助中显示文字。

- “已使用 Y”的判断：组合中有 `#spec_sowingMachine.seeds > 1` 的播种机（原版只在此时注册选种按键和 TOGGLE_SEEDS_BACK），或有精准农业的 `extendedSprayer` specialization（精准农业在没有播种机的喷洒机具上用 TOGGLE_SEEDS 切换默认作物需求）。按 specialization 名后缀 `.extendedSprayer` 判断，不依赖精准农业的类表。
- 组合中有两台以上可选择的机具时，只在被选中的机具上注册（`isActiveForInput`），避免一次按键改两台；只有一台时与原版播种机一样忽略选中状态（`isActiveForInputIgnoreSelection`）。
- 帮助文字：`Select fertilizer (Lime)`，括号内为原版 fillType 标题。`fts_selectFillType` 与控制设置中的 `input_FTS_SELECT_FILL_TYPE` 提供 27 种语言。
- Alt+Y 的依据：本机 `F:\SteamLibrary\steamapps\common\Farming Simulator 25\profileTemplate\inputBindingDefault_KeyboardMouse.xml`（1.25，只读）中含 Y 的绑定为 Y（IMPLEMENT_EXTRA3、TOGGLE_SEEDS、YARDER_FOLLOW_PICKUP、WINCH_DETACH）、Shift+Y（TOGGLE_SEEDS_BACK、TOGGLE_CUT_LENGTH_BACK）、Ctrl+Y（TOGGLE_CRABSTEERING、TOGGLE_WORKMODE、BALE_WRAPPER_DROP_CUSTOM）、Shift+Ctrl+Y（TOGGLE_CRABSTEERING_BACK）；左 Alt 只用于 F、N、P、X。Alt+Y 在原版键鼠默认中空闲。手柄等其他设备未设默认绑定，玩家可在控制设置中自行绑定。

效果：

- 显示：空箱时 `setFillUnitFillTypeToDisplay(index, 选择, true)`。必须用持久标记：原版在清空时先触发 `onChangedFillType`，再重置非持久的显示类型。装入内容时改回 `UNKNOWN`（非持久），因为 HUD 中显示类型会覆盖实际内容。播种机与喷洒共用同一料箱时不改显示，避免覆盖种子显示。唯一候选的料箱原版已在空箱时显示其类型，不另设。
- AI 购买：覆盖 `getExternalFill`，原版收到 `UNKNOWN` 时改为用选定类型调用原版函数。原版对 FERTILIZER、LIQUIDFERTILIZER、HERBICIDE、LIME 统一检查 `missionInfo.helperBuyFertilizer`（1.25 没有单独的石灰或除草剂设置），扣款仍由原版在 `isServer` 时执行。
- AI 是否外部补充：覆盖 `getIsSprayerExternallyFilled`。原版按机具类别判断：粪肥撒布机只看 `helperManureSource`。对“粪肥+石灰”撒布机选了石灰时，临时把类别标记视为肥料撒布机调用原版，调用后立即恢复，使石灰遵守“AI 帮手补充 - 肥料”。其他情况直接调用原版。
- 喷洒配置：覆盖 `getIsSprayTypeActive`。原版肥料+石灰撒布机（如 Bredal K105、Streumaster FW212）的 sprayType 写成 `fillTypes="fertilizer unknown"` 与 `fillTypes="lime"`，空箱时总是启用肥料配置（作业区、用量宽度、AI 标记、物体变化）。生效时，只把列出选定类型的 sprayType 视为可启用，并把它以 `fillTypes = {"UNKNOWN"}` 的视图交给覆盖链中的下一个函数，使 Foldable 等检查照常执行。
- AI 地块条件：原版 `Sprayer.updateAiParameters` 在 1.25 中没有调用方（GS 与反编译代码均未找到），AI 条件只在 `onLoad` 设默认值，以及服务器上 `onStartWorkAreaProcessing` 遇到新的非 UNKNOWN 类型时更新。本 Mod 在服务器上、空箱且有选择时调用 `setSprayerAITerrainDetailProhibitedRange(选择)`，让雇佣前就按所选类型（如石灰）筛选地块；该函数内部仍检查 `getUseSprayerAIRequirements`，带肥播种机等不受影响。

多人：`FTSSelectFillTypeEvent` 沿用 `SetSeedIndexEvent` 流程，发送方先本地生效。服务器对客户端请求检查：对象已同步；料箱为空且没有 AI 帮手在用（`getIsAIActive`），与本地按键的锁定条件相同；请求者所在农场可以使用该车辆（`g_currentMission:getFarmId(connection)` 加 `accessHandler:canFarmAccess`，与原版进入车辆、清空料箱的访问规则相同，承包农场也允许）；类型属于候选。通过后生效并广播给所有客户端（包括发送方，`ignoreConnection = nil`），使同时修改时所有端都以服务器顺序收敛。被拒绝时只向该连接发回服务器当前的选择（`connection:sendEvent`），让已先行生效的客户端恢复。客户端收到服务器的事件不回传。加入时 `onWriteStream`/`onReadStream` 同步选择（未选择写 `FillType.UNKNOWN`）。购买与扣款只在服务器发生（原版逻辑，按车辆的作业农场扣款）。2026-10-21 按 Codex 审查（任意客户端可改他人农场机具或作业中的选择）补上了这些服务器检查。

存档：`vehicles.vehicle(?).FS25_FillTypeSelector.fillTypeSelector#fillType`，按 fillType 名保存，在 `initSpecialization` 中向 `Vehicle.xmlSchemaSavegame` 注册（与精准农业 SoilSampler 相同做法）。在 `onPostLoad` 读取（FillUnit 在 `onPostLoad` 中恢复料量，本 specialization 排在其后）。未知名称或不属于候选的类型忽略。

失败保护：`Register.lua` 在注册前检查所有被调用或覆盖的游戏函数和常量，缺少任一项时写一次警告并不添加 specialization，原版喷洒机具完全不变。specialization 注册名必须是 `FS25_FillTypeSelector.fillTypeSelector`，否则报错并跳过。钩子按 Mod 名加键，重复载入地图不叠加；类型已有本 specialization 时不再添加。

## FS25 1.25 接口核对

路径前缀：GS = `work/reference/1.25.0.0/gameSource/dataS/scripts/`（随游戏 SDK 的 Lua），DC = `work/reference/1.25.0.0/decompiled/scripts/`（1.25 变更文件的反编译），DC24 = `work/reference/decompiled/dataS/scripts/`（1.24 反编译，1.25 字节码未变的文件）。1.25 中 Sprayer 与 SowingMachine 字节码有变化，GS 与 DC 的相关逻辑一致。

| 接口 | 位置 | 用途 |
| --- | --- | --- |
| `Sprayer:getExternalFill(fillType, dt)` | GS Sprayer.lua:488（UNKNOWN 回退 562-573，肥料分支含 LIME 558-581）；DC Sprayer.lua:383 | 覆盖：UNKNOWN 时改用选定类型 |
| `Sprayer:getIsSprayerExternallyFilled()` | GS Sprayer.lua:454-484；DC Sprayer.lua:341 | 覆盖：粪肥+石灰撒布机选石灰时按肥料设置判断 |
| `Sprayer:getIsSprayTypeActive(sprayType)` | GS Sprayer.lua:851；`getActiveSprayType` 838 | 覆盖：空箱时按选择启用 sprayType |
| `Foldable:getIsSprayTypeActive(superFunc, sprayType)` | GS Foldable.lua:1627 | 覆盖链中的下一环，只读字段，视图经 `__index` 保留 |
| `Sprayer:setSprayerAITerrainDetailProhibitedRange(fillType)` | GS Sprayer.lua:709（石灰 753） | 服务器上设置 AI 地块条件 |
| `Sprayer.updateAiParameters` | GS Sprayer.lua:687 | 1.25 无调用方，不使用 |
| `Sprayer:processSprayerArea` | GS Sprayer.lua:412-422 | AI 缺料停机条件（核对用） |
| `Sprayer:onStartWorkAreaProcessing` | GS Sprayer.lua:1203（外部补充 1245-1260，AI 条件 1289-1293） | 调用 getExternalFill 的位置（核对用） |
| `Sprayer:onStateChange` | GS Sprayer.lua:1348 | `fillTypeSources`/`supportedSprayTypes` 来源（只读） |
| `spec_sprayer.fillUnitIndex`、`isSlurryTanker`/`isManureSpreader`/`isFertilizerSprayer` | GS Sprayer.lua:182 起 onLoad | 只读，外部补充判断时临时切换类别标记 |
| `FillUnit:getFillUnitSupportedFillTypes(index)` | GS FillUnit.lua:997 | 候选类型 |
| `FillUnit:getFillUnitFillLevel(index)` / `getFillUnitFillType(index)` | GS FillUnit.lua:884 / 910 | 空箱判断、连接储箱判断 |
| `FillUnit:setFillUnitFillTypeToDisplay(index, fillType, isPersistent)` | GS FillUnit.lua:1082 | 空箱显示 |
| `FillUnit:addFillUnitFillLevel` 事件顺序 | GS FillUnit.lua:1485（清空 1576-1589，事件 1564/1579/1637） | 持久显示的依据 |
| `FillUnit:getFillLevelInformation` | GS FillUnit.lua:2537-2584 | 显示类型覆盖实际内容；单一类型空箱自动显示 |
| 事件 `onFillUnitFillLevelChanged`、`onChangedFillType` | GS FillUnit.lua:195-196 | 刷新显示与按键状态 |
| `SprayTypeManager:getSprayTypeByFillTypeIndex` | GS misc/SprayTypeManager.lua:228 | 判断喷洒类型 |
| `FillTypeManager:getFillTypeIndexByName` / `getFillTypeNameByIndex` / `getFillTypeTitleByIndex` | GS fillTypes/FillTypeManager.lua:504 / 475 / 483 | 存档、帮助文字 |
| `FillType.UNKNOWN` 名称 `UNKNOWN` | GS fillTypes/FillTypeDesc.lua:21，FillTypeManager.lua:204 | sprayType 视图 |
| `SowingMachine:onRegisterActionEvents` | GS SowingMachine.lua:872-887（`#spec.seeds > 1`） | Y 是否被占用 |
| `changeSeedInputButton` 默认 TOGGLE_SEEDS | GS SowingMachine.lua:221-225 | 同上 |
| `SowingMachine:setSeedIndex` / `SetSeedIndexEvent` | GS SowingMachine.lua:402；events/SetSeedIndexEvent.lua:14-75 | 事件流程参考 |
| 精准农业 `ExtendedSprayer` 使用 TOGGLE_SEEDS | GS internalMods/FS25_precisionFarming/scripts/specializations/ExtendedSprayer.lua:476-480、568 | Y 是否被占用 |
| `Vehicle:addActionEvent` / `clearActionEventsTable` | DC vehicles/Vehicle.lua:2072 / 2053 | 注册按键（callbackState 传方向） |
| `InputBinding:setActionEventText/TextVisibility/TextPriority/Active` | DC input/InputBinding.lua:905 / 927 / 938 / 949 | 帮助文字与可用状态 |
| modDesc `<actions>`、`<inputBinding>` 读取 | DC input/InputBinding.lua:1337-1345、1566；DC24 input/InputAction.lua:55-57（创建 `InputAction[name]`） | 新动作；l10n `input_<动作名>` 来自 1354-1386 |
| `Vehicle.xmlSchemaSavegame` | GS vehicles/Vehicle.lua:300 | 存档字段注册 |
| `Vehicle:saveToXMLFile` 调用 `spec.saveToXMLFile(self, xmlFile, key.."."..name)` | GS vehicles/Vehicle.lua:1515-1559 | 存档 |
| Mod specialization 名为 `<Mod名>.<名称>`、表名 `spec_<Mod名>.<名称>` | DC24 internalMods/FS25_precisionFarming/scripts/specializations/SoilSampler.lua:2-3；DC24 specialization/SpecializationUtil.lua:146-149 | SPEC_NAME / SPEC_TABLE_NAME |
| `SpecializationUtil.registerOverwrittenFunction` | GS specialization/SpecializationUtil.lua:103 | 覆盖链 |
| `TypeManager:validateTypes` / `addSpecialization` | GS specialization/TypeManager.lua:245 / 218；`g_vehicleTypeManager` 的 typeName 为 `vehicle`：DC24 specialization/TypeManager.lua:292 | 注册时机与类型判断 |
| Mod 代理 `g_specializationManager:getSpecializationByName` | DC mods.lua:583-589；读取 modDesc specializations 1019-1030，extraSourceFiles 997 | 取实际注册名 |
| `Vehicle:getIsSynchronized` | GS vehicles/Vehicle.lua:2606 | 事件对象检查 |
| `Vehicle:getIsAIActive` | GS vehicles/Vehicle.lua:196、3926 | AI 帮手作业中锁定选择 |
| `FSBaseMission:getFarmId(connection)` | DC FSBaseMission.lua:1069 | 服务器上取请求者的农场 |
| `g_currentMission.accessHandler:canFarmAccess(farmId, object)` | DC FSBaseMission.lua:160；DC24 farms/AccessHandler.lua:19；用法见 GS vehicles/specializations/FillUnit.lua:1491、Attachable.lua:1443 | 请求者农场能否使用车辆 |
| `Connection:sendEvent(event)` | DC24 network/Connection.lua:71 | 拒绝时把当前选择发回请求者 |
| `Server:broadcastEvent(event, sendLocal, ignoreConnection, ghostObject, ...)` | DC24 network/Server.lua:542 | 广播 |
| `I18N:getText(name, customEnv)` | DC24 I18N.lua:175 | Mod 文本 |
| `missionInfo.helperBuyFertilizer` 设置界面 | DC gui/InGameMenuSettingsFrame.lua:681；l10n `setting_helperRefillFertilizer` | 玩家文档中的设置名 |

精准农业的 `ExtendedSprayer` 不覆盖 getExternalFill 或 getIsSprayerExternallyFilled（GS 中未找到），与本 Mod 的覆盖不冲突；它的用量和 HUD 扩展未在游戏内核对。

已知限制（不在 README 中写）：空箱外部补充时，喷洒效果的颜色仍按原版取 `getFillUnitLastValidFillType`（GS Sprayer.lua:599-611），可能显示上次装过的类型；用量、地块与扣款按选定类型。

## 构建与测试

从仓库根目录执行：

```powershell
uv run fill-type-selector-mod/tests/run.py
python fill-type-selector-mod/tools/build.py
```

输出 `outputs/FS25_FillTypeSelector.zip`。ZIP 只含白名单内的 5 个原创文件：modDesc.xml、`scripts/FillTypeSelector.lua`、`scripts/SelectFillTypeEvent.lua`、`scripts/Register.lua`、`icon_fillTypeSelector.dds`。构建不安装、不修改存档、不启动游戏。

- `tests/engine_mock.lua`：原创的引擎替身。Sprayer 替身只复现本 Mod 依赖的原版决定（UNKNOWN 回退、设置检查、sprayType 判断、Foldable 链），FillUnit 替身复现清空时的事件顺序；不加载游戏文件。
- `tests/behavior.lua`：候选类型、Y 与新按键规则（有/无多种子播种机、精准农业、组合、两台机具）、循环、空箱显示、锁定、连接储箱、AI 购买（含石灰与原版回退）、购买设置、粪肥+石灰撒布机、sprayType 切换、AI 地块条件、事件往返、他人农场/料箱有内容/AI 作业中的请求被拒绝且发送方恢复、加入同步、存档、重复注册、缺少接口时停用。
- `tests/multiplayer.py`：服务器和两个客户端各自独立的 Lua 环境，用真实事件经有序传输：客户端/主机修改、同时修改两种到达顺序、无效请求、他人农场与锁定状态下的请求被拒绝并只纠正发送方、存档重载后加入、只有服务器扣款。
- 图标：`uv run fill-type-selector-mod/tools/make_icon.py --texconv <texconv.exe路径>`，默认查找 PATH 或被忽略的 `work/tools/directxtex/texconv.exe`。代码绘制（撒肥机料斗、肥料袋和石灰袋、循环箭头），PNG 源在 `assets/icon.png`，运行时使用 512×512 BC1、无 mipmap 的 `icon_fillTypeSelector.dds`，由 build.py 检查。

## 游戏内回归清单

单人测试默认开启“AI 帮手补充 - 肥料”，除非条目另有说明。每条记录构建提交与 SHA256。

| 编号 | 场景 | 预期 |
| --- | --- | --- |
| FTS-01 | 肥料+石灰撒布机（如 Bredal K105）空箱，挂在拖拉机上 | F1 显示“Select fertilizer”，Y 切换为 Solid Fertilizer / Lime，Shift+Y 反向；HUD 空料箱显示所选类型 |
| FTS-02 | FTS-01 选石灰后雇佣 AI 到需要石灰的田地 | AI 不停机，按石灰扣款，田地石灰状态更新；已撒石灰的地块被跳过；作业宽度为石灰配置 |
| FTS-03 | FTS-01 选固态肥料后雇佣 AI | 与原版相同买肥料；切回石灰后同一机具改买石灰 |
| FTS-04 | 纯石灰撒布机（DLC 或 Mod 机具）空箱雇佣 AI | 无按键；AI 购买石灰不停机 |
| FTS-05 | 关闭“AI 帮手补充 - 肥料”，FTS-02 场景 | AI 空箱即停（缺料提示），不扣款 |
| FTS-06 | 液态喷雾机（液肥/除草剂）选除草剂雇佣 AI | 购买除草剂，按杂草条件作业 |
| FTS-07 | 粪肥+石灰撒布机（Farmtech Variofex 750）选石灰，粪肥补充关、肥料补充开 | AI 购买石灰；改选粪肥并开启粪肥购买时购买粪肥 |
| FTS-08 | 带肥播种机（多种种子）挂接 | Y 仍切换种子；肥料选择用 Alt+Y（若机具有多种肥料可选），文字不重复 |
| FTS-09 | 有选择时手动装入另一种肥料 | HUD 显示实际内容；按键隐藏；用完后恢复显示所选类型 |
| FTS-10 | 前置料箱装有肥料、后置撒肥机空箱选石灰 | 先使用前置料箱的肥料（原版行为） |
| FTS-11 | 保存后重新载入 | 选择和 HUD 显示保留 |
| FTS-12 | 多人主机修改 / 客户端修改 | 双方 HUD 与 F1 一致；客户端雇佣 AI 时只有服务器扣款一次 |
| FTS-13 | 多人：选择后新客户端加入 | 加入的客户端看到相同选择 |
| FTS-15 | 多人：另一农场的玩家坐进不属于自己农场的撒肥机按 Y；本农场机具在 AI 作业中 | 选择不变（访问规则通常已阻止进入；无法进入时按客户端命令测试）；AI 作业中无按键 |
| FTS-14 | 精准农业开启的存档中的撒肥机 | Y 保持精准农业的功能；肥料选择为 Alt+Y |

## 结构

- `scripts/FillTypeSelector.lua`：车辆 specialization，候选、选择、显示、按键、AI 购买与 sprayType 覆盖、存档和同步。
- `scripts/SelectFillTypeEvent.lua`：选择事件 `FTSSelectFillTypeEvent`。
- `scripts/Register.lua`：在 `TypeManager.validateTypes` 前把 specialization 加到所有带 Sprayer 和 FillUnit 的车辆类型，检查所需接口。
- `tests/`：原创引擎替身及行为、多人测试；不会加载或执行反编译文件。
- `tools/build.py`：白名单打包，不安装；`tools/make_icon.py`：绘制图标。

## 待维护者决定

- 首个版本号（当前占位 0.1.0.0）及是否登记到 `tools/ci.py` 和根 README。
- Alt+Y 作为新动作默认键是否合适（德语键盘上 Y/Z 位置互换，按游戏的键位名显示）。
- 带肥播种机或撒肥机在没有选择时完全保持原版；是否希望“料箱用完后自动沿用最后装过的类型”。当前不沿用。
