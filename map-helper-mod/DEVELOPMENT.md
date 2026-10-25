# 开发与验收

## 当前状态

面向 PC 版 FS25 1.25.0.0（安装目录 `VERSION` 为 1.25.0.0），modDesc descVersion 114，与动物产品管理一致。首个正式版为 1.0.0.0（见“1.0.0.0 发布准备”）；之后的改动记录在 CHANGELOG 的 Unreleased。

- 1.0.0.0：维护者 2026-10-25 确认已实机测试，未提供逐项记录（包括主机/客户端和专用服务器），下方 MAP-xx 清单不据此逐项标为通过。
- 封面 `assets/cover.jpg`（1920×1080）2026-10-25 由 Codex CLI 图像生成制作，以动物产品管理的封面为风格参考，原图和提示词记录在被忽略的 `outputs/map-helper/cover/`；README 顶部显示。游戏内截图尚缺，维护者之后提供。
- 仓库级接入：已登记到 `tools/ci.py` 的 `MODS` 和根 README 的 Mod 列表。`tools/check_syntax.py` 用 `git ls-files` 列文件，删除的文件在暂存前会报“文件不存在”，暂存删除后即正常。

开发记录（各条为当日状态）：

- 2026-10-21：首次实现（右侧抽屉 + 作业菜单中的“加入队列”），后改为原生 `MENU_EXTRA_1` 和规划模式。
- 2026-10-21 之后（未提交）：界面重做。删除右侧抽屉（`DrawerDialog`）和作业菜单里的“加入队列”按钮，改为地图左侧边栏 `mapOverviewSelector` 的新页面“地图助手”（下文“页面”）；新增全局热键左 Alt + M；服务器新增 MOVE、EDIT 和“插入为下一个”；修复退出存档失败（下文“退出存档时的清理”）。本机 `uv run map-helper-mod/tests/run.py`：l10n（24 个键）、GUI 引用核对、36 项行为测试、降级检查、8 组多人模拟通过；5 个脚本用 `work/tools/fs-utils-bin/fs-luau-compile.exe` 编译通过（输出在被忽略的 `work/validation/map-helper-luau/`，只说明可解析）；`python map-helper-mod/tools/build.py` 9 个文件，SHA256 见最终报告。**尚未在游戏内运行过**，下方 MAP-xx 清单全部待维护者执行。
- 2026-10-24（未提交，维护者按 1b8bd5e 游戏内反馈）：去掉“我的车辆”和“开始队列”按钮，原位置改为地点过滤选择器（下文“地点过滤与作业需求”），新增 `scripts/FieldNeeds.lua` 判断田地是否需要当前组合的作业；田地图标改为 `gui.storeAttribute_seeding`（原 `gui.icon_others_farmland` 在列表尺寸下看起来像人像）；加入作业时自动开始/继续队列，队列标题旁新增“继续队列”，当前作业行的“删除”改为“取消作业”（下文“自动开始、继续与取消”）；点击车辆卡片回到自己的车辆。随后按审查修正：别人坐着的车辆不再被自动开始或继续；需求判断改用各农具自己的设置（直播、土壤/草地镇压器、除草机/锄的替换表、去茎叶机作物、割台青贮阶段、有无作业区域、喷洒来源、已有喷洒类型）；页面打开时每 10 s 重算组合的作业。本机 `uv run map-helper-mod/tests/run.py`：l10n（30 个键）、GUI 引用核对、45 项行为测试、降级检查、10 组多人模拟通过；6 个脚本编译通过；构建 10 个文件，SHA256 见最终报告。同样**尚未在游戏内运行过**。
- 2026-10-25（维护者游戏内反馈后修正两处队列问题）：读档后队列只执行了一个作业，后面的不再自动开始（下文“读档后跟随帮手”）；队列自动开始下一个田地工作时，Hardi MEGA 1200L 喷杆还没收完帮手就开上了路（下文“推进前等待组合停稳”）。本机 `uv run map-helper-mod/tests/run.py`：57 项行为测试、10 组多人模拟通过，两项新回归测试在去掉修正后均失败；构建 SHA256 见最终报告。**尚未在游戏内验证**。
- 2026-10-25（Codex 审计 5，`work/audits/map-helper-audit-5.md`，审计 5f8f15f）：读取 `mapHelper.xml` 时丢弃缺少目标位置或方向的作业，不再让任务开始中断（下文“存档”）；页面打开时挂上或卸下农具，每 10 s 的刷新也重新读取可用作业类型（下文“地点过滤与作业需求”）；“读档后跟随帮手”按 1.25 能看到的代码改写；新增“已知局限”；队列自己开始作业和该作业开始行驶时各写一行诊断日志（下文“推进前等待组合停稳”）。本机 `uv run map-helper-mod/tests/run.py`：60 项行为测试、10 组多人模拟通过，三项新测试在去掉对应修改后均失败。**尚未在游戏内验证**。
- 2026-10-25（维护者要求）：“需要此作业的田地”只列出现在就能做该作业的田地（下文“是否需要”）：施石灰、镇压、捡石、粉碎、除草剂按游戏作业区域的作物和地面条件，播种查所选种子的季节和水稻田；“我的田地”的需要石灰/镇压文字仍与信息框相同。本机 `uv run map-helper-mod/tests/run.py`：62 项行为测试、10 组多人模拟通过；新断言在旧 `FieldNeeds.lua` 上失败（施肥规则对原版作物结果不变，除草/锄只多了可播种地面，均无失败断言）。**尚未在游戏内验证**。
- 2026-10-25（维护者要求）：删除余额下方的“地图助手”按钮（`gui/DrawerToggle.xml`、`MF.placeToggle`/`updateToggle`），X 改为显示在地图页底部按钮栏中（下文“按键”）。本机 `uv run map-helper-mod/tests/run.py`：62 项行为测试、10 组多人模拟通过。**尚未在游戏内验证**（MAP-01、MAP-22）。

## 1.0.0.0 发布准备

2026-10-25：维护者确认已实机测试（“已经实机测试过了都”，与 Fill Type Selector、Production Overflow 一并确认，未提供逐项记录），要求以正式版发布 1.0.0.0，与这两个 Mod 的 1.0.0.0 及 Animal Products Manager 1.0.0.4 一起并入 PR #6（dev → main）。发布提交 6f482b4 只改 `modDesc.xml` 版本、`release.json`、CHANGELOG 标题和 README，脚本与已测构建一致，包内只有版本号不同；`FS25_MapHelper.zip` SHA256 `c56a37c28fe19a4e87377e6ab23ca5989f2cca10ab4b488a86594b1483148a8d`。CHANGELOG 的 Unreleased 条目移到 `## 1.0.0.0 — 2026-10-25`，空的 `0.1.0.0` 占位标题已删除。已登记到 `tools/ci.py` 的 `MODS` 和根 README 的 Mod 列表，CI Release plan 显示 `map-helper-v1.0.0.0` 为新的正式版。`release.json` 为正式版（`"prerelease": false`），合并由维护者执行。截图和封面图待维护者提供。

## 扩展包兼容（2026-10-21，8 个已安装 DLC 解包核对）

解包位置 `work/reference/1.25.0.0/dlc/`。没有 DLC 修改 `InGameMenuMapFrame`/`InGameMenu`、`mapOverviewSelector`、`createJobContainer` 或地图页的 `MENU_EXTRA_1`/`MENU_MAP_ACTION_1`；Pumps n' Hoses 的 `MENU_EXTRA_1` 按钮只在生产页面和设施信息对话框中（`inGameMenuProductionFrameExtension.lua:71`、`placeableInfoDialogExtension.lua:22,87`）。没有 DLC 注册 AI 作业类型、AI 参数或合同类型；Pumps n' Hoses 的拖管作业是原版 FIELDWORK，缺料时以 `AIMessageErrorOutOfFill` 停止（`ToolCarrier.lua:404-405`、`UmbilicalSprayer.lua:319-346`），队列按“出错”暂停。Highlands 地图的非田地合同（枯木、运木、岩石）没有田地，地点列表跳过。没有 DLC 绑定左 Alt + M。Emergency、Straw Harvest、Highlands 追加 `FSBaseMission.delete`，与本 Mod 的标记式前置/追加互不依赖顺序。`MH.getSupportsAI` 额外要求 `spec_aiJobVehicle.supportsAIJobs ~= false`（AIJobVehicle.lua:124），Emergency 的软管卷盘、交通锥车和 NEXAT 宽幅车这类不能派帮手的车辆直接显示为不支持。
## 结构

- `scripts/MapHelper.lua`：队列模型与服务端逻辑（请求处理、启动下一个作业、完成/取消判断、暂停原因、存档读写、加入同步、任务生命周期、全局热键注册）。
- `scripts/QueueEvents.lua`：`MHQueueRequestEvent`（客户端 → 服务器：添加/插入为下一个、编辑、移动、删除、清空、开始）和 `MHQueueStateEvent`（服务器 → 客户端：某车辆的完整队列）。
- `scripts/MapFrameExtension.lua`（`MHMapFrame`）：地图页面接入：选择器新状态与圆点、地图页底部按钮栏中的“地图助手”项、地图页按键（`MENU_EXTRA_1`、`MENU_MAP_ACTION_1`）、全局热键打开页面、各原生函数的钩子入口、规划模式（`MF.withPlanning`）、拆除。
- `scripts/MapHelperPage.lua`（`MHPage`）：页面内容：车辆卡片、地点过滤与地点列表、原生作业表单的放置与填写、加入/插入/保存、队列列表与进度、条目操作、继续队列。
- `scripts/FieldNeeds.lua`（`MHFieldNeeds`）：组合（车辆及其挂接农具）做哪些田间作业、某块田地在其位置点的状态、是否需要这些作业，以及“我的田地”的状态文字。
- `gui/MapHelperPage.xml`：页面本体，全部尺寸和位置写在 profile 里（下文“页面布局”）。`gui/MenuBarButton.xml`：地图页底部按钮栏中的“地图助手”项，沿用原生“下一页”按钮的 profile（`buttonMenuNext`）和分隔线。
- `scripts/Register.lua`：检查所需游戏函数是否存在，按功能（队列、页面、热键、田地需求）安装钩子；钩子按类只装一次，重复执行只刷新回调。
- `tests/`：原创引擎替身（`engine_mock.lua`）、`guixml.py`（把本 Mod 的 GUI XML 交给替身，替身按真实文件建元素树）、62 项行为测试、10 组多人模拟；不加载、不执行任何游戏文件。
- `tools/build.py`：白名单打包 10 个运行时文件（modDesc、6 个脚本、2 个 GUI XML、DDS 图标），检查 DDS 格式。
- `tools/make_icon.py`：代码绘制原创图标，PNG 源在 `assets/icon.png`。

## 设计

### 页面：地图边栏的新状态

地图页左侧 `filterBox`（profile `fs25_subCategoryContainer`，410 px 宽，全高）顶部是 `mapOverviewSelector`，状态 1-5 为地图图层，6 为创建作业，7 为在岗帮手（1.25 decompiled `gui/InGameMenuMapFrame.lua:3-12`，下称 MF）。本 Mod 按 Precision Farming 加“土壤取样”页面的方式（1.24 decompiled `internalMods/FS25_precisionFarming/scripts/gui/InGameMenuMapFrameExtension.lua:177-300`）加一个状态：

- 追加在 `InGameMenuMapFrame:setupMapOverview`（MF:949-960，每个任务第一次打开地图页时重建 `mapSelectorTexts`）之后：追加文字 `mh_toggle`，页面状态号取文字所在位置（无 PF 时为 8，PF 在前时为 9），`setTexts`；为该状态设 `dataTables`、`filterStates`、`numSelectedFilters`（否则 `filterList:reloadData` 会对未知状态报 devError，MF:2160-2169）；克隆 `subCategoryDotBox` 的第一个圆点并 `invalidateLayout`，圆点 `getIsSelected` 比较当前状态。
- 选择器的 `onClick` 在加载 XML 时已绑定到原函数（`GuiElement:addCallback`，SDK `gui/elements/GuiElement.lua:1611` 只绑一次），类表上的钩子不会被调用。与 PF 相同，注入时把 `onClickCallback` 换成 `frame:onClickMapOverviewSelector(state)`，拆除时恢复原值。
- 追加在 `onClickMapOverviewSelector`（MF:1518-1602）之后：原生部分已按状态号隐藏 `filterListContainer`（state ≤ 5）、`createJobEmptyText`（state == 6）、`workerListContainer`（state == 7），对本 Mod 的状态全都隐藏；本 Mod 再显示/隐藏页面。原生对 state ≠ 6 调用 `setMapSelectionItem(nil)`，切换页面时选择清空，与其他页面一致。
- 页面根元素 `mhPage` 用 `PrecisionFarmingGUI.loadAdditionalGUI` 同样的方式（`g_gui:loadProfileSet` + `g_gui:loadGuiRec`，SDK `gui/base/Gui.lua:347`）加载到 `filterBox`，目标是 `MHPage` 对象。`loadGuiRec` 不把 id 写到目标上（id 由 `FrameElement:exposeControlsAsFields` 处理，SDK `gui/elements/FrameElement.lua:100`），所以加载后自己遍历 `getDescendants()`（`GuiElement.lua:1412`）把 id 写到 `MHPage`，再对页面根元素调用 `onGuiSetupFinished`（`GuiElement.lua:568`，递归）：SmoothList 找模板和裁剪条，Slider 用 `target[dataElementId]` 找列表（`SliderElement.lua:267`）。`MHPage:getDescendantById` 转给页面根元素，供列表的 `emptyIndicatorId` 等按 id 查找。
- 焦点：`FocusManager:setFocus` 只接受 `target.name == currentGui` 的元素（SDK `gui/base/FocusManager.lua:769-777`）。`MHPage.name` 每次 `registerInput` 时取 frame 的 `name`，与原生元素相同。

### 页面布局（全部在 `gui/MapHelperPage.xml` 的 profile 中）

页面与原生列表同框：`mh_page` 继承 `fs25_subCategoryListContainer`（`guiProfiles.xml`：`absoluteSizeOffset 52px 215px`、`position 23px -145px`，即 358 px 宽、1080 参考高度下约 865 px 高）。自上而下（y 为距页面顶部）：

