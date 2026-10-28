# 开发与验收

## 当前验收状态

面向 PC 版 FS25 1.25.0.0，modDesc descVersion 114。玩家 README 只写功能和操作；验收状态集中记录在这里。

- 2026-10-21 首次实现：离线行为测试和多人模拟通过，三个脚本通过本机 fs-luau-compile 编译。尚未在游戏内测试，下方 FTS-01 至 FTS-14 全部待维护者执行。
- 1.0.0.0：维护者 2026-10-25 确认已实机测试，未提供逐项记录（包括主机/客户端），下方 FTS 清单不据此逐项标为通过。
- 首个正式版为 1.0.0.0（见“1.0.0.0 发布准备”），已登记到 `tools/ci.py` 的 `MODS` 和根 README 的 Mod 列表；之后的改动记录在 CHANGELOG 的 Unreleased。
- 封面 `assets/cover.jpg`（1920×1080）2026-10-25 由 Codex CLI 图像生成制作，以动物产品管理的封面为风格参考，同日按维护者要求重新生成：肥料改为参照游戏图标的带绿叶标记棕色袋装颗粒，石灰为白色粉堆，拖拉机改为不像任何真实品牌的配色；原图和提示词记录在被忽略的 `outputs/fill-type-selector/cover/`（`v2/` 为现用版本）；README 顶部显示。README 截图在 `assets/screenshots/`：维护者 2026-10-25 的游戏内截图（英文界面，FS25 1.25 PC，2000×1250），转为 JPEG 并用红框标出重点按钮和行，不进 ZIP。共 2 张：01 空喷洒机选择除草剂；02 空散布机（Bredal）选择石灰，为维护者 2026-10-26 补拍的截图（2560×1600 整幅缩放到 2000×1250，红框标出 F1 帮助的“选择肥料 (石灰)”行和料量显示）。未拍 Alt+Y、设置页和 AI 帮手撒石灰。

## 1.0.0.0 发布准备

2026-10-25：维护者确认已实机测试（“已经实机测试过了都”，与 Map Helper、Production Overflow 一并确认，未提供逐项记录），要求以正式版发布 1.0.0.0，与这两个 Mod 的 1.0.0.0 及 Animal Products Manager 1.0.0.4 一起并入 PR #6（dev → main）。维护者决定按现状发布：Alt+Y 保持为备用默认键，料箱用完后不沿用最后装过的类型（见“维护者决定”）。发布提交 6f482b4 只改 `modDesc.xml` 版本、`release.json`、CHANGELOG 标题和 README，脚本与已测构建一致，包内只有版本号不同；`FS25_FillTypeSelector.zip` SHA256 `ad3fccedd67b98ab6c7f3d21db698389342517eb3d89cf2187b54390e39da234`。CHANGELOG 的 Unreleased 条目移到 `## 1.0.0.0 — 2026-10-25`，空的 `0.1.0.0` 占位标题已删除。已登记到 `tools/ci.py` 的 `MODS` 和根 README 的 Mod 列表，CI Release plan 显示 `fill-type-selector-v1.0.0.0` 为新的正式版。`release.json` 为正式版（`"prerelease": false`），合并由维护者执行。截图和封面图待维护者提供。


2026-10-26 最终构建：维护者确认 2026-10-25 安装进游戏的构建（200ea8a，按维护者要求替换了四个 Mod 的 ZIP）实机测试没有问题，同意固定 SHA256。最终包在 06e2879，SHA256 `7e6cfdbf96ac30178e56c6b61e1f2f0c553a1db91d8e01c3233223de42080ca2`，与测试的包完全相同。
## 功能与决定

问题：原版 `Sprayer:getExternalFill` 在料箱为空（`FillType.UNKNOWN`）时只会按“液态肥料 → 固态肥料 → 除草剂”挑选购买类型，从不选石灰。因此纯石灰撒布机空箱时 AI 帮手直接因缺料停机，肥料+石灰撒布机空箱时总是买肥料；玩家只能先装一点石灰“标记”料箱（外部购买时不消耗料箱内容，所以标记一直有效）。

做法：给所有带 Sprayer 的车辆类型追加 specialization `fillTypeSelector`，为每台喷洒机具保存一个“选定喷洒类型”。

- 候选类型：喷洒机具自身料箱（`spec_sprayer.fillUnitIndex`）支持的、在 SprayTypeManager 中登记为喷洒类型、且机具确实为它设计了施撒的 fillType，按索引排序。“设计了施撒”：机具声明了 spray setup（`vehicle.sprayer.sprayTypes.sprayType#fillTypes`，GS Sprayer.lua:216-227、789-817，存于 `spec_sprayer.sprayTypes[i].fillTypes`）时，只取这些 setup 列出的类型；有 setup 未列 fillTypes 时视为覆盖全部；没有 setup 的粪肥撒布机（`isManureSpreader`）只取 MANURE；其他没有 setup 的机具取料箱的全部喷洒类型。原因：原版把料箱支持的全部类型都当作喷洒类型（`Sprayer:onStateChange`，GS Sprayer.lua:1348-1366），而 BULK 类通用拖车（Annaburger AW2217、Fliegl ASW271）料箱能装石灰、肥料等任何散货，2026-10-21 维护者游戏内反馈“原本不能撒石灰的粪肥车也能选石灰”。1.25 本体中料箱含石灰的喷洒机具只有 K105、FW212（setup 含 lime）、Variofex 750（setup 含 manure、lime）和上述两台通用拖车（无 setup），按本规则只有前三台提供石灰。粪浆罐车（例如 Oxbo AT5105，fillTypeCategories `slurryTank` = LIQUIDMANURE DIGESTATE）的候选是粪浆和沼渣。原版空箱时按 `helperSlurrySource` 直接购买或从粪池调取（GS Sprayer.lua:505-530），不需要“先装一点做标记”，但总是先粪浆：购买时只要粪浆有价格就买粪浆；粪池先取粪浆，取不到才取沼渣（该设置为“关”时 F1 提示“你需要先装填工具！”）。2026-10-21 维护者要求加上二选一。`FillTypeSelector:getExternalSlurry` 对所选类型重复原版这一分支：购买（`helperSlurrySource == 2`）用 `economyManager:getCostPerLiter(所选)`，价格、`updateFarmStats`、`MoneyType.PURCHASE_FERTILIZER` 与原版相同；所选类型没有价格时交给原版。粪池（`> 2`，`liquidManureLoadingStations[source-2]`）先取所选类型，再取另一种，只在服务器执行。设置为“关”时交给原版（不补充）。粪浆和沼渣算作“原版会自行选择”的类型，只能装粪浆的罐车不设默认选择。只有一种候选时不提供按键。
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

失败保护：`Register.lua` 在注册前检查所有被调用或覆盖的游戏函数和常量，缺少任一项时写一次警告并不添加 specialization，原版喷洒机具完全不变。检查不包含 `FillType.*` 常量：游戏在 `TypeManager.validateTypes` 之后才由 `FillTypeManager` 重建并填充 `FillType`（GS `fillTypes/FillTypeManager.lua:103`），检查时它还是空表。2026-10-21 的游戏日志显示旧版因检查 `FillType.UNKNOWN` 而 `Fill Type Selector disabled`，整个 Mod 未生效；`FillType` 只在游戏运行中使用。测试的替身同样在脚本加载和类型验证时让 `FillType` 为空，地图加载后才填入（`loadMapFillTypes`）。specialization 注册名必须是 `FS25_FillTypeSelector.fillTypeSelector`，否则报错并跳过。钩子按 Mod 名加键，重复载入地图不叠加；类型已有本 specialization 时不再添加。

## 扩展包兼容（2026-10-21，8 个已安装 DLC 解包核对）

解包位置 `work/reference/1.25.0.0/dlc/`。只有 Pumps n' Hoses 需要处理：