| 区域 | profile | y / 高 |
| --- | --- | --- |
| 车辆卡片（`gui.animalDealer_box`，正是在岗帮手列表项的 358×100 底图；左侧车辆商店图或机械图标、名称、状态、等待数） | `mh_vehicleCard` 及子项 | 0 / 100 |
| 地点过滤选择器（原生作业类型选择器 `fs25_aiJobTypeMultiTextOption`，高 32 px） | `mh_filterSelector` | -104 / 32 |
| 地点列表（只显示所选类别、无分组；行 32 px；空列表时显示说明文字） | `mh_placesBox`、`mh_list`、`mh_placeItem`、`mh_placesEmptyText` | -139 / 130 |
| 作业表单槽（原生 `createJobContainer` 放在这里，见下节） | `mh_nativeForm`（作用于原生容器） | -277 / 320 |
| “加入队列”（Z）/“插入为下一个”（X）；编辑时为“保存”/“取消” | `mh_buttonAction1/Extra1` | -603 / 25 |
| 队列标题 + “继续队列”（只在可继续时显示）+ “清空队列” | `mh_queueTitle`、`mh_buttonResume`、`mh_buttonClear` | -636 / 25 |
| 队列列表（行 40 px：黑色编号方块或帮手图标、标题、说明；纵向随页面拉伸） | `mh_queueBox`、`mh_queueItem` | -667 / 167（1080p） |
| 上移、下移、编辑、删除（当前作业行为“取消作业”），贴页面底部 | `mh_buttonIcon/Entry` | 底部 / 25 |

顶部车辆和地点约占 31%。表单槽按最长的“装载和运送”计算：作业类型 40 px + 7 行 × 40 px（隐藏车辆组后：装载站标题、装载站、填充类型、卸载站标题、卸载站、循环标题、循环）= 320 px；较短的作业下方留空，与原生作业菜单把“开始作业”固定在底部相同。列表行用地图右侧上下文按钮的底图（`fs25_mapContextButtonListItemBg`，选中改为高亮绿），文字和图标的选中色为深色；裁剪条、滚动条均为原生 `fs25_subCategory*`。地点行左侧名称 150 px，右侧信息 150 px（`textLayoutMode resize`，长文字缩小而不出框）。按钮全部是地图页原生按钮（`fs25_mapButtonBgLight` + `fs25_mapButtonText` + `fs25_mapButton`），`isTriggerableByGlobalAction=false`，只由本 Mod 的按键事件触发。上/下按钮用原生选项箭头 `gui.3dShop_arrow`（指向右），旋转 270°/90°；预览实验室中朝向正确（MAP-27 仍在游戏中确认）。

GUI 预览实验室（`tools/gui_lab/`，由集成方维护）渲染方法：

1. 渲染原生 `dataS-archive/gui/InGameMenuMapFrame.xml`，把 `gui/MapHelperPage.xml` 中 `<GUI>` 的子元素（根元素 id `mhPage`）作为最后一个子元素插入 `filterBox`，并加载其 `<GUIProfiles>`；去掉 `mh_page` 的 `visible=false`（或渲染后设为可见）。
2. 隐藏 `filterListContainer`、`workerListContainer`、`createJobEmptyText`；`subCategoryDotBox` 加第 8 个圆点并选中；选择器文字为“Map Helper”。
3. 对原生 `createJobContainer` 应用 profile `mh_nativeForm` 并设为可见，隐藏其中的 `buttonStartJobContainer`；`jobMenuLayout` 中第一组（车辆标题和车辆行）运行时隐藏。
4. 预览无法显示：运行时文字（车辆名、地点、队列行、进度）、按钮禁用状态、列表选中/悬停色、车辆商店图、原生作业表单的参数行（由 `setActiveJobTypeSelection` 按作业类型克隆）、地图上的目标标记、按键图标（`MENU_MAP_ACTION_1`/`MENU_EXTRA_1` 的实际键位）。

### 原生作业表单的复用

页面直接用原生 `createJobContainer`（作业类型 `jobTypeElement`、参数 `jobMenuLayout`、各参数模板），作业类型、参数行、站点/填充类型选择、验证提示和地图选点都是原生的：

- 不调用 `InGameMenuMapFrame:createJob`（MF:2509-2543）：它经 `setJobMenuVisible(true)`（MF:2479-2508）把选择器切到状态 6 并禁用，页面会被隐藏。改为按 `createJob` 的步骤：对 `jobTypeInstances`（`onFrameOpen` 中 `generateJobTypes`，MF:299/1347）逐个 `getIsAvailableForVehicle`，设 `currentJobTypes`、`jobTypeElement:setTexts/setState`、`currentJobVehicle`、`currentJob = nil`，然后调用原生 `setActiveJobTypeSelection`（MF:1403-1451：`createJob` + `applyCurrentState` + 按 `AIParameterType` 克隆行 + `updateParameterValueTexts` + `validateParameters`）。默认类型规则与原生相同（`getLastJob` 的类），之后切换类型走原生 `onJobTypeChanged`（MF:2025）。
- frame 保持 `AI_MODE_OVERVIEW`：这样在地图上点击车辆仍会选中（`onClickHotspot` 只在总览模式下 `setMapSelectionItem`，MF:1603-1611），页面据此切换车辆；`setMapSelectionItem` 末尾本来也会把模式设回总览（MF:1281）。代价是原生 `getCanStartJob`（要求 `AI_MODE_CREATE`，MF:796）为假——本来就不用原生开始；Esc 在总览模式下关闭菜单（`getCanGoBack`，MF:802），与其他边栏页面一致；选点中按 Esc 取消选点（MF:1799-1805）。
- 放置：页面显示时对原生容器 `applyProfile("mh_nativeForm")`。`GuiElement:applyProfile/loadProfile`（SDK `GuiElement.lua:393/315`）只覆盖 profile 链中出现的属性，且不更新 anchorDeltas，所以随后 `setPosition(当前位置)`（`:1121`，内部 `updateAnchorDeltas`）重新计算。子元素的 anchor 均相对父元素边界，随父元素移动（`updateAbsolutePosition`，`:1047-1070`）。`mh_nativeForm` 只用 `size` 而不用 `width/height`，因为 `loadProfile` 不会清掉已设的 `widthStr/heightStr`；离开页面时 `applyProfile("fs25_subCategoryListContainer")` + `setPosition` 即恢复原生布局，并恢复可见性和 `buttonStartJobContainer`。
- 原生“开始作业”容器 `buttonStartJobContainer` 在页面上隐藏。原生 `onMenuMapAction1`（MF:2380-2386）只在 `buttonDeselectAll` 或 `buttonStartJobContainer` 可见时动作（`getIsVisible` 检查父元素，`GuiElement.lua:1192`），因此页面上原生不响应；追加的钩子在页面显示时执行“加入队列”。
- 车辆组隐藏：车辆卡片已显示车辆，表单第一组（标题 + 不可修改的车辆行，`AIParameterType.TEXT`）在每次 `setActiveJobTypeSelection` 之后隐藏；`BoxLayout` 不排不可见元素（`BoxLayoutElement.lua:305`）。
- 离开页面（换状态、关闭菜单 `onFrameClose`、拆除）时清空表单，做法同 `setJobMenuVisible(false)` 的前半段（删除行、`currentJobElements = {}`、`jobTypeElement:setTexts({})`），但不碰焦点、选择器和 `createJobEmptyText`；若此时原生“创建作业”流程正在打开作业菜单（模式已是 `AI_MODE_CREATE`，如在页面上点了右侧上下文框的“创建作业”），保留它的车辆和作业，作业菜单照常在状态 6 打开。
- 按钮状态：每秒刷新时比较按钮所依赖状态（暂停、权限、帮手、队列、选中项、编辑）的签名，变化时重新设置启用状态，所以取消暂停或权限变化后不必等其他操作。
- 站点标记：装载站和卸载站参数各自只有自己的取值函数，未设置的站点为 nil，按类型分支处理。
- 地图标记：`setMapSelectionItem` 会移除或改写 `aiTargetMapHotspot` 等标记（MF:1049-1053、1181-1221），页面在每次选择变化后按表单参数重新加上（不平移地图）。

### 车辆

默认是 `g_localPlayer:getCurrentVehicle()`。页面显示时追加在 `setMapSelectionItem`（MF:1019）之后的钩子：选中的 hotspot 有 `getVehicle()` 且该车可规划（`MH.getCanManage` + `MF.getHasAccess` + `spec_aiJobVehicle`）时，页面改为该车并重建表单；其他 hotspot 只选中不切换。“我的车辆”按钮已去掉：显示的不是自己驾驶的车辆（且自己的车可规划）时，卡片信息行加上 `mh_backToMine`（“点击返回你的车辆”），点击卡片回到自己的车辆并平移地图；显示的就是自己的车辆时，点击卡片只平移地图。切换时按 `setAIVehicle`（MF:936-942）的方式 `setMapSelectionItem(hotspot)`，打开页面和回到自己的车辆时再 `panToHotspot`。

### 地点过滤与作业需求

地点列表一次只显示一个类别，由列表上方的 `MultiTextOption`（`mhFilterSelector`，回调 `(state, element)`，SDK `gui/elements/MultiTextOptionElement.lua:342`）选择：

| 选项 | 何时提供 | 内容 |
| --- | --- | --- |
| 需要此作业的田地（`mh_filterNeeds`） | 识别出组合至少一种田间作业且田地状态可读（`MH.features.fieldNeeds`） | 先列本农场进行中合同里、组合能完成其作业的（按合同类型判断，见下），再列本农场田地中需要组合作业的；信息栏为需要的作业（最多两项） |
| 我的田地（`mh_filterFields`） | 总是 | 本农场全部田地；信息栏为状态文字，读不到状态时为面积 |
| 合同（`ui_contracts`） | 总是 | 本农场进行中的田地合同；组合能做的排在前面，信息栏“作业 - 百分比”，其余只显示百分比 |
| 站点（`ui_stations`） | 车辆可执行 LOAD_AND_DELIVER 或 DELIVER | 有效的装载/卸载站点 |

合同的作业按合同类型（`mission.type.name`，`MissionManager:registerMissionType`，SDK `missions/MissionManager.lua:706-721`；服务器 `:266/:395`、客户端 `AbstractMission:readStream` `:264` 都有）对应：plowMission→犁地、cultivateMission→耕地、sowMission→播种、fertilizeMission→施肥、herbicideMission→除草剂、weedMission→除草机、hoeMission→锄、harvestMission→收割、mowMission→割草、stonePickMission→捡石（类型名见 decompiled `missions/field/*Mission.lua` 的 `NAME`）；收割、割草和播种还要求合同作物（`mission.fruitTypeIndex`，播种见 decompiled `missions/field/SowMission.lua:22-28`）在组合的作物表中，播种机的作物表来自 `spec_sowingMachine.seeds`（SDK `SowingMachine.lua:176-190`，Codex 审计 4 发现播种合同曾不看作物）；打捆、包膜、翻晒合同没有可识别的作业。合同田地不属于本农场，只按田地状态扫描本农场田地时不会出现：2026-10-24 维护者游戏内反馈犁和耕耘机的列表为空，存档中正好有进行中的犁地合同（41 号田）和耕地合同（10、53 号田），而本农场田地按状态都不需要（存档关闭了犁地要求）。“合同任务”过滤也用同一判断。

默认：有“需要此作业的田地”时选它，否则“我的田地”（例如卡车、没有挂农具的拖拉机）。每台车辆的选择存在 `MHPage.filterByVehicle`（本局游戏内，拆除时清空）。空列表显示对应说明（`mh_emptyNeeds/Fields/Contracts/Stations`）。田地状态在切换车辆、切换过滤和每 10 s（`MHPage.PLACES_INTERVAL`，页面显示时）读取一次，不是每帧。

**刷新可用作业类型（2026-10-25，Codex 审计 5）**：可用作业类型原来只在建表单时（`buildForm`）存入 `MHPage.jobTypes`，而每 10 s 的刷新（`updateFilterOptions`、`reloadPlaces` 经 `getAvailableTypes`）一直用旧值：页面开着时别人挂上耕作机，过滤已显示作业需求，田地却仍按“前往”预填和双击（卸下后反过来）。田地工作是否可用取决于有无 AI 农具（`AIJobFieldWork:getIsAvailableForVehicle` → `getCanStartFieldWork`，SDK `ai/jobs/AIJobFieldWork.lua:166-168`）。现在刷新先调用 `MHPage:refreshJobTypes`：重新取可用类型（与 `buildForm` 相同，规划模式下判断，5 个原生类型各一次调用），与 `jobTypes` 的索引列表不同时以当前表单的类型（仍可用时）和参数（`copyJobParameters`）重建表单；选点进行中不重建，留到下次刷新。

**已被帮手认领**：`MHPage:getClaims` 收集本农场正在运行的田地工作（`AISystem:getActiveJobs`，SDK `ai/AISystem.lua:541`，`startedFarmId` 为本农场）和地图助手队列中等待的田地工作，按作业起点（`AIParameterPosition:getPosition`，SDK `ai/parameters/AIParameterPosition.lua:71`）用 `FarmlandManager:getFarmlandIdAtWorldPosition`（SDK `economy/FarmlandManager.lua:421`）找到所在农地；运行中优先于排队。`MHPage.markClaims` 按地点的农地（合并田地取所有成员、合同取其田地）在信息栏前加“帮手作业中”（`mh_claimWorking`）或“已在队列”（`mh_claimQueued`）；在“需要此作业的田地”和“合同任务”中把这些地点稳定地移到最后，“我的田地”只标注不改顺序；站点不处理。2026-10-24 维护者要求。

**表单与地点列表的高度**：`MHPage:fitLayout`（在原生表单就位和每次构建后调用）把原生表单的高度设为作业类型实际需要的高度：作业类型选择加上所有可见行（每行 40 px，`InGameMenuMapFrame:setActiveJobTypeSelection` decompiled `gui/InGameMenuMapFrame.lua:1403-1451`；只有车辆的那组隐藏），限制在 40–320 px。表单底边固定在“加入队列”上方（页面内 597 px），地点列表从 139 px 开始占用表单以上的全部空间：田地工作、前往 120 px → 列表 330 px（约 10 行），运送 280 px，装载和运送 320 px → 列表 130 px。两个框都以上边为锚（`anchorTopLeft`/`anchorTopStretchingX` 的 pivot 为顶边），改尺寸不移动上边。2026-10-25 维护者要求。

**帮手作业中规划田地工作**：`MF.withPlanning` 除了遮蔽 `getIsAIActive`，对有 `spec_aiFieldWorker` 的车辆还遮蔽 `getCanStartFieldWork`，按空闲时的规则（有 AI 农具即可）回答。原版在田地工作进行中返回 false（`spec.isActive`，decompiled `vehicles/specializations/AIFieldWorker.lua:320-327`），田地工作因此被视为不可用，地点预填和双击都退回“前往”；队列里后面的作业只开到田地就结束。2026-10-25 维护者游戏内反馈后修正，测试替身按原版链路判断田地工作是否可用（`getCanStartFieldWork` 与 `getIsAIActive`）。

**双击加入**：地点列表设 `onDoubleClick="onDoubleClickPlace"`（SmoothList 原生回调，SDK `gui/elements/SmoothListElement.lua:138/1546-1550/1598-1600`：第二次点击先触发双击，再按普通点击处理）。田地或合同、且预填的是田地工作（车辆能做田地工作）、不在编辑中时，`prefill` 后走与“加入队列”相同的 `submit(false)`（同样验证、队列满提示、空闲时自动开始）；站点和“前往”只预填。随后的普通点击再预填一次同一地点，无副作用。SmoothList 用 `self.target.time` 判断两次点击间隔（`doubleClickInterval` 400 ms），列表的 target 是页面，所以 `MHPage` 自己维护 `time`（`new` 置 0，`update(dt)` 累加），就像 `ScreenElement`；缺少它时第二次点击会在 `self.target.time - ...` 处出错（Codex 审计 4 发现）。测试中的 `list:mouseClick` 按 SDK 的这段逻辑模拟。2026-10-24 维护者要求。

**合并的田地**：游戏没有“合并”记录，每个田地编号始终是一个 `Field`；玩家把两块田之间的地带耕作后，它们在地面上连成一片。`MHFieldNeeds.getIsGroundConnected` 沿两块田位置点之间的直线每个密度图格子读一次地面类型层（步长为 `terrainSize / getDensityMapSize(map)` 的 0.9 倍，`map` 来自 `fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)`，decompiled `field/FieldGroundSystem.lua:500-507`，`getDensityMapSize` 用法见 decompiled `FSBaseMission.lua:1300`；读不到时 0.5 m。之前每 4 m 一次，会跨过 2 m 宽的未耕地带把两块田误合并，Codex 审计 4 发现）（`fieldGroundSystem:getValueAtWorldPos(FieldDensityMap.GROUND_TYPE, x, 0, z)` + `FieldGroundType.getTypeByValue`，与 `FieldState:update` 相同，decompiled `field/FieldState.lua:110-111`），全程都是田地地面（不是 NONE）就算合并；超过 800 m 不检查，遇到第一处 NONE 即停。两块田轮廓（`field:getDensityMapPolygon():getVerticesList()`，decompiled `densityMaps/DensityMapPolygon.lua:67-77`）的包围盒相距超过 30 m（`MERGE_BOUNDS_GAP`）时不采样，包围盒按田地缓存。`MHPage.mergeFieldItems` 用并查集把本农场所有田地分组（也可经第三块田连通），显示为“田地编号 3 + 4 + 5”，面积相加；分组在按需求筛选之前，所以一组保留全部田地的农田编号，任何一块田上的帮手都会标记整组（Codex 审计 4 发现先筛选再分组会丢掉标记）。“我的田地”取第一块田的位置和状态；“需要此作业的田地”只要组内任一块田需要作业就列出，位置和需求取第一块需要作业的田。每对结果缓存 60 s（`MERGE_CACHE_TIME`），列表每 10 s 刷新时不重复采样。凹形田地的直线可能穿出田外，这时仍分开显示。游戏自己的边界检测（`field/course/BoundaryDetectionTask.lua`）是后台任务，代价太高，不用于列表。2026-10-24 维护者游戏内反馈合并的田地各自出现在需求列表里后加入。

**组合的作业**（`MHFieldNeeds.getWorks`）：遍历 `vehicle:getRootVehicle():getChildVehicles()`（SDK `vehicles/Vehicle.lua:3010/3022`，列表含根车辆）中每台车的 specialization 表，并按各农具自己的设置：`spec_plow` → 犁地；`spec_cultivator` → 耕地；`spec_sowingMachine` → 播种，`useDirectPlanting`（SDK `SowingMachine.lua:168`）或组合中有耕作机时也播在收获后/草地地面（`AI_OUTPUT_GROUND_TYPES`，SDK `SowingMachine.lua:1224-1247`）；`spec_roller` 只在 `isSoilRoller` 时算镇压（SDK `Roller.lua:112-123/198-219`，纯草地镇压器没有可判断的需求）；`spec_weeder` 按 `isHoeWeeder`（SDK `Weeder.lua:87`）区分除草机/锄；`spec_mulcher` → 粉碎；`spec_stonePicker` → 捡石；`spec_fruitPreparer.fruitTypes`（SDK `FruitPreparer.lua:99-110`）→ 去茎叶（这些作物）；`spec_mower.fruitTypeConverters`（SDK `Mower.lua:156-162`，以作物类型为键，值为 `{fillTypeIndex, conversionFactor}`，1.25 decompiled `fruits/FruitTypeManager.lua:98-112`）→ 割草，但只取转换结果不是秸秆（`FillType.STRAW`）的作物：原版 MOWER 转换表还把小麦、大麦、燕麦、油菜、大豆转换为秸秆（`data/maps/maps_fruitTypes.xml:59-67`），割草机能从谷物割出秸秆，但那不是割草作业；原版割草合同也只针对牧草（decompiled `missions/field/MowMission.lua:98-105`）。2026-10-24 维护者游戏内反馈割草机的“需要此作业的田地”不对后修正；`spec_cutter.fruitTypeIndices` 与 `allowsForageGrowthState`（SDK `Cutter.lua:179-182/331`）→ 收割。喷洒机只在有作业区域时算（`spec_sprayer.hasWorkAreas`，SDK `Sprayer.lua:299`；只有药箱的车不算），施肥播种机、施肥耕作机仍按播种/耕地。喷洒内容按游戏开始喷洒时的顺序（SDK `Sprayer.lua:1206-1226`）：自身药箱有内容就用它，否则 `fillTypeSources` 中有支持的喷洒类型且有内容的来源（如前置药箱），两者都空时若装有本仓库的 Fill Type Selector Mod 则用其选择（车辆上的 `spec_FS25_FillTypeSelector.fillTypeSelector` 的 `selectedFillType/defaultFillType`，没有该 Mod 时这张表不存在）；然后 `g_sprayTypeManager:getSprayTypeByFillTypeIndex`（SDK `misc/SprayTypeManager.lua:228`），`isLime` → 施石灰，`isHerbicide` → 除草剂，其余和未知 → 施肥（`:146-148`），并记下喷洒类型的 `sprayGroundType`。

**田地状态**：与地图田地信息框读鼠标下的点相同（MF:674-677），`FieldState.new()`（SDK `field/FieldState.lua:33-55`）+ `FieldState:update(x, z)`（1.24 decompiled `field/FieldState.lua:86-120`，约 12 次单点密度图读取，客户端可用），点取田地自己的位置 `Field:getCenterOfFieldWorldPosition()`（posX/posZ，1.24 decompiled `field/Field.lua:94-96`），这也是游戏为田地记录状态时读取的点（`Field:updateState` → `fieldState:update(self.posX, self.posZ)`，`:194-199`）。最初读的是名称标记 `getIndicatorPosition()`：名称标记只是数字的显示位置，常在田边、地头或没耕作过的条带上，读到的地面为 NONE，整块田被跳过；2026-10-24 维护者游戏内反馈犁和耕耘机的“需要此作业的田地”为空，按存档 `fields.xml` 核对后改为田地位置点。测试替身把名称标记放在田地外，旧读法会让测试失败。`Field.fieldState` 不用：它只在服务器上为无主田地和整地任务后更新（1.25 decompiled `field/FieldManager.lua:363-388/643-670`）。`groundType == FieldGroundType.NONE` 或无效时视为读不到，不加需求。作物 `g_fruitTypeManager:getFruitTypeByIndex`，`FruitType.UNKNOWN`（SDK `fruits/FruitTypeManager.lua:84`）为无作物。

**是否需要**（`MHFieldNeeds.getNeedsWork`；“裸地”= 无作物、生长阶段 0、已收割 `getIsCut` 或枯萎 `getIsWithered`；“可播种地面”= 地面类型值在 `fieldGroundSystem:getSowableRange()` 之间，即灭茬到起垄，`FieldGroundType.getValueByType` 取值，1.24 decompiled `field/FieldGroundSystem.lua:195-196/485-487`、`field/FieldGroundType.lua:19-21`，读不到范围时用 `SowingMachine.AI_REQUIRED_GROUND_TYPES`，同一组类型；“已播种地面”= `getSowingRange()`，播种到垄播，`:197-198/488-490`，读不到时用 SOWN/DIRECT_SOWN/PLANTED/RIDGE_SOWN）。2026-10-25 起，“需要此作业的田地”只列出现在就能做这项作业的田地（维护者要求，例如生长中、可收获的作物上不能施石灰）：条件按游戏自己的作业区域函数（1.25 decompiled `utils/FSDensityMapUtil.lua`，下称 DMU），设置开关仍按信息框；完整核对见被忽略的 `work/audits/field-work-allowed-rules.md`。

| 作业 | 需要的条件 | 依据 |
| --- | --- | --- |
| 犁地 | 裸地且地面不是 PLOWED，并且地面未整（不是 CULTIVATED/SEEDBED/ROLLED_SEEDBED/RIDGE）或 `plowingRequiredEnabled` 且 `plowLevel == 0` | 犁的 AI 地面要求为除 PLOWED 外全部（1.24 decompiled `Plow.lua:5-20`）；信息框“需要犁地”（MF:748） |
| 耕地 | 裸地且地面不是 CULTIVATED/SEEDBED/ROLLED_SEEDBED | 耕作机 AI 地面要求（`Cultivator.lua:3-17`） |
| 播种 | 裸地且地面属于 `SowingMachine.AI_REQUIRED_GROUND_TYPES`；直播或带耕作机时也包括 `AI_OUTPUT_GROUND_TYPES`（收获后、草地等）。另外播种机当前选择的种子（`spec.seeds[spec.currentSeed]`，SDK `SowingMachine.lua:228/331/405-407`，组合中第一台播种机）必须在本期可播：`desc:getIsPlantableInPeriod(missionInfo.growthMode, environment.currentPeriod)`，非季节生长模式总为真；播种机 `getCanPlantOutsideSeason()` 为真时不查（原版为假，`:725-727`）；种子有 `seedRequiredFieldType`（水稻）时，田地位置点的田地类型必须相同 | 1.24 decompiled `SowingMachine.lua:4-21`，SDK `:1224-1247`；季节：SDK `SowingMachine.lua:1017-1036`（不在季节不种）、`:851-866`（AI 以 `AIMessageErrorWrongSeason` 停止），1.25 decompiled `fruits/FruitTypeDesc.lua:707-709`，`growthMode` 见 1.24 decompiled `FSCareerMissionInfo.lua:50`，`currentPeriod` 见 1.25 decompiled `environment/Environment.lua:149`；田地类型：SDK `SowingMachine.lua:541-555`、`FruitTypeDesc.lua:538-541`，DMU:2888-2895（`FSDensityMapUtil.getFieldTypeAtWorldPos`，`FieldDensityMap.FIELD_TYPE` 存在时才读，`getDensityMapData` 可返回 nil，1.24 decompiled `FieldGroundSystem.lua:500-507`）。播种合同的作物判断仍用全部种子 `spec.seeds`。 |
| 镇压（只土壤镇压器） | `Platform.gameplay.useRolling`、`rollerLevel > 0`，作物 `needsRolling` 不为假，且可播种地面（有无作物都行）或已播种地面上作物在第一生长阶段 | DMU:250-325（可播种地面不看作物，已播种地面只第一阶段）；不需镇压的作物播种时镇压等级置 0（DMU:2081，`needsRolling` SDK `FruitTypeDesc.lua:533`）；AI 不进第 2-15 阶段（SDK `Roller.lua:205-216`）。此前不看地面，收获后地面也列出 |
| 施石灰 | `useLimeCounter`、`limeRequired`、`limeLevel == 0`，地面喷洒类型不是石灰的 `sprayGroundType`，且无作物、作物生长阶段 ≤ 1、阶段大于 `maxHarvestingGrowthState`（枯萎、已收割）或可播种地面 | 信息框“需要石灰”（MF:745）；DMU:1398-1466（第一阶段 :1440、超过可收获 :1443、无作物 :1446、可播种地面 :1417/1453；秸秆/玉米切碎标记 :1421 未采用，偏严）；AI 排除已有该喷洒类型的地面（SDK `Sprayer.lua:753-758`）。此前不看作物，生长中的作物也列出（维护者反馈）；收获后的马铃薯（收获阶段在收割阶段之后、地面为已播种）在耕地前不列出 |
| 施肥 | `sprayLevel` 小于最大值，地面喷洒类型不是这种肥料的 `sprayGroundType`，作物未枯萎，且无作物或生长阶段不在 `minHarvestingGrowthState..maxHarvestingGrowthState` 之间 | 信息框施肥百分比（MF:740-742）；DMU:1336-1397（:1354，可收获阶段不施）；枯萎作物仍排除（偏严）；对原版作物与此前“未枯萎、未到可收获”结果相同。AI 排除最大喷洒等级和同种喷洒类型（SDK `Sprayer.lua:744-751`）。比较时把 `sprayGroundType`（密度图值，`FieldSprayType.getValueByName`，decompiled `misc/SprayTypeManager.lua:55`）用 `FieldSprayType.getTypeByValue` 换成类型，再与 `FieldState.sprayType`（类型，decompiled `field/FieldState.lua:112-113`）比较；固态和液态肥料共用 FERTILIZER 地面标记，施过一次后在标记清除前都不再列出。2026-10-24 前直接比较值和类型，施过肥的田仍被列出（维护者游戏内反馈）。 |
| 除草剂 | `weedsEnabled`、`weedState` 在除草剂替换表（`WeedSystem:getHerbicideReplacements`）中，且可播种地面、作物生长阶段在 `1..minHarvestingGrowthState - 1`（含根茎作物的茎叶阶段），或作物在 `wheelDestructionState`（谷物收获后） | 信息框除草剂条件（MF:754-772）；DMU:1467-1545（可播种地面 :1508、可收获前 :1515、车轮压过 :1522-1524；`cutState + 1` 的 :1519 未采用）；AI 要求（SDK `Sprayer.lua:719-741`）。此前“无作物或生长中”：漏掉根茎作物茎叶阶段和收获后的谷物，并列出未耕的无作物地面 |
| 除草 / 锄 | `weedsEnabled`、`weedState` 在该工具的替换表（`getWeederReplacements(isHoe)`）中，除草机要求无作物、`getIsWeedable` 或可播种地面，锄要求无作物、`getIsHoeable` 或可播种地面 | 信息框（MF:765-768）；DMU:1546-1640（可播种地面 :1573；作物 `0..maxWeederState`、`cutState` :1587-1589，本 Mod 仍用 `getIsWeedable/getIsHoeable`，偏严）；AI 要求（SDK `Weeder.lua:209-229`）；1.24 decompiled `field/WeedSystem.lua:203/206` |
| 粉碎 | 作物 `isCultivationAllowed` 不为假，已收割或枯萎，生长阶段在 `2..cutState` 且不等于 `mulchedState`；`Platform.gameplay.useStubbleShred`（PC 为真，1.25 decompiled `platform/Platform.lua:181`）时还要 `stubbleShredLevel == 0`（`FN.readState` 读取，SDK `field/FieldState.lua:49`，1.24 decompiled `FieldState.lua:118`） | DMU:1761-1814（`isCultivationAllowed`、`2..cutState`、非 `mulchedState` :1784-1788，残茬粉碎等级 +1 :1796，等级 1 时收获加成 DMU:141/171-176，`== 0` 为推断）；粉碎机也会毁掉生长中的作物，所以只列收获后和枯萎的。粉碎机 AI 作物要求（SDK `Mulcher.lua:134-146`）。此前要求 `mulchedState ~= 0`，实际只剩牧草（割后即为粉碎状态，什么也不改变），收获后的谷物从不列出；旧测试能通过只因替身中小麦的 `mulchedState` 为 7，现已改为与游戏相同的 0、牧草的 `mulchedState` 等于 `cutState` |
| 去茎叶 | 作物在该去茎叶机的作物列表中且 `getIsPreparable` | 信息框“去除茎叶”（MF:723）；SDK `FruitPreparer.lua:99-123` |
| 割草 / 收割 | 割草：作物在转换表中、转换结果不是秸秆，且生长阶段在 `minHarvestingGrowthState..maxHarvestingGrowthState`；收割：作物在割台列表中，起点为 `allowsForageGrowthState` 时的 `minForageGrowthState`，否则 `minHarvestingGrowthState`，终点 `maxHarvestingGrowthState` | SDK `Mower.lua:224-227`、`Cutter.lua:1537-1538`；`getIsHarvestable` 含青贮阶段（1.25 decompiled `fruits/FruitTypeDesc.lua:483/695`），所以不用它 |
| 捡石 | `stonesEnabled`、可播种地面、`stoneLevel > 0` 且（`stoneLevel` + 掩码值）在 `getMinMaxValues` 之间 | 1.24 decompiled `field/StoneSystem.lua:134-181`；DMU:535-591（只在可播种地面，:558）；捡石机 AI 要求（SDK `StonePicker.lua:139-145`）。此前用“裸地”，收获后、枯萎的作物地面也列出 |