- 分离粪肥：DLC 新增 `SEPARATED_MANURE`，加入 BULK、MANURESPREADER、MANURESPREADER_ORCHARDS、SHOVEL 类别（`archive/data/fillTypes/fillTypes.xml:43-46`），并在地图加载时注册为喷洒类型，地面类型与粪肥相同（`PumpsAndHoses.lua:109-113`）。没有 spray setup 的粪肥撒布机因此候选为“粪肥及与粪肥同地面类型的喷洒类型”（`FillTypeSelector.isSpreadLikeManure`）。DLC 在加载时直接包装 `Sprayer.getExternalFill`（`inject_manureSeparation.lua:2-32, 93`）：原版没找到时，若请求的是分离粪肥（或空箱且料箱允许）且粪肥补充为“购买”，就购买分离粪肥。本 Mod 的覆盖排在它外层，选了分离粪肥时传给下一层；粪肥补充不是“购买”时传 `UNKNOWN`，由原版从粪堆取粪肥，避免帮手停机。
- 拖管施肥机：`umbilicalSprayer` 的 `getIsSprayerExternallyFilled` 总是返回 false 且不调用下一层（`UmbilicalSprayer.lua:25, 284-286`），料来自软管（`updatePreferredSpraySource`，`:240-261`）。这类车没有候选，不提供按键。
- Y 键：DLC 的 `PM_TOGGLE_TOOLCARRIER_STATE`、`PM_TOGGLE_REEL_STATE` 绑定 Y（`archive/dlcDesc.xml:312-331`），工具架即使未选中也注册（`ToolCarrier.lua:442-447`）。组合中有 `*.toolCarrier` 或 `*.umbilicalReel` 时视为 Y 已占用，改用 Alt+Y。
- 泵车 PW121、JC450、G400 是 `manureTrailer` 类型，没有 Sprayer，本 Mod 不涉及。
- 折叠配置：spray setup 可限定折叠配置（`Foldable:loadSprayTypeFromXML`，GS Foldable.lua:1598-1618，`hasRequiredFoldingConfiguration`），不适用于当前配置的 setup 不计入候选（例如 Plains & Prairies 的 Rogator 900 液体配置）。
- 其余 DLC（Highlands、NEXAT、Plains & Prairies 的撒肥机、喷雾机与粪浆罐车）按现有规则得到合理候选；Emergency、Daimler、NH CR11、Straw Harvest 没有喷洒机具（Straw Harvest 的 `SH_GRAB_BALES` 绑定 Y，但不在喷洒组合中）。没有 DLC 覆盖 `getIsSprayTypeActive`、`getSprayerUsage` 或 `onStateChange`。

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
| FTS-16 | Pumps n' Hoses：粪肥撒布机（例如 Highlands Lowlander HBD）选分离粪肥，粪肥补充设为购买，再改为粪堆 | 购买时帮手买分离粪肥；粪堆时改用粪肥，不停机 |
| FTS-17 | Pumps n' Hoses：拖管施肥机（SP12260/SPC1230 装在 HS5100 上、SP8040）与软管卷盘组合 | 施肥机没有选择按键；带工具架或卷盘的组合中肥料选择为 Alt+Y，Y 仍切换工具架/卷盘 |

## 结构

- `scripts/FillTypeSelector.lua`：车辆 specialization，候选、选择、显示、按键、AI 购买与 sprayType 覆盖、存档和同步。
- `scripts/SelectFillTypeEvent.lua`：选择事件 `FTSSelectFillTypeEvent`。
- `scripts/Register.lua`：在 `TypeManager.validateTypes` 前把 specialization 加到所有带 Sprayer 和 FillUnit 的车辆类型，检查所需接口。
- `tests/`：原创引擎替身及行为、多人测试；不会加载或执行反编译文件。
- `tools/build.py`：白名单打包，不安装；`tools/make_icon.py`：绘制图标。

## 维护者决定

2026-10-25 发布 1.0.0.0 时决定，按现状发布：

- 首个版本号为 1.0.0.0 正式版，已登记到 `tools/ci.py` 和根 README。
- Alt+Y 保持为新动作的备用默认键（德语键盘上 Y/Z 位置互换，按游戏的键位名显示）。
- 料箱用完后不自动沿用最后装过的类型：带肥播种机或撒肥机在没有选择时完全保持原版。