FruitTypeDesc 的判断函数见 1.25 decompiled `fruits/FruitTypeDesc.lua:695-729`；任务开关 `plowingRequiredEnabled/limeRequired/weedsEnabled/stonesEnabled` 见 1.24 decompiled `FSCareerMissionInfo.lua:57-71`。没有用 AI 自己的区域查询（`AIImplement:getFieldCropsQuery` + `AIVehicleUtil.getAIAreaOfVehicle`，1.24 decompiled `vehicles/ai/AIVehicleUtil.lua:381`）：它需要车辆的工作区域和一个平行四边形，且喷洒机、割台的要求只在服务器或 AI 开始时设置。单点判断的局限：田地部分完成时只反映田地位置点（MAP-28）。

“我的田地”的状态文字（`MHFieldNeeds.getStateText`，均为游戏文字）：作物状态按信息框的判断顺序（已收割、枯萎、生长中、去除茎叶、可收获，MF:716-726，青贮阶段因此算生长中），其中可收获、去除茎叶、枯萎排在最前；然后需要石灰、需要犁地、需要镇压（与信息框相同，MF:744-753：石灰只看 `useLimeCounter/limeRequired/limeLevel == 0`，镇压只看 `useRolling/rollerLevel > 0`，不论作物；2026-10-25 起不再经 `getNeedsWork`，那里的作物和地面条件只用于需求列表）；再然后生长中、已收割；否则地面类型（`ui_growthMapStubbleTillage/Cultivated/Seedbed/Plowed/Sown`）。作业名称用游戏的合同标题（`contract_field_plow_title` 等）和信息框文字；粉碎没有游戏文字，用 `mh_workMulch`。

田地图标：`gui.storeAttribute_seeding`（商店“播种”属性的幼苗图标）。原 `gui.icon_others_farmland`（`menu/gui.xml`，135×135 的山丘加标记）缩到 22 px 时像人像。

### 地点

- 合同：`g_missionManager:getMissionsByFarmId(farmId)`（SDK `missions/MissionManager.lua:525`），筛选 `mission.farmId == farmId`、`getIsInProgress()`（`AbstractMission.lua:790`）且有 `getField()`（`missions/field/AbstractFieldMission.lua:86`）；名称 `getTitle()`（`AbstractMission.lua:868`），进度 `mission.completion`（随 `writeUpdateStream` 同步，`:300-311`），状态和位置取合同田地的位置点（同上），没有田地时退回 `getWorldPosition()`（`AbstractFieldMission.lua:98`）。
- 田地：`g_fieldManager:getFields()`（1.25 decompiled `field/FieldManager.lua:394`），`g_farmlandManager:getFarmlandOwner(field.farmland.id) == farmId`（SDK `economy/FarmlandManager.lua:407`，写法同 1.25 decompiled `gui/InGameMenuMobileMapFrame.lua:1113-1125`），按 `getId()` 排序，名称 `ui_fieldNo` + 编号、面积 `g_i18n:formatArea(getAreaHa(), 2)`（同 `InGameMenuMobileMapFrame.lua:1583-1594`）；位置和状态点取 `getCenterOfFieldWorldPosition()`（1.24 decompiled `field/Field.lua:94-96`）。
- 站点：对可用的 LOAD_AND_DELIVER / DELIVER 各建一个临时作业，`applyCurrentState(vehicle, g_currentMission, farmId, false)`（SDK `ai/jobs/AIJobLoadAndDeliver.lua:217-260`、`AIJobDeliver.lua:172-214`）后读 `loadingStationParameter.loadingStationIds`、`unloadingStationParameter.unloadingStationIds`（SDK `ai/parameters/AIParameterLoadingStation.lua`、`AIParameterUnloadingStation.lua` 的 `setValidLoadingStations/setValidUnloadingStations`），`NetworkUtil.getObject` 得到站点，名称 `getName()`，位置取 `owningPlaceable:getHotspot(1):getWorldPosition()`（同 MF:1193-1218）。临时作业用完即丢。

点击地点：有位置时 `ingameMap:setCenterToWorldPosition(x, z)`，然后预填表单：田地/合同 → FIELDWORK（不可用时 GOTO），把 `positionAngle` 参数设到该位置（角度保留）；装载站 → LOAD_AND_DELIVER 并 `setLoadingStation`；卸载站 → 当前是 DELIVER/LOAD_AND_DELIVER 时保留类型，否则优先 LOAD_AND_DELIVER；站点只在其 id 位于参数的有效列表中时才设置，之后调用 `job:onParameterValueChanged(parameter)`（装载站会刷新填充类型，`AIJobLoadAndDeliver.lua:276`）。原来的“作业类型”分组已去掉，表单的作业类型选择器已经包含它。最后 `updateParameterValueTexts` + `validateParameters`（MF:2048/1992），原生的无效提示照常显示。

### 加入、插入为下一个、编辑

- 加入/插入：按 `InGameMenuMapFrame:startJob`（MF:1374-1395）先 `setValues` 再 `validate(g_localPlayer.farmId)`，失败时原生 `InfoDialog` + `updateWarnings`；成功则把 `frame.currentJob` 作为请求发给服务器（主机上按引用交给队列），`currentJob = nil` 后以同一类型重建一个新表单。
- 编辑：选中等待中的条目后“编辑”：以该条目的作业类型重建表单，再把条目作业的参数复制进 `currentJob`：`AIJob:saveToXMLFile` 写入一个只在内存中的 XML（`XMLFile.create`，1.24 decompiled `xml/XMLFile.lua:19`，从不 `save`），`loadFromXMLFile` 读回（SDK `ai/jobs/AIJob.lua:52-79`），之后对每个参数 `onParameterValueChanged`（填充类型保留有效的原值，`AIParameterFillType.lua:64-96`）并 `setValues`。车辆参数没有 `loadFromXMLFile`，保持表单车辆。此时按钮变为“保存”（Z）/“取消”（X，恢复为空白新表单）。保存发送 EDIT，服务器验证方式同添加并替换该条目的作业，条目 id 和位置不变。被编辑的条目在此期间开始或被删除时，编辑状态结束（表单内容保留，可作为新作业加入）。
- 正在执行的作业不能编辑（原生作业运行中参数不可改），它只显示在队列第一行。

### 队列列表与进度

列表第一行是车辆当前的作业：`vehicle:getIsAIActive()` 且 `vehicle:getJob()`（1.24 decompiled `vehicles/specializations/AIJobVehicle.lua:273`；客户端经 `AIJobVehicleStateEvent` → `aiJobStarted` 也设置 `spec.job`，`:182-188`）。标题为 `job:getDescription()`（类型 + 当前任务，如“田地工作 - 正在田地中作业”，`AIJob.lua:327` 与各作业的 `getDescription`），说明为：

- 当前任务有驾驶目标时（`job:getTaskByIndex(job.currentTaskIndex)` 的 `x/z`，`AIJob.lua:314`、`ai/tasks/AITaskDriveTo.lua:25/65`；客户端由 `AITaskStartEvent` 同步任务），车辆 `rootNode` 到目标的距离 `ui_distance: 320 m`（`g_i18n:formatDistance`，1.24 decompiled `I18N.lua:315`）；
- 作业 `positionAngle` 所在 farmland（`getFarmlandAtWorldPosition`，SDK `FarmlandManager.lua:432`）有本农场进行中的合同时，`contract_progress: 45 %`；
- 两者都没有时显示帮手名字（`getHelperName`，`AIJob.lua:334`）。

AI 没有百分比进度，所以不做进度条。之后是等待中的条目：编号、作业类型、目标（田地名或坐标、站点名，用“>”连接）。原生在岗帮手列表每 1 s 刷新描述（MF:592-606），页面同样每 1 s 刷新：行结构不变时只改单元格文字（`getElementAtSectionIndex`，MF:596），有作业开始或结束时重建列表。完成的作业自动消失：队列启动条目时已把它移出队列，作业结束后车辆不再有 `getJob()`，第一行随之消失；服务器的状态事件到达时页面也立即刷新（`MH.addListener`）。

### 规划模式（帮手工作期间安排作业）

原生作业类型只对没有帮手的车辆可用：`AIJobFieldWork:getIsAvailableForVehicle`（SDK `ai/jobs/AIJobFieldWork.lua:167`，经 `getCanStartFieldWork`）和 `AIJobGoTo`（`ai/jobs/AIJobGoTo.lua:92`）都依赖 `AIJobVehicle:getCanStartAIVehicle`（SDK `vehicles/specializations/AIJobVehicle.lua:488-520`），其中 `getIsAIActive()` 为真时返回 false。

车辆有帮手或队列正在运行时，页面在 `MF.withPlanning` 内判断可用类型并调用 `setActiveJobTypeSelection`：给车辆写一个实例字段 `vehicle.getIsAIActive = function() return false end`，遮住 specialization 注册在类型上的函数，回调后恢复 `rawget` 得到的原值；之后再 `refreshContextInput` 一次，让右侧上下文框按真实状态显示。脚本不捕获错误：回调出错时错误进入日志，遮蔽记在 `MF.planningShadow`，由下一帧 `MapHelper:update` 开头的 `MF.restorePlanning` 去掉。`validate` 不检查帮手状态（`AIParameterVehicle:validate`，SDK `ai/parameters/AIParameterVehicle.lua:86-97`），加入时无需遮蔽。

服务器端（`MH.serverAdd` → `MH.followCurrentJob`）：加入一项后，如果队列不在运行而车辆 `getIsAIActive()` 为真，就用 `vehicle:getJob()` 取当前作业，设 `queue.running = true`、`queue.runningJob = current`；之后的完成判断与队列自己启动的作业相同。

### 自动开始、继续与取消

- **有人坐着的车辆**：玩家要求的开始（加入作业触发的自动开始、继续队列）用请求者自己的连接做原生 `getIsStartable` 检查（`Enterable:getIsInUse`，SDK `vehicles/specializations/Enterable.lua:1663`；`AIJobGoTo.lua:205-213`），所以别的玩家坐着的车辆按游戏自己的“正在使用”原因被拒，作业留在队首、队列以 START_FAILED 暂停，卡片显示该类型的 `getIsStartErrorText`。只有请求者就是车里的人（同一连接，或 `userManager:getUserIdByConnection(请求者) == spec_enterable.controllerUserId`，1.24 decompiled `users/UserManager.lua:90`、SDK `Enterable.lua:217/936`）时才改用车内的连接，以免自己的座位被算作占用。队列完成一项后自己推进时（没有请求者），沿用车内的连接：这些作业已在之前排好。
- **自动开始**（`MH.serverAdd`）：加入（ADD，包括插入为下一个）后，如果队列不在运行（`queue.running` 为假）且车辆没有帮手，服务器立即 `MH.startNext`，新加入的作业（或队首）成为正在执行的作业。两项之间的 1.5 s 间隔内队列仍是运行状态，新作业只排队；车辆有帮手时队列照旧跟随当前作业。
- **暂停后加入**：选择让加入**继续**队列：暂停原因清除，从队首（最早等待的作业，不一定是新加入的）开始。理由：玩家加作业就是想让车辆干活；若暂停原因未解决，开始会再次失败并按原规则暂停、提示原因，等待的作业不丢。
- **继续队列**：没有加作业也能继续——队列标题旁的“继续队列”（`mh_resumeQueue`，发送原有的 START 请求）只在有等待作业、没有帮手且队列不在运行时显示（暂停后或读档后）。读档后的队列同样等待“继续队列”或新作业；期间车辆上开始的帮手作业会被跟随（下文“读档后跟随帮手”）。
- **取消当前作业**：原“开始队列/取消作业”按钮已去掉。队列第一行（当前作业）被选中时，条目按钮“删除”显示为“取消作业”（`button_cancelJob`），调用与 `InGameMenuMapFrame:cancelJob`（MF:1396-1402）相同的 `vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())`；队列按“玩家停止”暂停，“继续队列”可继续。右侧原生上下文框的“取消作业”和车内 H 键同样有效。`mh_startQueue`（“开始队列”）已删除。

### 队列、请求与完成判断

队列只存在服务器上，按车辆存放，每辆最多 10 项，每项有服务器分配的 id。请求动作（`MH.ACTION`，3 bit）：ADD=1、REMOVE=2、CLEAR=3、START=4、MOVE=5、EDIT=6。

`MHQueueRequestEvent` 流格式：动作（UIntN 3）、车辆（`NetworkUtil.writeNodeObject`），然后

| 动作 | 内容 |
| --- | --- |
| ADD | 插入为下一个（bool）、作业类型索引（UInt16）、原生 `AIJob:writeStream` |
| EDIT | 条目 id（Int32）、作业类型索引（UInt16）、原生 `AIJob:writeStream` |
| MOVE | 条目 id（Int32）、上移（bool） |
| REMOVE | 条目 id（Int32） |
| CLEAR、START | 无 |

服务器校验：车辆存在且支持 AI、请求者农场等于车辆所属农场、`getHasPlayerPermission("hireAssistant", connection, farmId)`。ADD 和 EDIT 都经 `MH.getIsValidRequestJob`：作业的 vehicle 参数就是该车辆、清掉随请求来的帮手设置（见下）、`setValues` + `validate(farmId)`。ADD 未超过上限，插入为下一个时放在位置 1；EDIT 找不到条目（已开始或已删除）时拒绝；MOVE 在首/尾越界时不变。状态事件 `MHQueueStateEvent` 格式不变（农场、运行中、暂停原因、条目 id + 作业），当前作业不在其中，客户端从车辆读取。

开始（自动开始、继续队列）时服务器对第一项 `setValues`、`validate(farmId)`，再用原生 `job:getIsStartable(connection)` 检查（AI 上限、车辆存在、hireAssistant、车辆是否被占用）；connection 见上文“有人坐着的车辆”（`MH.getStartConnection`）。通过后才从队列移除并 `g_currentMission.aiSystem:startJob(job, farmId)`。

完成判断订阅 `MessageType.AI_JOB_STOPPED`（`AISystem:stopJobInternal` 发布 `job, aiMessage`，SDK `ai/AISystem.lua:583-589`），只处理队列启动或跟随的那个作业：`AIMessageSuccessFinishedJob`（`AIJob:update`）和 `AIMessageSuccessSiloEmpty`（`AIJobLoadAndDeliver.lua:411`）算成功，还有下一项时 1500 ms 后启动（原生作业在下一次 `AISystem:update` 才移除），并且要等组合停稳（下文“推进前等待组合停稳”）；其他消息和 nil 让队列暂停并提示。启动失败：`validate` 失败记为“下一个作业无法按计划开始”，`getIsStartable` 失败记下原生状态码，客户端用该类型的 `getIsStartErrorText(state)` 显示原因；失败项留在队首。车辆删除时队列删除；车辆所有者变化时清空并广播。

### 田地作业的帮手设置

`AIJobFieldWork:readStream`（SDK `ai/jobs/AIJobFieldWork.lua:53`）把发送方的设置读进 `pendingData/pendingVehicle`，首次 `update` 时应用；`writeStream`（`:64`）写车辆当时的设置；`AIJob:saveToXMLFile` 不保存设置。排队作业一律使用**开始时车辆的设置**：服务器收到请求时、开始前和客户端读状态时都调用 `MH.useVehicleSettingsAtStart` 清掉 `pendingData/pendingVehicle`。

### 多人

请求经 `MHQueueRequestEvent` 发往服务器；主机上 `Connection:sendEvent` 走本地流直接 `run`，主机和客户端同一路径，客户端不做乐观更新。每次变化后服务器 `broadcastEvent(event, false, nil, vehicle)`（只发给已有该车辆的连接）；加入游戏时在 `FSBaseMission:sendInitialClientState` 之后发送全部队列。暂停/完成提示只给车辆所属农场的玩家。

### 已知局限（不修，2026-10-25 Codex 审计 5）

- 原生停止事件没有权限检查：`AIJobStopEvent` 从客户端读入作业 id 和 AI 消息，服务器直接 `aiSystem:stopJob`，不检查发送者的农场和权限（SDK `ai/events/AIJobStopEvent.lua:35-46/62-69`、`ai/AISystem.lua:570-587`）。被修改的客户端可以用“作业完成”消息停止别的农场的作业，本 Mod 收到 `AI_JOB_STOPPED` 后按成功推进队列。原版界面不会发这样的事件；这是游戏自己的缺口，本 Mod 的请求检查（`MH.handleRequest`）不经过这里。
- 服务器拒绝的请求没有回复：页面在发出请求后立即清空表单（`MHPage:submit`），`MHQueueRequestEvent:run` 不回送结果。两个客户端在同一往返内向只剩一个空位的队列各加一项时，后到的被服务器拒绝，该玩家的表单已清空且没有提示；所有端最终显示同一个队列（服务器广播）。

### 存档

追加在 `FSCareerMissionInfo:saveToXMLFile` 之后（服务器、存档有效时），写存档目录的 `mapHelper.xml`，没有队列也覆盖。格式与 `AIJobVehicle:saveToXMLFile` 保存 lastJob 相同：作业类型名 + 原生 `AIJob:saveToXMLFile` 参数，按车辆 `uniqueId` 分组。读取在 `FSBaseMission:onStartMission` 之后：`getVehicleByUniqueId`、`getJobTypeIndexByName` + `createJob`、`loadFromXMLFile`，车辆参数用 `setVehicle` 补上；找不到车辆或作业类型的项丢弃并写一行 info。读档后不自动开始。

**不完整的条目（2026-10-25，Codex 审计 5）**：文件仍是有效 XML、却缺少某个作业的位置或方向时（手改或损坏），新建作业的位置和方向为 nil（`AIParameterPosition.new`、`AIParameterPositionAngle.new`，SDK `ai/parameters/AIParameterPosition.lua:16-25`、`AIParameterPositionAngle.lua:16-26`），`loadFromXMLFile` 只读存在的属性（两者 `:38-42`），随后 `AIJobGoTo/AIJobFieldWork:setValues` 把 nil 方向交给 `MathUtil.getDirectionFromYRotation`（SDK `ai/jobs/AIJobGoTo.lua:147-157`、`AIJobFieldWork.lua:199-211`；decompiled `utils/MathUtil.lua:228-229`，`math.sin(nil)`）抛错，追加在 `onStartMission` 之后的读取中断，任务开始流程随之中断。现在 `loadFromXMLFile` 之后、`setValues` 之前由 `MH.getHasSavedTargets` 检查：作业的每个 `POSITION`/`POSITION_ANGLE` 参数都有 x、z，`POSITION_ANGLE` 还有角度，否则丢弃该项（计入同一行 info）。站点、填充类型缺失不会抛错：`AIJobDeliver/AIJobLoadAndDeliver:setValues` 在没有站点时提前返回（SDK `AIJobDeliver.lua:69-79`、`AIJobLoadAndDeliver.lua:73-88`），开始时 `validate` 失败，队列按“无法按计划开始”暂停，与其他失效作业相同。测试替身的 `setValues` 同样经 `getDirectionFromYRotation`，回归测试去掉检查后抛出同样的错误。

**读档后跟随帮手（2026-10-25）**：维护者反馈重启游戏读档后，队列只执行了第一个作业，之后不再自动开始下一个。核对（2026-10-25 按 Codex 审计 5 改写，原文据 1.24 代码断言“原版不会重新开始”）：作业本身不存档——`AIJobVehicle:saveToXMLFile` 只保存 `lastJob`（作业菜单的预填模板，1.24 decompiled `vehicles/specializations/AIJobVehicle.lua:434-442`，读取 SDK `AIJobVehicle.lua:113-151`），`AISystem:save` 只写调试目标（SDK `ai/AISystem.lua:421-444`）。但田地工作的帮手可能被游戏重新开始：1.25 SDK `AIFieldWorker:saveToXMLFile` 仍保存 `isActive`（`vehicles/specializations/AIFieldWorker.lua:202-206`）；1.24 decompiled 中 `onLoad` 读取它并设 `pendingAIFieldWorkerStart`（`AIFieldWorker.lua:135-143`），服务器上的 `onUpdate` 随后在车辆当前位置和朝向建一个 FIELDWORK 作业并发送 `AIJobStartRequestEvent`（`:181-191`）。1.25 SDK 的 `AIFieldWorker.lua` 没有 `onLoad/onUpdate`，1.25 decompiled 没有这个文件，所以 **1.25 是否仍这样重启无法从参考代码确认**；前往、运送等其他作业没有类似的保存。维护者看到的“读档后只执行了一个作业”与游戏重启田地工作帮手相符，但也可能是玩家自己或其他 Mod（维护者的 `log.txt` 中同时加载了 HiredHelper Tool、Courseplay、AutoDrive；本 Mod 不读取 mods 目录，未核对它们）开始的。README 原来写“保存时正在工作的帮手不会重新开始，与原版相同”，与 1.24 代码不符，已改为列举这几种情况。原来只有“加入作业”时才跟随车辆当前的作业，读档后的队列不跟随这样开始的作业，作业结束时 `MH:onAIJobStopped` 找不到对应队列，等待的作业不再开始。现在：服务器订阅 `MessageType.AI_JOB_STARTED`（`AISystem:startJobInternal` 对每次开始发布，SDK `ai/AISystem.lua:561-566`；此时 `aiJobStarted` 已设好车辆的作业），有等待作业、未运行且**未暂停**的队列（即读档后的队列）跟随该作业，作业完成后照常推进；读档时车辆已有帮手（在队列读取之前开始）也同样跟随。暂停的队列仍不跟随玩家直接开始的作业，等“继续队列”。“继续队列”路径本身没有问题，测试同样覆盖。

**推进前等待组合停稳（2026-10-25）**：维护者反馈 Hardi MEGA 1200L（安装目录 `data/vehicles/hardi/mega1200L/mega1200L.xml`，一个折叠部件，`startMoveDirection="1"`，即折叠状态为 1、`turnOnFoldDirection = -1`，SDK `Foldable.lua:368-387`）在队列自动开始下一个田地工作（另一块田）时，喷杆没收完帮手就上了路；手动开始原生“前往”时完全折叠后才走。原版代码中两条路径相同：`AITaskDriveTo:start` 调用 `prepareForAIDriving`（`onAIImplementPrepareForTransport`，折叠动作 -1，SDK `AIDrivable.lua:1028-1030`、`Foldable.lua:2272-2276`），`AITaskDriveTo:update` 在 PREPARE_DRIVING 中等 `getIsAIReadyToDrive`（SDK `ai/tasks/AITaskDriveTo.lua:88-103`），`Foldable:getIsAIReadyToDrive` 对该喷雾机要求 `foldAnimTime == 1`（`:2174-2190`），`AIDrivable:getIsAIReadyToDrive` 检查组合中每台车（`:620-633`）；PC 上 `foldAfterAIFinished` 为假（decompiled `platform/Platform.lua:204`），作业结束时不折叠。原版脚本里没有找到队列开始与手动开始的区别（唯一不同是队列在 `AI_JOB_STOPPED` 后 1.5 s 开始、作业类型为田地工作）；其他已加载 Mod 的影响无法核对。按维护者批准的保护措施：`MH:update` 在 1.5 s 之后再等组合停稳才 `startNext`——根车辆 `getLastSpeed()` 低于 1 km/h（SDK `vehicles/Vehicle.lua:2587-2595`，AIDrivable 以 < 1 km/h 视为停住，`AIDrivable.lua:265`），`getRootVehicle():getChildVehicles()` 中没有 `spec_foldable.foldMoveDirection ~= 0` 的车（`setFoldState` 设置、`onUpdate` 到位后清零，`Foldable.lua:816-830/594-608`，折叠和中间位置升降都在其中），也没有正在升降的挂接点（车辆激活时 `attachedImplements` 对应 `attacherJoints[jointDescIndex].isMoving`，`setJointMoveDown` 置真、`onUpdateTick` 只在 `getIsActive()` 时移动并清除，`AttacherJoints.lua:3276-3284/1056-1075`；同 `getIsAutomaticShiftingAllowed` 的写法，`:4151-4163`）。`queue.delay` 低于 0 后记录额外等待，最多 `MH.SETTLE_TIMEOUT` = 20 s，之后照常开始；等待中车辆又有帮手时仍按“玩家停止”暂停。玩家要求的开始（加入第一个作业、继续队列）不等待。

**诊断日志（2026-10-25，Codex 审计 5）**：审计认为上面的等待通常立即通过（作业结束时 PC 上不折叠，`foldMoveDirection` 在中间位置停住后也是 0，`Foldable.lua:591-608`），解释不了这个现象；它可能的原因是 `AIJobFieldWork:getStartTaskIndex` 在车辆离目标点不到 3 m 时返回 2，跳过驾驶任务（SDK `ai/jobs/AIJobFieldWork.lua:90-104`，`AIJob:update` 在作业第一次更新时调用，`AIJob.lua:117-126`），也就没有 `prepareForAIDriving` 和 `getIsAIReadyToDrive` 的等待。等待保留，另加两行 `Logging.info`，只针对队列自己开始的作业（完成上一项后的推进，不含加入作业或“继续队列”触发的开始）：

- 开始时（`MH.logQueueStart`，`startJob` 之前）：`[Map Helper] Queue starts <作业类型> on <车辆>: <距离> to target, start task <n>; <折叠状态>`。距离为车辆 `rootNode` 到作业 `positionAngle`（或 `position`）参数的平面距离；`start task` 只对原版 FIELDWORK 调用 `job:getStartTaskIndex()`（该函数只读车辆和目标，开始前调用无副作用），其他类型（含其他 Mod 的类型）写 `-`。
- 驾驶任务开始行驶时（追加在 `AITaskDriveTo:startDriving` 之后，服务器在 `PREPARE_DRIVING` 中 `getIsAIReadyToDrive` 通过后调用，SDK `ai/tasks/AITaskDriveTo.lua:88-104/135-151`；任务的 `job` 字段见 `ai/tasks/AITask.lua:16-26`）：`[Map Helper] Queue job <作业类型> on <车辆> starts driving; <折叠状态>`。只记录 `queue.autoStartedJob` 且仍是 `runningJob` 的作业。
- 折叠状态：组合中每台有 `spec_foldable` 的车：`<名称> foldAnimTime=<0..1> foldMoveDirection=<-1/0/1> turnOnFoldDirection=<-1/1>`（SDK `Foldable.lua:369-387/441`），没有时为 `no foldable vehicle`。

维护者在 `log.txt` 中看：Hardi 这类 `turnOnFoldDirection=-1` 的农具，`foldAnimTime=1` 为完全折叠（运输状态），0 为完全展开。若开始行为 `start task 2`（离目标不到 3 m），后面不会有 “starts driving” 行，帮手直接以田地工作开始，跳过了运输准备；若有 “starts driving” 行而其中 `foldAnimTime` 不是运输端点，则是原版就绪检查放行了未折叠的状态；若开始行为 `start task 1`，但没有 “starts driving” 行而帮手已开走，则是别的路径（例如其他 Mod）在驾驶。

### 退出存档时的清理（含退出失败修复）

**修复（2026-10-21 之后）**：维护者日志中每次退出存档都报 `dataS/scripts/ai/jobs/AIJob.lua:43: attempt to call missing method 'delete' of table`，无法离开存档。原因：原生 `AIJob:delete`（SDK `ai/jobs/AIJob.lua:41-48`）对每个参数调用 `parameter:delete()`，而 `ai/parameters/` 下没有任何类实现 `delete`，游戏自己也从不调用 `job:delete()`；旧的 `MH.deleteJob` 在 `FSBaseMission:delete` 的前置钩子里经 `deleteQueue` 调用了它，错误中断了游戏的退出流程（删除、拒绝、清空、替换条目时也会报同样的错）。现在：

- 任何作业都不再 `delete`，只丢弃引用（`MH.clearEntries`、删除条目、拒绝请求、编辑替换），与原生对结束作业的处理相同；`AITask:delete`（SDK `ai/tasks/AITask.lua:30`）原生也不为作业调用，故不调用。
- 替身中作业的 `delete` 与游戏一样抛出该错误，测试中任何残留调用都会失败；回归测试“quitting with queued jobs…”在有排队、运行中、删除和编辑过的条目时执行完整的任务删除。
- `FSBaseMission:delete` 删除 AI 系统时会停止所有进行中的作业并发布 `AI_JOB_STOPPED`（SDK `ai/AISystem.lua:97/587`）；`MH:onAIJobStopped` 在任务未激活时直接返回，退出时队列不暂停、不发提示、不广播（替身同样在删除时发布该消息，退出测试检查无反应）。
- `FSBaseMission:delete` 的前置钩子只设 `MH.missionActive = false`（不可能出错），本 Mod 所有钩子和回调都检查它，因此原生拆除过程中（如 `g_inGameMenu:reset()` → `InGameMenuMapFrame:reset` → `setMapSelectionItem(nil)`，1.25 decompiled `FSBaseMission.lua:169`、MF:511-518）不会运行本 Mod 代码。其余清理放在追加钩子中，在游戏自身的拆除之后执行，且只做有 nil 检查的 GUI 操作和表清理，不调用已删除任务的函数（不取消选点、不移除地图标记、移除 updateable 前检查表存在）。没有用 pcall（ModHub TestRunner），追加钩子若仍出错，游戏的拆除已经完成。

`g_inGameMenu` 只在启动时创建一次（1.25 decompiled `main.lua:550` → `gui/InGameMenu.lua:31-32`），地图页及本 Mod 加的元素会跨存档保留，所以拆除时（`MF.remove`）：删除页面根元素和底部按钮栏中的“地图助手”项（`GuiElement:delete`，SDK `:453`，同时从父元素和 FocusManager 移除）；原生作业容器恢复 profile `fs25_subCategoryListContainer`、位置、隐藏，`buttonStartJobContainer` 恢复可见；从 `mapSelectorTexts` 删除本页文字并 `setTexts`，页面正显示时选择器回到状态 1；删除克隆的圆点并 `invalidateLayout`；删除 `dataTables` 等该状态的表项；恢复选择器原 `onClickCallback`；按目标移除按键事件（地图页事件和全局热键）；退订消息、移除 updateable、清空队列和监听器。下一个启用本 Mod 的存档在 `onLoadMapFinished` 时重新创建；frame 上若残留旧脚本副本的控件，会先删除再注入。

### 防护

`Register.lua` 在加载时检查全部依赖，分三组：队列（AI 系统、作业、存档）、页面（地图页各函数、`g_gui`、`InfoDialog` 等，依赖队列）、热键（`PlayerInputComponent.registerGlobalPlayerActionEvents`、`InGameMenu.openMapOverview`、`InputAction.MH_OPEN_MAP_HELPER`，依赖页面）。缺失时只关闭对应功能，用 `Logging.warning` 记一次 `[Map Helper] ... disabled`，不安装相关钩子。地图页头部找不到时只跳过按钮。脚本不用 pcall/xpcall。

### 按键

- 地图页：`MENU_EXTRA_1`（键盘默认 X，`profileTemplate/inputBindingDefault_KeyboardMouse.xml:428-430`；手柄 `BUTTON_11`，`inputBindingDefault_Gamepad.xml:380-382`）。PC 地图页和游戏菜单都不为它注册事件（`registerInput` MF:2357-2368，`CLEAR_INPUT_ACTIONS` MF:2589-2594）。事件追加在 `InGameMenuMapFrame:registerInput` 之后注册（先按目标移除）。不在页面时切换到页面（底部按钮栏的“地图助手”项显示此键），并让给其他可见的同键按钮（Precision Farming 土壤图层的“帮助”，`ScreenElement.callButtonsWithAction`，1.24 decompiled `gui/elements/ScreenElement.lua:74-87`）；在页面上为“插入为下一个”，编辑时为“取消”。按钮栏项在页面上、原生作业菜单中（`AI_MODE_CREATE`）和有其他可见同键按钮时隐藏，因此同一时刻只有一个按钮显示 X。
- 底部按钮栏（2026-10-25 维护者要求，取代余额下方的按钮）：地图页 `hasFullScreenMap = true`（1.25 decompiled MF:48），`InGameMenu:updateButtonsPanel` 因此隐藏并禁用菜单自己的 `buttonsPanel`（1.25 decompiled `gui/InGameMenu.lua:533-540`），`TabbedMenuFrameElement:setMenuButtonInfo`/`setMenuButtonInfoDirty`（SDK `gui/elements/TabbedMenuFrameElement.lua:58-68`，由 `TabbedMenu:update`/`updateButtonsPanel` 读取，SDK `gui/base/TabbedMenu.lua:187-207/618-625`）写入的就是这个被隐藏的面板，地图页上看不到。地图页显示的是它自己的 `buttonBox`（`dataS-archive/gui/InGameMenuMapFrame.xml`：`BoxLayout profile="fs25_buttonBox"`，子元素依次为 `buttonBack`、`buttonNext`、`buttonPrev`、移动/缩放图标文字、切换车辆、`buttonSelectIngame`；`fs25_buttonBox` 右对齐、`fillDirectionX=rightToLeft`、`autoValidateLayout`，`dataS-archive/guiProfiles.xml`），`TabbedMenu:updateButtonsPanel` 只把它重新加到父元素末尾以绘制在最上层。所以本 Mod 用 `MF.loadElements` 把 `gui/MenuBarButton.xml` 的按钮加进 `frame.buttonBox`，移到 `buttonPrev` 之后（即“上一页”左侧），文字 `mh_toggle`，`inputAction` `MENU_EXTRA_1` 显示 X 图标；`BoxLayoutElement` 跳过隐藏元素（SDK `gui/elements/BoxLayoutElement.lua:304-306`），隐藏后 `invalidateLayout`，原生 `updateInputGlyphs` 同样如此（MF:1973-1991）。可见性在 `onClickMapOverviewSelector`、`setJobMenuVisible`、`registerInput` 之后立即更新，并标记在下一帧 `update` 再查一次（其他 Mod 的同名钩子可能在本 Mod 之后才显示或隐藏自己的按钮，例如 PF 的“帮助”在它自己的 `onClickMapOverviewSelector` 覆盖中切换，1.24 decompiled `FS25_precisionFarming/scripts/gui/InGameMenuMapFrameExtension.lua:276-307`）。**按键只走一条路径**：游戏菜单在地图页的自定义上下文中也注册 `Gui.NAV_ACTIONS`（含 `MENU_EXTRA_1`，1.24 decompiled `gui/base/Gui.lua:11-27`；`Gui:toggleCustomInputContext` → `enterMenuContext` → `registerMenuInput`，`:632-636/657`，SDK `Gui.lua:646-686/1032-1036`），`Gui:notifyControls` → `ScreenElement:inputEvent` → `callButtonsWithAction` 会触发第一个可见、`isTriggerableByGlobalAction`（ButtonElement 默认 true，1.24 decompiled `ButtonElement.lua:28`）且动作相同的按钮；按钮栏项的 profile 设 `isTriggerableByGlobalAction=false`，与页面按钮相同，X 只由本 Mod 在 `registerInput` 中注册的事件（`MF.onKeyAction`）处理，鼠标点击走按钮的 `onClick`（`MF:onClickBarButton`）。若改用 menu button info，`TabbedMenu:assignMenuButtonInfo` 对 `MENU_EXTRA_1`（`TabbedMenu.DEFAULT_BUTTON_ACTIONS`，1.24 decompiled `TabbedMenu.lua:5-12`）只存 `buttonActionCallbacks`（SDK `TabbedMenu.lua:387-394`），由 `onClickMenuExtra1` 调用，按钮却不显示，因此不用。
- 页面“加入队列/保存”：`MENU_MAP_ACTION_1`，即原生“开始作业”的键（`fs25_mapButtonAction1`，键盘 `KEY_z`，`inputBindingDefault_KeyboardMouse.xml:452-454`；手柄 `BUTTON_1`，`inputBindingDefault_Gamepad.xml:404-406`）。由追加在 `onMenuMapAction1` 之后的钩子处理，原生部分在页面上不动作（见上）。按钮上的键位图标只显示组合键的第一个键（`ButtonElement:loadInputGlyph`，1.24 decompiled `gui/elements/ButtonElement.lua:199-219`），所以页面只用单键动作。这两个菜单 action 在 `inputActions.xml` 中为 `locked="true"`，控制设置里不能改（MAP-16）。
- 全局热键 `MH_OPEN_MAP_HELPER`：modDesc `<actions>` 中 `category="SYSTEM"`（与 `TOGGLE_MAP`、`TOGGLE_STORE` 相同，`dataS-archive/inputActions.xml`），`<inputBinding>` 默认 `KEY_lalt KEY_m`。在安装目录的默认键位表中，左 Alt 只与 P、F、X、N 组合（`inputBindingDefault_KeyboardMouse.xml:101/177/217/1010`），单独的 M 只用于车辆的轴（前装载机、起重机等，`:312` 起），而 InputBinding 对当前上下文中键集合为另一绑定子集的绑定标记 `isShadowed` 并跳过（1.25 decompiled `input/InputBinding.lua:2329-2354/2423`），按 Alt + M 不会同时触发 M；左 Ctrl 单独是蹲下（`:48`），所以不用 Ctrl 组合。键盘修饰键不是 combo（combo 只指鼠标键和手柄肩键，`:150-209`），因此组合键不需要 `ignoreComboMask`。注册追加在 `PlayerInputComponent:registerGlobalPlayerActionEvents(context)` 之后：游戏在步行时（`PLAYER` 上下文：玩家创建时和按键表变化时，1.25 decompiled `player/PlayerInputComponent.lua:56-59`，SDK `player/PlayerInputComponent.lua:145-155`）和每次进入车辆时（`Enterable:onRegisterActionEvents` 以 `VEHICLE` 调用，SDK `vehicles/specializations/Enterable.lua:1711`）注册菜单、地图、商店等全局动作，本 Mod 的事件与之同处；上下文处理照抄该函数（目标上下文不同时先 `beginActionEventsModification(context)`，之后切回）。同一上下文重复注册由 `registerActionEvent` 拒绝（`InputBinding.lua:640-643`）。事件文字可见、优先级 `GS_PRIO_VERY_LOW`，F1 按键帮助中显示 `input_MH_OPEN_MAP_HELPER`（`InputBinding.lua:1355-1381` 从 Mod 的 l10n 读取）。回调按 `PlayerInputComponent:onInputToggleMap`（`:408-423`）的条件（输入锁定、同步中、导览中不打开），调用 `g_inGameMenu:openMapOverview()`（`gui/InGameMenu.lua:570-577`；`Gui:changeScreen` → `TabbedMenu:onPageChange` → `onFrameOpen` 同步执行），再像 `openFarmlandsScreen`（`:589-592`）那样 `mapOverviewSelector:setState(页面状态, true)`。骑马（`ANIMAL_LOAD_EMPTY` 上下文）不在其中。

## FS25 1.25 接口核对

2026-10-21 只读核对。`work/reference/1.25.0.0/` 下：`gameSource/` 为随游戏 SDK 的可读 Lua（部分函数体被裁掉），`decompiled/scripts/` 为 1.25 反编译，`dataS-archive/` 为从安装目录 `dataS.gar` 解出的 1.25 GUI XML、guiProfiles 和 l10n。1.25 未改动的脚本引用 `work/reference/decompiled/dataS/scripts/`（1.24 反编译）。MF = 1.25 decompiled `gui/InGameMenuMapFrame.lua`。

| 接口 | 位置 | 用途 |
| --- | --- | --- |
| 选择器状态与模式常量 | MF:3-12 | 页面状态号、总览/创建模式 |
| `setupMapOverview` | MF:949-960 | 追加页面文字（每任务一次） |
| `onClickMapOverviewSelector` | MF:1518-1602 | 原生容器显隐、清空选择、页面显隐 |
| `onFrameOpen/onFrameClose` | MF:276-327/328-358 | `generateJobTypes`、按当前状态调用选择器回调；关闭时交还表单 |
| `onLoadMapFinished` | MF:460 | 注入时机 |
| `registerInput`、`onMenuMapAction1`、`CLEAR_INPUT_ACTIONS` | MF:2357-2368、2380-2386、2589-2594 | 地图页按键 |
| `getCanStartJob/getCanGoBack` | MF:796/802 | 页面保持总览模式的后果 |
| `refreshContextInput` | MF:832-898 | 规划后刷新上下文框 |
| `setAIVehicle`、`setMapSelectionItem` | MF:936-942、1019-1282 | 选中车辆、模式复位、标记 |
| `startJob`、`setActiveJobTypeSelection` | MF:1374-1395、1403-1451 | 验证顺序、表单构建 |
| `onClickHotspot`、`onClickMap`、`onClickBack` | MF:1603-1628、1796-1821 | 总览模式下选中车辆、Esc 行为 |
| `validateParameters/updateWarnings/onJobTypeChanged/updateParameterValueTexts` | MF:1992/2003/2025/2048 | 表单验证与文字 |
| `update`（在岗帮手每 1 s 刷新） | MF:592-606 | 进度刷新方式 |
| `getIsPicking/executePickingCallback/startPickPositionAndRotation` | MF:2395/2398/2432 | 选点 |
| `setJobMenuVisible/createJob` | MF:2479-2508/2509-2543 | 不调用的原因、清空表单的做法 |
| 地图页 XML：`filterBox`、`mapOverviewSelector`、`subCategoryDotBox`、`createJobContainer`、`jobMenuLayout`、`buttonStartJobContainer`、`fs25_mapButton*`、`fs25_mapContextButtonListItemBg`、`fs25_aiContainerEmptyText` | `dataS-archive/gui/InGameMenuMapFrame.xml` | 页面位置、复用元素与样式 |
| `fs25_subCategory*`、`fs25_listSlider*`、`fs25_textDefault`、`baseReference/emptyPanel`、trait、preset | `dataS-archive/guiProfiles.xml` | 页面 profile |
| 切片 `gui.animalDealer_box`（358×100）、`gui.map_box_colorOverlay`、`gui.ingameMap_*`、`gui.icon_others_farmland`、`gui.icon_vehicleDealer_machines`、`gui.3dShop_arrow` | `dataS-archive/menu/gui.xml` | 卡片与图标 |
| PF 加页面 | 1.24 decompiled `internalMods/FS25_precisionFarming/scripts/gui/InGameMenuMapFrameExtension.lua:177-300`、`PrecisionFarmingGUI.lua:4-17` | 先例：文字、圆点、选择器回调、加载 GUI |
| `Gui:loadGuiRec/loadProfileSet`、`FrameElement:exposeControlsAsFields` | SDK `gui/base/Gui.lua:347`、`gui/elements/FrameElement.lua:100` | 加载页面、id 不写入目标 |
| `GuiElement` `loadProfile/applyProfile/delete/clone/updateAbsolutePosition/setPosition/getIsVisible/getDescendants/getDescendantById/onGuiSetupFinished/addCallback` | SDK `gui/elements/GuiElement.lua:315/393/453/473/1047/1121/1192/1412/1458/568/1611` | 原生表单放置与恢复、页面元素 |
| `SmoothListElement` 数据源/委托、`reloadData`、`getElementAtSectionIndex`、`getItemCount` | SDK `gui/elements/SmoothListElement.lua:183-195/573/1455`；MF:596 | 地点和队列列表 |
| `ListItemElement` 属性 | 1.24 decompiled `gui/elements/ListItemElement.lua:152-169` | `cell:getAttribute` |
| `SliderElement` 数据元素 | SDK `gui/elements/SliderElement.lua:267` | 滚动条 |
| `BoxLayoutElement` 跳过不可见元素 | SDK `gui/elements/BoxLayoutElement.lua:305` | 隐藏车辆组 |
| `MultiTextOptionElement:setTexts/setState` | SDK `gui/elements/MultiTextOptionElement.lua:391/342` | 选择器、作业类型 |
| `BitmapElement:setImageSlice/setImageFilename/setImageUVs` | SDK `gui/elements/BitmapElement.lua:228`；用法 MF:2210/2223-2224 | 图标、车辆图 |
| `FocusManager:setFocus` | SDK `gui/base/FocusManager.lua:769-777` | 页面目标的 `name` |
| `ButtonElement:loadInputGlyph`、`isTriggerableByGlobalAction` | 1.24 decompiled `gui/elements/ButtonElement.lua:199-219`；SDK `:62/138` | 键位图标、全局触发 |
| `ScreenElement.callButtonsWithAction` | 1.24 decompiled `gui/elements/ScreenElement.lua:74-85` | 与 PF 帮助按钮共用 X |
| `InGameMenu:openMapOverview/openFarmlandsScreen`、`pageMapOverview` | 1.25 decompiled `gui/InGameMenu.lua:570-577/589-592/53` | 热键打开页面 |
| `PlayerInputComponent:registerGlobalPlayerActionEvents/onInputToggleMap` | 1.25 decompiled `player/PlayerInputComponent.lua:130-200/408-423` | 全局动作注册位置与条件 |
| `Enterable:onRegisterActionEvents` | SDK `vehicles/specializations/Enterable.lua:1711` | 车内注册 |
| `InputBinding:registerActionEvent/beginActionEventsModification/getContextName/setActionEventTextVisibility/setActionEventTextPriority/removeActionEventsByTarget` | 1.25 decompiled `input/InputBinding.lua:603/724/2744/927/938/882` | 事件注册 |
| Mod action 与默认键、`input_` 文本 | 1.25 decompiled `input/InputBinding.lua:487-503/1355-1381`；1.24 decompiled `input/InputAction.lua:36-58` | modDesc `<actions>/<inputBinding>` |
| `MENU_EXTRA_1/MENU_MAP_ACTION_1/TOGGLE_MAP` 定义与默认键 | `dataS-archive/inputActions.xml`；安装目录 `profileTemplate/inputBindingDefault_KeyboardMouse.xml:428-430/452-454`、`inputBindingDefault_Gamepad.xml:380-382/404-406` | 页面按键 |
| `AIJobTypeManager` 类型名、`createJob/getJobTypeIndex/getJobTypeByIndex/getJobTypeIndexByName` | SDK `ai/AIJobTypeManager.lua:35-39/81/92/110/116` | GOTO…LOAD_AND_DELIVER |
| `AIJob:delete` | SDK `ai/jobs/AIJob.lua:41-48` | 不调用的原因 |
| `AIJob:saveToXMLFile/loadFromXMLFile/readStream/writeStream/getTaskByIndex/getDescription/getHelperName/getNamedParameter(s)/getGroupedParameters/applyCurrentState/onParameterValueChanged/getIsStartable` | SDK `ai/jobs/AIJob.lua:52/69/83/101/314/327/334/389-412/418/436/441` | 复制、序列化、进度、表单 |
| `AIJobGoTo/AIJobFieldWork/AIJobDeliver/AIJobLoadAndDeliver/AIJobConveyor` 参数与组 | SDK `ai/jobs/*.lua` 构造函数 | 表单行数、车辆组 |
| `AIJobLoadAndDeliver/AIJobDeliver:applyCurrentState` | SDK `ai/jobs/AIJobLoadAndDeliver.lua:217-260`、`AIJobDeliver.lua:172-214` | 有效站点 |
| `AIParameterLoadingStation/UnloadingStation` `setLoadingStation/setUnloadingStation/getString/loadingStationIds/unloadingStationIds` | SDK `ai/parameters/AIParameterLoadingStation.lua`、`AIParameterUnloadingStation.lua` | 预填站点 |
| `AIParameterPosition(Angle)`、`AIParameterFillType:setValidFillTypes`、`AIParameterVehicle:validate` | SDK `ai/parameters/AIParameterPosition.lua:64-80`、`AIParameterPositionAngle.lua:68-120`、`AIParameterFillType.lua:64-96`、`AIParameterVehicle.lua:86-97` | 预填位置、编辑、规划时验证 |
| `AITaskDriveTo` 目标 | SDK `ai/tasks/AITaskDriveTo.lua:25/65`；`AITaskStartEvent:run` `ai/events/AITaskStartEvent.lua:56-62` | 距离 |
| `AISystem:startJob/startJobInternal/stopJob/stopJobInternal`、`AI_JOB_STARTED` | SDK `ai/AISystem.lua:547/561-566/570/583` | 启动、跟随、完成消息 |
| `AISystem:save`、`AIJobVehicle` lastJob 读写 | SDK `ai/AISystem.lua:421-444`、`AIJobVehicle.lua:113-151`；1.24 decompiled `AIJobVehicle.lua:434-442` | 作业本身不存档 |
| `AIFieldWorker:saveToXMLFile/onLoad/onUpdate`（`isActive`、`pendingAIFieldWorkerStart`） | SDK `vehicles/specializations/AIFieldWorker.lua:202-206`；1.24 decompiled `AIFieldWorker.lua:135-143/181-191`（1.25 无函数体） | 读档后田地工作帮手可能被重启 |
| `AIParameterPosition(Angle).new/loadFromXMLFile`、`AIJobGoTo/AIJobFieldWork:setValues`、`MathUtil.getDirectionFromYRotation` | SDK `ai/parameters/AIParameterPosition.lua:16-25/38-41`、`AIParameterPositionAngle.lua:16-26/38-42`、`ai/jobs/AIJobGoTo.lua:147-157`、`AIJobFieldWork.lua:199-211`；decompiled `utils/MathUtil.lua:228-229` | 读档丢弃缺少目标的条目 |
| `AIJobFieldWork:getStartTaskIndex`、`AIJob:update`、`AITask.new`、`AITaskDriveTo:startDriving` | SDK `ai/jobs/AIJobFieldWork.lua:90-104`、`AIJob.lua:117-126/369-371`、`ai/tasks/AITask.lua:16-26`、`AITaskDriveTo.lua:88-104/135-151` | 队列自动开始的诊断日志 |
| `AIJobStopEvent` | SDK `ai/events/AIJobStopEvent.lua:35-46/62-69` | 已知局限：无权限检查 |
| `FieldGroundSystem:getSowableRange/getSowingRange/getDensityMapData`、`FieldGroundType.getValueByType`、`FieldDensityMap.FIELD_TYPE/STUBBLE_SHRED_LEVEL` | 1.24 decompiled `field/FieldGroundSystem.lua:3-12/195-198/485-490/500-507`、`field/FieldGroundType.lua:19-21` | 可播种/已播种地面、田地类型层 |
| `FSDensityMapUtil` 作业区域：`updateRollerArea`、`updateStonePickerArea`、`updateFertilizerArea`、`updateLimeArea`、`updateHerbicideArea`、`updateWeederArea`、`updateMulcherArea`、`getFieldTypeAtWorldPos` | 1.25 decompiled `utils/FSDensityMapUtil.lua:250-325/535-591/1336-1397/1398-1466/1467-1545/1546-1640/1761-1814/2888-2895` | 需求列表的作物和地面条件 |
| `FruitTypeDesc` `cutState/witheredState/wheelDestructionState/mulchedState/needsRolling/seedRequiredFieldType/isCultivationAllowed`、`getIsPlantableInPeriod` | SDK `fruits/FruitTypeDesc.lua:187-196/312-320/388/430/533/538-544`；1.25 decompiled `fruits/FruitTypeDesc.lua:707-709` | 作物条件、播种季节 |
| `SowingMachine` `seeds/currentSeed`、`getCanPlantOutsideSeason`、季节与田地类型检查 | SDK `vehicles/specializations/SowingMachine.lua:228/331/405-407/541-555/725-727/851-866/1017-1036` | 所选种子 |
| `FieldState.stubbleShredLevel`、`Platform.gameplay.useStubbleShred`、`GrowthMode`、`missionInfo.growthMode`、`environment.currentPeriod` | SDK `field/FieldState.lua:49`；1.24 decompiled `field/FieldState.lua:118`；1.25 decompiled `platform/Platform.lua:181`；1.24 decompiled `growth/GrowthMode.lua:1-4`、`FSCareerMissionInfo.lua:50`；1.25 decompiled `environment/Environment.lua:149` | 粉碎、播种季节 |
| `Vehicle:getLastSpeed`、`Foldable` `foldMoveDirection`/`getIsAIReadyToDrive`、`AttacherJoints` `isMoving`、`AITaskDriveTo:update` | SDK `vehicles/Vehicle.lua:2587-2595`、`Foldable.lua:594-608/816-830/2174-2190`、`AttacherJoints.lua:1056-1075/3276-3284/4151-4163`、`ai/tasks/AITaskDriveTo.lua:88-103` | 推进前等待组合停稳 |
| `AIJobVehicle:aiJobStarted/getJob/getLastJob/getCanStartAIVehicle` | 1.24 decompiled `vehicles/specializations/AIJobVehicle.lua:182-213/273/276`；SDK `:488-520` | 客户端当前作业、规划 |
| `MissionManager:getMissionsByFarmId`、`AbstractMission:getIsInProgress/getTitle/completion`、`AbstractFieldMission:getField/getWorldPosition` | SDK `missions/MissionManager.lua:525`、`AbstractMission.lua:790/868/300-311`、`missions/field/AbstractFieldMission.lua:86/98` | 合同 |
| `FieldManager:getFields/getFieldById`、`Field:getId/getAreaHa/getCenterOfFieldWorldPosition`、`FarmlandManager:getFarmlandOwner/getFarmlandAtWorldPosition` | 1.25 decompiled `field/FieldManager.lua:391/394`；1.24 decompiled `field/Field.lua:97/117/138`；SDK `economy/FarmlandManager.lua:407/432` | 田地、目标名称 |
| `I18N:formatArea/formatDistance` | 1.24 decompiled `I18N.lua:292/315` | 面积、距离 |
| `XMLFile.create/loadIfExists/iterate` | 1.24 decompiled `xml/XMLFile.lua:19/12/187` | 存档、编辑复制 |
| `FSBaseMission:delete/onStartMission/sendInitialClientState/getHasPlayerPermission`、`BaseMission:addUpdateable/removeUpdateable` | 1.25 decompiled `FSBaseMission.lua:167/367/774/2072`、`BaseMission.lua:548/562` | 生命周期 |
| `FSCareerMissionInfo:saveToXMLFile` | 1.24 decompiled `FSCareerMissionInfo.lua:246` | 存档时机 |
| `Utils.appendedFunction/prependedFunction` | 1.24 decompiled `utils/Utils.lua:380/387` | 钩子不保留返回值，只用于无返回值的函数 |

## 构建与测试

从仓库根目录执行：

```powershell
uv run map-helper-mod/tests/run.py
python map-helper-mod/tools/build.py
uv run map-helper-mod/tools/make_icon.py --texconv <texconv.exe路径>
```

`run.py` 用固定版本 Lupa 执行：l10n 检查（脚本和 GUI 用到的 Mod 文本键与 modDesc 一一对应、27 种语言齐全、格式参数一致、描述 27 种语言）、GUI 引用核对（`work/reference/1.25.0.0/dataS-archive` 存在时：GUI XML 引用的 profile、父 profile、trait、切片、preset、游戏文本和脚本用到的游戏文本都存在）、62 项行为测试、缺少游戏函数时的降级检查（页面、队列、热键分别关闭）和 10 组多人模拟。替身中的 GUI 树由 `tests/guixml.py` 从真实 XML 构建，回调按加载时绑定，选择器回调绑定原函数，列表按数据源填充。

行为测试覆盖（2026-10-24 新增：过滤选项随车辆类型、每车记忆、各类农具的需求判断与设置开关、四个列表的内容与空状态、每 10 s 重读状态、空闲车辆首个作业自动开始、暂停后加入继续、继续队列、当前作业行取消、卡片回到自己的车辆）：服务器权限、上限与验证；插入为下一个、移动、编辑、删除、清空；开始、成功推进、停止/错误/删除暂停、启动失败；自己座位；忽略非队列作业；车辆删除与易主；全部请求动作和状态事件的序列化；存档往返；加入同步；田地作业设置；**带排队、运行中、删除和编辑过的条目退出存档**；页面注册（第 8 个状态和圆点）、原生容器隐藏、原生表单放入页面并在其他状态恢复、原生“创建作业”仍在状态 6 正常打开；步行/无 AI/无权限的说明；表单隐藏车辆组并保留原生类型切换；地图选择切换车辆、其他农场车辆不切换、“我的车辆”；地点列表（合同只含本农场进行中、本农场田地按编号、作业类型、装载/卸载站点）；由地点预填（田地 → 田地工作或前往、装载站、卸载站保留类型、作业类型）；Z 加入、X 插入为下一个、无效作业提示、队列已满；列表上移/下移/编辑（保存替换、取消、条目开始时结束编辑）/删除/清空；当前作业的描述、距离和合同进度、每秒原地刷新、完成后消失并推进；规划模式；规划出错下一帧恢复；客户端只发请求；X 让给 PF 帮助；底部按钮栏项（位于“上一页”之后、余额下方不再加按钮、按 X 只经本 Mod 的事件触发一次而不被菜单的全局按键触发、在页面上隐藏、PF 帮助在本 Mod 钩子之后显示时下一帧隐藏、鼠标点击打开页面）；全局热键在 PLAYER 和 VEHICLE 各注册一次、打开页面、锁定时不打开；钩子与页面幂等；退出存档后原生地图页完全恢复（文字、圆点、选择器回调、容器 profile 与可见性、开始按钮、按键）、未启用 Mod 的存档中遗留回调无效、再次启用时重新创建；关闭菜单交还表单、重新打开恢复页面、选点在切换页面时取消；读档丢弃缺少位置或方向的条目且任务照常开始；页面开着时挂上/卸下农具，地点在下次刷新时改为田地工作/前往；队列自动开始的作业写诊断日志，玩家触发的开始不写；需求列表只列现在能做的作业（生长中的作物不施石灰、只在可播种地面捡石、收获后和枯萎的作物粉碎、残茬粉碎等级、种子季节和水稻田、镇压的地面和不需镇压的作物、除草剂的作物阶段），“我的田地”仍按信息框显示需要石灰/镇压。

多人模拟（新增：首个作业在服务器自动开始且各端显示运行中、暂停后加入作业由服务器继续）：服务器和多个客户端各用独立 Lua 环境，经有序队列交换真实 Mod 事件。新增一组：插入为下一个、上移、编辑（条目 id 不变）由服务器应用并广播到所有端；无权限成员和其他农场的移动/编辑被拒；首项上移不变；编辑已不存在的条目被拒。替身不模拟原生 AI 事件、对象创建、ghost 和断线，不能代替双机实测。

## 游戏内回归清单

维护者 2026-10-25 确认 1.0.0.0 已实机测试，但没有逐项结果，以下各项均未单独记录为通过。单人、主机 + 客户端、专用服务器各测一遍；每项记录构建提交和 SHA256，并检查 `log.txt` 中没有 `[Map Helper]` 警告和 Lua 错误。

- MAP-01：载入存档，打开地图页：左侧边栏选择器多一页“地图助手”，圆点从 7 个变为 8 个（有 Precision Farming 时为 9 个），翻页时圆点正确高亮；底部按钮栏中“上一页”之后有“地图助手”（X），只有一个，余额下方没有按钮。退出到主菜单再载入另一个存档，仍只有一页、一个圆点、一个按钮栏项。
- MAP-02：**退出存档**：有排队作业（等待中、正在执行、刚删除或编辑过）时从游戏菜单退出存档，能正常回到主菜单，日志没有 `AIJob.lua:43` 或其他错误；载入另一存档再退出同样正常。
- MAP-03：页面视觉：卡片、两行按钮、地点列表、作业表单、加入按钮、队列标题与清空按钮、队列列表、条目按钮从上到下不重叠，左右对齐边栏列表；1080p、1440p、超宽屏和不同 UI 缩放下不溢出底部按钮栏；列表滚动条位于列表右侧；中文、德文等长文本不出框（滚动显示）。
- MAP-04：按钮上显示 Z 和 X；页面上按 Z 加入、按 X 插入为下一个，不会同时开始原生作业；地图其他页面按 X 切到地图助手页，Precision Farming 土壤图层下按 X 打开 PF 帮助。
- MAP-05：全局热键：步行、驾驶、作为乘客时按左 Alt + M 都打开地图并显示地图助手页面；F1 按键帮助中列出“打开地图助手”；控制设置中能看到并修改此键；骑马时不生效（已知）。按 Alt + M 时车辆的 M 功能不动作。菜单已打开时无反应。
- MAP-06：车辆：驾驶时打开页面，卡片显示该车名称和商店图；在地图上点击自己农场的另一台车，页面切换到它，右侧上下文框显示该车；点击别人农场的车只选中不切换；信息行出现“点击返回你的车辆”，点击卡片回到自己的车并移动地图；步行时卡片显示步行说明，表单区显示提示文字。
- MAP-07：原生表单：作业类型列表、参数行与在地图上点车辆再点“创建作业”相同（只是不显示车辆一行）；改作业类型、选站点和填充类型、在地图上选位置和方向都正常；验证失败时出现原生红色提示和对话框。页面上没有“开始作业”按钮。
- MAP-08：离开页面（切到其他图层、在岗帮手、创建作业页、关闭菜单）后原生“创建作业”页和右侧“创建作业”按钮打开的原生作业菜单位置、大小与原版完全相同，“开始作业”按钮在；再回到页面表单重新出现在页面中。
- MAP-09：地点：过滤选择器外观与作业类型选择器一致、左右箭头和点击都能切换；“合同”只含本农场进行中的田地合同，能做的排在前面并写明作业；“我的田地”只含自己的田地并显示状态；“站点”只在车辆能运送时出现。点击田地/合同：地图移到该处，表单为田地工作（或前往）且目标在田内；点击装载站/卸载站：表单为装载和运送（或运送）并选中该站点。田地行图标是幼苗而不是人像。
- MAP-10：加入队列：车辆空闲时第一个作业立即开始并成为第一行；之后的新项排在最后，插入为下一个排在第一；加入后表单恢复为该类型的新作业；已满 10 项时提示。
- MAP-11：队列列表：上移/下移顺序正确，箭头方向与动作一致；编辑把条目载入表单，按钮变为“保存/取消”，保存后条目原位替换，取消不改变；编辑中该条目开始执行时退出编辑；删除、清空正常。
- MAP-12：执行与进度：作业开始后第一行显示帮手当前任务，驾驶阶段显示到目标的距离且每秒更新，在合同田地上显示合同进度；作业完成后该行消失，约 1.5 秒后下一项开始并成为第一行；全部完成后出现完成提示。
- MAP-13：帮手工作期间（含玩家直接开始的作业）：表单仍可用、作业类型与空闲时相同，加入的作业在当前作业后执行；右侧上下文框显示“取消作业”而非“创建作业”；帮手行为不受影响。
- MAP-14：取消与失败：选中第一行用“取消作业”、车内 H 键、地图原生“取消作业”停止，队列暂停，卡片显示原因并提示，“继续队列”出现；缺油、缺种子、被挡、帮手过多等原因同样暂停并显示原生原因；“继续队列”或加入新作业都从第一个等待作业继续。
- MAP-15：田地工作排队后再改车辆的帮手设置，开始后按新设置执行；客户端排队、主机执行时同样如此；存档读回后同样。
- MAP-16：手柄：Z 和 X 对应的手柄默认键（`MENU_MAP_ACTION_1` 的 `BUTTON_1`、`MENU_EXTRA_1` 的 `BUTTON_11`）显示在按钮上且有效；地点和队列列表可用手柄选择并确认；过滤选择器、条目按钮（上/下/编辑/删除）、清空、继续队列没有按键，手柄能否聚焦需确认（地图按钮原生 `handleFocus=false`）。确认这两个菜单键不能在控制设置中修改。
- MAP-17：存档、退出、重新载入：队列保留且不自动开始，“继续队列”显示；卖掉其中一辆车后保存再载入，该车队列被丢弃并在日志写 info。
- MAP-18：联机：客户端经理添加（空闲车辆立即开始）、插入、移动、编辑、删除、继续、取消，其他客户端页面同步；无权限成员和其他农场不能修改（按钮无效、服务器拒绝）；之后加入的玩家看到队列；规划者离开后队列继续；客户端上当前作业行和距离正常显示。
- MAP-19：车辆卖出、转给其他农场或被重置/删除时，页面切回自己的车辆或步行说明，无报错；队列按原规则删除或暂停。
- MAP-20：与 Precision Farming 同时使用：PF 页面（筛选、实验室窗口）显示正常，地图助手页面与 PF 页面互相切换时元素不残留；PF 土壤图层的“帮助”与 X 的让位正常。
- MAP-21：载入启用本 Mod 的存档，回主菜单，载入未启用本 Mod 的存档：地图页没有地图助手页面、圆点、按钮，“创建作业”页和作业菜单为原版布局，X 和 Alt + M 无本 Mod 行为；再载入启用的存档，一切只有一份且可用。
- MAP-22：底部按钮栏项：位于“上一页”左侧，分隔线、文字和 X 图标与原生按钮一致；在页面上、原生作业菜单中和 Precision Farming 土壤图层（显示“帮助”时）隐藏，回到其他页面时重新出现，按钮栏随之重新排列；按一次 X 只切换一次（页面上只插入一次）；鼠标点击切换到页面；手柄显示 `BUTTON_11` 图标；切换分辨率/UI 缩放后重新进入地图页位置仍正确。
- MAP-23：页面选点：在页面上选位置时光标标记跟随鼠标（仅在边栏右侧，原生规则），确认/取消后表单和地图标记正确；在地图空白处点击后表单的目标标记仍显示。
- MAP-24：暂停游戏时加入、继续队列、取消作业不可用；取消暂停后一秒内恢复可用；导览进行中热键不打开。
- MAP-25：快速连续切换页面和车辆、在页面上关闭再打开菜单，不出现重复元素或残留的“开始作业”隐藏状态。
- MAP-26：预览实验室无法显示的部分（运行时文字、禁用状态、选中色、车辆图、表单参数行、按键图标）在游戏中逐项检查。
- MAP-27：上/下按钮的箭头朝向（`gui.3dShop_arrow` 旋转 270°/90°）与动作一致，否则交换两个 profile 的旋转。
- MAP-28：需要此作业的田地：分别挂犁、耕作机、播种机（含施肥播种机）、装石灰/化肥/除草剂的喷洒机、镇压器、除草机、粉碎机、割草机、联合收割机割台（谷物/玉米）、去茎叶机、捡石机，打开页面，默认选中“需要此作业的田地”，列出的田地与地图田地信息框（鼠标停在田地中部）的状态一致；作业完成一部分的田地按田地位置点判断（已知局限）；关闭石灰、杂草、石头或犁地要求的存档中对应需求不出现。卡车、没有农具的拖拉机默认“我的田地”。工作 10 秒后列表随状态更新。
- MAP-29：每台车辆记住自己的过滤选择（切换车辆再切回）；空列表显示对应说明文字；大量田地（50 块以上）时打开页面和切换过滤无明显卡顿。
- MAP-30：联机：另一名玩家坐在车里时，为该车加入作业或点“继续队列”不会开车，作业留在队首，卡片显示游戏的“车辆正在使用”原因；他下车后“继续队列”开始。自己坐在车里时加入作业照常开始（单人和客户端都测）。
- MAP-31：割台：谷物割台不把青贮阶段的玉米列为需要收割，青贮割台列出；“我的田地”中青贮阶段显示“生长中”。直播机在收获后的田地上列出播种需求，普通播种机不列；带耕作机的播种组合也列出。除草机只列小杂草、锄也列中等杂草；纯草地镇压器不列需求；去茎叶机只列自己的作物；没有作业区域的药箱车不算喷洒机；刚施过同种肥料/石灰的田地不再列出。前置药箱装除草剂、后置喷杆空箱时列为除草剂；装有 Fill Type Selector 且药箱为空时按其选择。页面打开时挂上或卸下农具，10 秒内选项更新、当前选择保持（若仍可用）。
- MAP-32：诊断日志（Hardi MEGA 1200L 或其他折叠喷杆）：排两个以上不同田地的田地工作，让队列自己开始后面的作业。`log.txt` 中每次自动开始有一行 `[Map Helper] Queue starts ...`（距离、`start task`、各折叠部件状态），驾驶开始时有一行 `... starts driving; ...`；加入第一个作业或“继续队列”开始的作业没有这两行。把相关行连同现象（喷杆是否收完才走）交给开发者，判断方法见“推进前等待组合停稳”。
- MAP-33：读档：手动删掉 `mapHelper.xml` 中某个作业的 `angle` 或 `x` 属性后载入，存档正常进入，该作业不在队列中，`log.txt` 有一行 “Dropped ... whose target is missing”。页面开着时让另一名玩家（或自己下车）挂上耕作机，10 秒内田地点击改为田地工作；卸下后改回前往。
- MAP-34：需要此作业的田地只列现在能做的：装石灰的撒布机不列生长中或可收获的作物田（“我的田地”仍显示需要石灰），收获后的田列出；捡石机只列整过的地；粉碎机列收获后和枯萎的作物，粉碎一次后不再列出；播种机选了不在季节内的种子时不列播种（换成当季种子 10 秒内列出），水稻只列稻田；土壤镇压器不列已长过第一阶段的作物和收获后地面，马铃薯田不列；除草剂喷洒机列收获后的谷物和茎叶阶段的马铃薯。帮手在列出的田地上开始作业时不应以“田地未准备好”或“错误季节”停止。
