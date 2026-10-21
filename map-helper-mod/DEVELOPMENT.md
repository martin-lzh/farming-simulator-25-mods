# 开发与验收

## 当前状态

面向 PC 版 FS25 1.25.0.0（安装目录 `VERSION` 为 1.25.0.0），modDesc descVersion 114，与动物产品管理一致。`modDesc.xml` 的 `0.1.0.0` 只是占位，首个版本号由维护者决定；改动记录在 CHANGELOG 的 Unreleased。

- 2026-10-21：首次实现。28 项行为测试、7 组多人模拟、l10n 检查和构建均通过，5 个脚本用本机 `fs-luau-compile` 编译通过（输出在被忽略的 `work/validation/map-helper-luau/`，只说明可解析）。构建基于 dev `a6e6fbc` 加未提交的本目录文件，10 个文件，SHA256 `247faf0fd65977fb86ed6390a5ee57e4b11f270e184fd383285e2c440fa738b6`（含 Codex 审查的两处修正）。**尚未在游戏内运行过**：没有安装构建，没有启动游戏，下方 MAP-xx 清单全部待维护者执行。
- 2026-10-21 之后的改动（未提交）：按键从自定义的 `MH_TOGGLE_DRAWER`/`MH_ADD_TO_QUEUE`（左 Alt + H/J）改为原生 `MENU_EXTRA_1`，删除 modDesc 的 `<actions>`、`<inputBinding>` 和 `input_*` 文本；按钮移到余额和帮手状态行下方右对齐，抽屉从右侧滑入、高度随内容；帮手工作期间也能规划队列（下文“规划模式”）。本机 `uv run map-helper-mod/tests/run.py`：32 项行为测试、l10n（20 个键）、降级检查和 7 组多人模拟通过。这一版的构建 SHA256 尚未记录，同样**尚未在游戏内运行过**。
- 仓库级接入（`tools/ci.py` 的 `MODS`、根 README 的 Mod 列表）不在本次范围内，由集成方处理；在此之前 `tools/ci.py validate/build` 不会处理本 Mod。

## 结构

- `scripts/MapHelper.lua`：队列模型与服务端逻辑（请求处理、启动下一个作业、完成/取消判断、暂停原因、存档读写、加入同步、任务生命周期）。
- `scripts/QueueEvents.lua`：`MHQueueRequestEvent`（客户端 → 服务器：添加、删除、清空、开始）和 `MHQueueStateEvent`（服务器 → 客户端：某车辆的完整队列）。
- `scripts/MapFrameExtension.lua`：地图页面接入：余额和帮手状态行下方的“地图助手”按钮（`MF.placeToggle`）、作业菜单里“开始作业”上方的“加入队列”按钮、两者共用的 `MENU_EXTRA_1` 按键事件、规划模式（`MF.withPlanning`），以及抽屉各按钮调用的原生流程。
- `scripts/DrawerDialog.lua`、`gui/DrawerDialog.xml`：抽屉本体。原生 MessageDialog（无全屏遮罩），BoxLayout 放操作按钮，ScrollingLayout + 克隆行显示队列，与动物产品管理的弹窗做法相同；`MHDrawerDialog:layout/place` 负责高度和右侧滑入。
- `gui/DrawerToggle.xml`、`gui/QueueButton.xml`：插入地图页面的两个小按钮，沿用地图页面自己的 `fs25_mapButton*` 样式。
- `scripts/Register.lua`：检查所需游戏函数是否存在，按功能安装钩子；钩子按类只装一次，重复执行只刷新回调（与模板相同）。
- `tests/`：原创引擎替身、31 项行为测试、7 组多人模拟；不加载、不执行任何游戏文件。
- `tools/build.py`：白名单打包 10 个运行时文件（modDesc、5 个脚本、3 个 GUI XML、DDS 图标），检查 DDS 格式。
- `tools/make_icon.py`：代码绘制原创图标（折叠地图、地图钉、虚线路线和小拖拉机），PNG 源在 `assets/icon.png`，texconv 生成 512×512 BC1、单级无 mipmap 的 `icon_mapHelper.dds`。

## 设计

### 抽屉

“地图助手”按钮加在地图页面头部（`shopMoneyBox` 的父元素，即余额所在的 `fs25_menuHeaderPanel`）。加载方式与游戏自带 Precision Farming 给地图页加窗口相同：在 `InGameMenuMapFrame:onLoadMapFinished` 之后对该 frame 调用 `g_gui:loadProfileSet` 和 `g_gui:loadGuiRec`，目标对象是本 Mod 的扩展表。frame 每个存档重新创建，所以每个 frame 只注入一次（`frame.mapHelper` 判重），GUI profile 全局只加载一次。

按钮位置：`gui/DrawerToggle.xml` 里的 position 只是起点。`MF.placeToggle` 在注入时和每次 `registerInput`（每次进入地图页，分辨率或 UI 缩放可能已变）按绝对坐标重新放置：右边缘对齐余额底框 `shopMoneyBoxBg` 的右边缘，上边缘取 `shopMoneyBoxBg` 与帮手状态行 `statusMessage`（`fs25_ingameMenuAIStatusText`，anchorBottomRight，位于头部下方）两者 `absPosition[2]` 中较低者再下移 `MF.TOGGLE_GAP` = 10 px，这样不遮挡余额和状态行。`GuiElement:setPosition` 会让 absPosition 平移同样的量，所以按差值加到 `position` 上即可。两个元素见 1.25 `dataS-archive/gui/InGameMenuMapFrame.xml`；余额底框宽度随余额位数变化（1.25 decompiled `gui/InGameMenuMapFrame.lua:1464`）。

抽屉是一个不带全屏遮罩的 MessageDialog，地图仍可见。`MHDrawerDialog:layout(state)` 按 `MHDrawerDialog.LAYOUT`（像素）自上而下排标题、状态文字（按 `getTextHeight` 计高）、可见的操作按钮，车内时再排队列标题和队列行（最多 6 行可见，空队列时为提示文字高度），最后加底部按钮区，并把 `drawerPanel` 的高度设为总和：步行时只有标题、状态和“定位到我”，车内时才有队列部分。`MHDrawerDialog:place` 让抽屉右边缘对齐按钮右边缘、顶部在按钮下方 `toggleGap` = 8 px；打开后的 `SLIDE_TIME` = 160 ms 内，每帧把抽屉向右偏移剩余距离（三次缓出），形成从右侧滑入的效果。每次 `refresh` 重新布局，所以内容变化时高度随之变化。打开期间每 250 ms 重新计算状态，只有内容变化时才重建队列行并恢复焦点；队列事件到达时也会立即刷新。需要地图的操作（定位、创建作业、设置目的地、在作业菜单里开始作业）先关闭抽屉再执行。抽屉内的按钮均可获得焦点并互相链接，手柄可上下选择。

抽屉作用于 `g_localPlayer:getCurrentVehicle()`。步行时只显示“定位到我”。各按钮直接调用原生流程：

| 抽屉按钮 | 调用 | 判断条件（与原生一致） |
| --- | --- | --- |
| 定位到我 | 有车：`setMapSelectionItem(hotspot)` + `ingameMap:panToHotspot`；步行：`g_localPlayer:getPosition` + `ingameMap:setCenterToWorldPosition`（同 `onFrameOpen`） | 只在总览模式、非选点时选中 hotspot |
| 创建作业 | 车辆空闲：`InGameMenuMapFrame:setAIVehicle(vehicle)`（选中、平移、`onCreateJob`）；帮手在岗或队列运行中：按钮文字改为“加入队列”，走规划模式（见下节） | hireAssistant 权限、可访问车辆、总览模式、非选点、未暂停、无导览、`jobTypeInstances` 中有可用作业（规划模式下在 `MF.withPlanning` 内判断） |
| 设置目的地 | `setMapSelectionItem` + `panToHotspot` + `onStartGoToJob`（原生选点后 `startGoToJob`） | 同上，且 GOTO 作业可用；规划模式下不提供（它会立即开始作业） |
| 取消作业 | `vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())`，与 `cancelJob` 相同 | 车辆有帮手、有权限 |
| 开始作业 | `onStartCancelJob`（作业菜单正在为该车辆打开时） | `getCanStartJob` |
| 开始队列 / 清空队列 / 删除 | 发送 `MHQueueRequestEvent` | 有权限且队列不为空 |

### 加入队列

“加入队列”按钮放在作业菜单（`createJobContainer`）里原生“开始作业”上方，与“地图助手”按钮共用 `MENU_EXTRA_1`。只在作业菜单为玩家当前驾驶的车辆打开、且有权限时显示（追加在 `setJobMenuVisible` 之后的 `MF.updateQueueButton` 判断）；作业菜单打开期间“地图助手”按钮隐藏，所以同一时刻只有一个按钮显示这个键。点击后按 `InGameMenuMapFrame:startJob` 的方式先 `setValues` 再 `validate(g_localPlayer.farmId)`，失败时用原生 InfoDialog 和 `updateWarnings` 提示；成功则把 `frame.currentJob` 作为请求发给服务器，然后按原生 `startJob` 成功分支（1.25 decompiled `gui/InGameMenuMapFrame.lua:1383-1387`）离开作业菜单：`mode = AI_MODE_OVERVIEW`、`currentJob = nil`、`setJobMenuVisible(false)`、`refreshContextInput()`，再打开抽屉显示队列。不用 `onClickBack`（同文件 `:1796-1812`）：它在 `AI_MODE_CREATE` 分支调用 `self.currentJob:resetTasks()`，而主机上请求事件按引用把这个作业对象交给了队列，会把已排队的作业清掉。`createJob`、`refreshContextInput` 已加入 `Register.lua` 的依赖检查。

### 规划模式（帮手工作期间加入队列）

原生作业菜单只能为没有帮手的车辆创建作业：`InGameMenuMapFrame:createJob`（1.25 decompiled `gui/InGameMenuMapFrame.lua:2509-2543`）对每个作业类型调用 `getIsAvailableForVehicle`，`AIJobFieldWork`（gameSource `ai/jobs/AIJobFieldWork.lua:167`，经 `getCanStartFieldWork`）和 `AIJobGoTo`（`ai/jobs/AIJobGoTo.lua:92`）都依赖 `AIJobVehicle:getCanStartAIVehicle`（gameSource `vehicles/specializations/AIJobVehicle.lua:488-520`），其中 `getIsAIActive()` 为真时返回 false；`refreshContextInput` 也只在车辆空闲时给出“创建作业”。

做法：车辆有帮手（`getIsAIActive`）或队列正在运行（含两项之间的 1.5 s 间隔）时，抽屉状态 `planning` 为真，“创建作业”显示 `mh_addToQueue`。`MF.createJob` 不走 `setAIVehicle`（它要求 `getCanCreateJob`），而是照它的步骤 `setMapSelectionItem(hotspot)` + `ingameMap:panToHotspot`，记下 `ext.planningVehicle`，在 `MF.withPlanning` 内调用 `frame:createJob()`，再隐藏 `createJobEmptyText`。`MF.withPlanning` 给车辆写一个实例字段 `vehicle.getIsAIActive = function() return false end`，遮住 specialization 注册在类型上的函数，执行回调后恢复 `rawget` 得到的原值（通常为 nil，即去掉遮蔽）。脚本不捕获错误（见“兼容与降级”）：回调出错时错误照常进入日志，遮蔽记在 `MF.planningShadow`，由下一帧 `MapHelper:update` 开头调用的 `MF.restorePlanning` 去掉；新的规划开始前也会先清理。只在构建作业类型列表期间生效，帮手本身和其他代码看到的状态不变。抽屉可用性判断（`MF.getHasAvailableJob`）也在同一包装内执行。

作业菜单以规划模式打开时，`MF.updateQueueButton` 在 `planningVehicle == currentJobVehicle` 时隐藏原生 `buttonStartJobContainer`（原生开始会被 `getIsStartable` 拒绝），只留“加入队列”；离开作业菜单时清掉 `planningVehicle` 并恢复“开始作业”。“设置目的地”在规划模式下不提供，因为原生 `startGoToJob` 立即开始作业；要排队前往某处，在作业菜单里选“前往”作业类型。

服务器端（`MH.serverAdd`）：加入一项后，如果队列不在运行而车辆 `getIsAIActive()` 为真，就用 `vehicle:getJob()`（`AIJobVehicle` 用 `registerFunction` 注册的 `getJob`，gameSource `AIJobVehicle.lua:75`）取当前作业，设 `queue.running = true`、`queue.runningJob = current`。之后的完成判断与队列自己启动的作业相同：成功结束则开始下一项，玩家停止或出错则暂停。所以不论当前作业来自队列还是玩家直接开始，队列都在它之后继续。

### 队列与完成判断

队列只存在服务器上，按车辆存放，每辆最多 10 项，每项有服务器分配的 id。“开始队列”时服务器对第一项 `setValues`、`validate(farmId)`，再用原生 `job:getIsStartable(connection)` 检查（AI 上限、车辆存在、hireAssistant 权限、车辆是否被占用）。connection 取车辆当前控制者的连接（`spec_enterable.isControlled` 时用 `getOwnerConnection()`），这样玩家自己坐在车里不会被 `Enterable:getIsInUse` 判为占用，与玩家自己在地图上点“开始作业”时相同。通过后才从队列移除并调用 `g_currentMission.aiSystem:startJob(job, farmId)`，记下这个作业对象。

完成判断订阅 `MessageType.AI_JOB_STOPPED`（`AISystem:stopJobInternal` 在服务器和客户端都会发布 `job, aiMessage`），只处理队列自己启动的那个作业对象：

- `AIMessageSuccessFinishedJob`（`AIJob:update` 在任务全部完成时发出）和 `AIMessageSuccessSiloEmpty`（`AIJobLoadAndDeliver` 的正常结束）算成功。还有下一项时设 1500 ms 延迟后再启动：原生作业在下一次 `AISystem:update` 才从 activeJobs 移除。延迟到时如果车辆又被别人开始了作业，队列暂停。最后一项完成后发“队列完成”提示。
- `AIMessageSuccessStoppedByUser`、所有错误消息（缺料、缺油、被挡、没钱等）以及 nil（车辆删除）都让队列暂停，剩余项保留并提示。原生的停止原因由游戏自己提示，本 Mod 只补“队列已暂停”。
- 启动失败分两种：`validate` 失败记为“下一个作业无法按计划开始”；`getIsStartable` 失败记下原生状态码和作业类型，客户端用该类型的 `getIsStartErrorText(state)` 显示原生原因（如帮手过多）。失败的项留在队首。

玩家手动启动的其他作业不影响队列，例外是在该作业执行期间往队列加项：服务器此时跟随这个作业（见“规划模式”）。车辆被删除时队列删除；车辆所有者变化时服务器清空队列并广播。

### 多人

请求经 `MHQueueRequestEvent` 发往服务器；主机上 `Connection:sendEvent` 走本地流直接 `run(localConnection)`，所以主机和客户端是同一条路径。服务器校验：车辆存在且支持 AI、请求者农场等于车辆所属农场、`getHasPlayerPermission("hireAssistant", connection, farmId)`（与原生 `getIsStartable` 相同的权限）、作业的 vehicle 参数就是该车辆、未超过上限、服务器端 `validate` 通过。客户端不做乐观更新。

每次变化后服务器广播 `MHQueueStateEvent`（`broadcastEvent(event, false, nil, vehicle)`，只发给已有该车辆的连接），内容是该车辆的完整队列；作业用原生 `AIJob:writeStream/readStream` 序列化，作业类型索引用 UInt16（与 `AIJobStartRequestEvent` 相同）。加入游戏时在 `FSBaseMission:sendInitialClientState` 之后发送全部队列，位置与 `AISystem:onClientJoined` 发送进行中作业相同。暂停/完成提示随状态事件发出，只有车辆所属农场的玩家显示（专用服务器没有本地玩家，不显示）。

田地作业的帮手设置（2026-10-21 按 Codex 审查修正）：`AIJobFieldWork:readStream`（SDK `ai/jobs/AIJobFieldWork.lua:53`）把发送方的设置读进 `pendingData`/`pendingVehicle`，首次 `update` 时用 `vehicle:applyReadAIModeSettingsFromStream` 应用到车辆（1.24 decompiled `AIJobFieldWork.lua:41-50`，1.25 字节码未变）；`writeStream`（SDK `:64`）却写车辆当时的设置（`AIModeSelection:writeAIModeSettingsToStream`，SDK `vehicles/specializations/AIModeSelection.lua:403`）；`AIJob:saveToXMLFile`（SDK `ai/jobs/AIJob.lua:52`）不保存设置。原实现因此会让服务器在开始时套用排队那一刻的旧设置，而广播和存档给的是别的设置。

选择的做法：排队作业一律使用**开始时车辆的设置**，与原生开始路径一致——`AISystem:startJob` 广播的 `AIJobStartEvent` 本来就写车辆当时的设置。服务器收到请求时、开始前和客户端读状态时都调用 `MH.useVehicleSettingsAtStart` 清掉 `pendingData`/`pendingVehicle`（`AIJobFieldWork:setValues`，SDK `:199`，已给任务设置车辆，不依赖该分支）。于是服务器执行、广播和存档读回三者一致，玩家排队后再改的设置也生效。没有选择保存一份快照，因为 `FieldCourseSettings` 只经核对过 stream 读写，没有核对过的 XML 存取接口，而且快照会在开始时覆盖车辆上玩家后来改过的设置。README 和 CHANGELOG 已向玩家说明。

### 存档

追加在 `FSCareerMissionInfo:saveToXMLFile` 之后（服务器、存档有效时），写入存档目录的 `mapHelper.xml`，即使没有队列也覆盖，避免旧队列复活。格式与 `AIJobVehicle:saveToXMLFile` 保存 lastJob 相同：每项写作业类型名（`jobType.name`）和原生 `AIJob:saveToXMLFile` 的参数，按车辆 `uniqueId` 分组并排序。

读取在 `FSBaseMission:onStartMission` 之后（服务器，车辆和建筑都已加载）。用 `vehicleSystem:getVehicleByUniqueId` 找车，`getJobTypeIndexByName` + `createJob` 建作业，`loadFromXMLFile` 读参数。`AIParameterVehicle` 没有 `loadFromXMLFile`，所以用队列所属车辆 `setVehicle` 后再 `setValues`。找不到车辆、车辆不支持 AI、作业类型不存在（例如来自已移除的 Mod）的项被丢弃，并在日志写一行 info。读档后队列不自动开始；保存时正在执行的作业不恢复，与原版一致。

### 退出存档时的清理（2026-10-21 按 Codex 审查修正）

核对结果：`g_inGameMenu` 只在启动时创建一次（1.25 decompiled `main.lua:550` → `gui/InGameMenu.lua:31-32`），每个任务在 `FSBaseMission.lua:66` 把它登记为地图加载完成对象，`:1235` 调用 `onLoadMapFinished`（`gui/InGameMenu.lua:184` → 地图页）。`FSBaseMission:delete` 只调用 `g_inGameMenu:reset()`（`FSBaseMission.lua:169`），`InGameMenuMapFrame:reset`（`gui/InGameMenuMapFrame.lua:511`）和 `GuiElement:reset`（SDK `gui/elements/GuiElement.lua:1080`）不删除子元素。所以地图页及本 Mod 加的按钮会跨存档保留。

现在 `FSBaseMission:delete` 之前（前置钩子，此时 Mod 仍已加载）执行 `MH.onMissionDeleted`：`MHMapFrame.removeAll` 删除两个按钮（`GuiElement:delete`，SDK `:453`，同时从父元素和 FocusManager 移除）、按目标移除按键事件、清掉 `frame.mapHelper`；`MHDrawerDialog.release` 关闭抽屉（`Gui:closeDialogByName`，SDK `gui/base/Gui.lua:579`），按 `InGameMenu.createFromExistingGui`（1.25 decompiled `gui/InGameMenu.lua:105-106`）的方式先删根元素再删控制器，并清除 `g_gui.guis`、`nameScreenTypes` 和 `Gui:addScreen`（SDK `:1062`）登记的条目。下一个启用本 Mod 的存档在 `onLoadMapFinished` 时重新创建。另外按钮和按键回调都先检查 `g_modIsLoaded`、任务是否进行中以及控件是否仍属于该 frame，遗留回调不会再起作用；frame 上若残留旧脚本副本留下的控件，会先删除再注入。

### 防护

`Register.lua` 在加载时检查全部依赖（见下表），缺失时只关闭对应功能（抽屉或队列），用 `Logging.warning` 记一次 `[Map Helper] ... disabled`，不安装相关钩子。地图页面头部找不到时只跳过按钮，菜单键仍可打开抽屉。脚本不用 pcall/xpcall（ModHub TestRunner 的 PublicLuaCheck 不允许，与 Animal Products Manager 相同）；需要“出错也要收尾”的地方改为下一帧收尾（`MF.restorePlanning`）。

### 按键

两个按钮都用原生菜单 action `MENU_EXTRA_1`（`MF.INPUT_ACTION`），不再自定义 action。事件只在地图页面自己的输入上下文内注册（追加在 `InGameMenuMapFrame:registerInput` 之后，先按目标移除再注册，避免重复），回调 `MF.onKeyAction`：“加入队列”按钮可见时加入队列，否则在总览模式下打开抽屉。两个按钮 profile 的 `inputAction` 也是 `MENU_EXTRA_1`，按钮上显示的就是这个键。

为什么不用自定义组合键：按钮上的键位提示由 `ButtonElement:loadInputGlyph`（1.24 decompiled `gui/elements/ButtonElement.lua:199-219`）调用 `InputDisplayManager:getKeyboardInputActionKey`（`input/InputDisplayManager.lua:689-747`，经 `getFirstBindingAxisAndDeviceForActionName`）生成，只取绑定的 `axisNames[1]`，所以左 Alt + H 在按钮上只显示成“ALT”。自定义 action 也没有手柄默认键。

为什么是 `MENU_EXTRA_1`：PC 地图页 `InGameMenuMapFrame:registerInput`（1.25 decompiled `gui/InGameMenuMapFrame.lua:2357-2368`）只注册 `MENU_MAP_ACTION_1` 和换车键，`CLEAR_INPUT_ACTIONS`（`:2589-2594`）是 `MENU_ACTIVATE`、`MENU_CANCEL`、`MENU_EXTRA_2`、`CAMERA_ZOOM_IN_OUT`；地图页、游戏菜单和 Precision Farming 都没有为 PC 地图页注册 `MENU_EXTRA_1` 的事件（游戏菜单 `TabbedMenu:onClickMenuExtra1` 只转给页面的 menuButtonInfo，地图页没有这一项）。默认绑定（安装目录 `profileTemplate/`，只读）：键鼠 `KEY_x`（`inputBindingDefault_KeyboardMouse.xml:428-430`），手柄 `BUTTON_11`（`inputBindingDefault_Gamepad.xml:380-382`），方向盘、摇杆等多数设备表也有默认键（Saitek 面板为空）。

注意两点：
- `MENU_EXTRA_1` 在 `dataS/inputActions.xml` 中是 `locked="true"`，而控制设置 `ControlsController`（1.24 decompiled `gui/ControlsController.lua:214`，1.25 字节码未变）用 `g_inputBinding:getActionBindingsCopy(true)` 取列表，`InputBinding.lua:2747-2750` 跳过 locked 动作。按这段代码，玩家**不能**在控制设置里改这个键，README 因此没有写可改键；需在游戏内确认（MAP-16）。
- Precision Farming 在地图页筛选栏克隆的“帮助”按钮也设了 `setInputAction("MENU_EXTRA_1")`（1.24 decompiled `internalMods/FS25_precisionFarming/scripts/gui/InGameMenuMapFrameExtension.lua:249-257`，土壤图层可见时显示，`:282`）。它没有注册事件，靠界面自身触发：`ScreenElement:inputEvent` 在动作未被焦点元素用掉时调用 `ScreenElement.callButtonsWithAction(self.elements, action)`（decompiled `dataS/scripts/gui/elements/ScreenElement.lua:74-85, :125`），触发树中第一个 `isTriggerableByGlobalAction`、可用且 `inputActionName` 相同的按钮。因此本 Mod 的两个按钮在 profile 中设 `isTriggerableByGlobalAction=false`（`ButtonElement.lua:138` 读取），只由本 Mod 的事件触发；`MF.onKeyAction` 先用 `MF.getHasOtherKeyButton` 查找 frame 中其他可见、可用且使用 `MENU_EXTRA_1` 的按钮（跳过本 Mod 的按钮），找到就让出，由 PF 的“帮助”响应。土壤图层下两个按钮都显示 X，按 X 打开 PF 帮助，地图助手按钮仍可点击（MAP-18）。

## FS25 1.25 接口核对

2026-10-21 只读核对。`work/reference/1.25.0.0/` 下：`gameSource/` 为随游戏 SDK 的可读 Lua（部分函数体被裁掉），`decompiled/scripts/` 为 1.25 反编译，`dataS-archive/` 为本次用 `work/tools/fs-utils-bin/fs-unpack.exe` 从安装目录 `dataS.gar` 解出的 1.25 GUI XML、guiProfiles 和 l10n（只读读取安装目录，输出在被忽略的 `work/`）。1.25 未改动的脚本引用 `work/reference/decompiled/dataS/scripts/`（1.24 反编译，`work/analysis/update-1.25.0.0/comparison.json` 中字节码列为 unchanged）。1.25 的 `InGameMenuMapFrame.xml` 与 1.24 存档逐字节相同。

| 接口 | 位置 | 用途 |
| --- | --- | --- |
| `InGameMenuMapFrame.AI_MODE_OVERVIEW/AI_MODE_CREATE` | 1.25 decompiled `gui/InGameMenuMapFrame.lua:10-11` | 模式判断 |
| `InGameMenuMapFrame:onFrameOpen` | 同上 `:276`（`:297` 用 `setCenterToWorldPosition`，`:299` `generateJobTypes`） | 定位方式与 `jobTypeInstances` 来源 |
| `InGameMenuMapFrame:onLoadMapFinished` | 同上 `:460`；由 `gui/InGameMenu.lua:121`、`:180` 调用 | 注入按钮的时机 |
| `getCanCancelJob/getCanCreateJob/getCanGoTo/getCanStartJob` | 同上 `:787/:790/:793/:796` | 权限与模式条件（hireAssistant、总览、非选点、无导览） |
| `refreshContextInput` | 同上 `:832` | 原生可用性判断（访问、AI 空闲、`getIsAvailableForVehicle`） |
| `setAIVehicle` | 同上 `:936` | 创建作业 |
| `setMapSelectionItem` | 同上 `:1019` | 选中车辆 hotspot |
| `startGoToJob/startJob/cancelJob` | 同上 `:1352/:1374/:1396`（`startJob` 成功分支 `:1383-1387`） | 设置目的地、验证顺序、加入队列后离开作业菜单的方式、取消调用 |
| `onClickBack` | 同上 `:1796-1812`（`AI_MODE_CREATE` 分支调用 `resetTasks`） | 说明为什么加入队列后不用它 |
| 地图页头部 `shopMoneyBoxBg`、`statusMessage` | 同上 `:1464`（余额底框宽度）、`:2023`（状态文字）；XML 见 `dataS-archive/gui/InGameMenuMapFrame.xml` | 按钮位置 |
| `onStartGoToJob/onStartCancelJob/onCreateJob` | 同上 `:1822/:1828/:1967` | 抽屉按钮 |
| `updateWarnings` | 同上 `:2003` | 验证失败提示 |
| `registerInput`、`CLEAR_INPUT_ACTIONS`、`INPUT_CONTEXT_NAME` | 同上 `:2357-2368`、`:2589-2594`、`:2588` | 菜单键注册上下文，地图页已占用的菜单 action |
| `getIsPicking/setJobMenuVisible/createJob/tryStartJob` | 同上 `:2395/:2479/:2509-2543/:2558` | 选点判断、按钮显示时机、作业菜单流程、规划模式下作业类型的筛选 |
| `ButtonElement:loadInputGlyph`、`InputDisplayManager:getFirstBindingAxisAndDeviceForActionName/getKeyboardInputActionKey` | 1.24 decompiled `gui/elements/ButtonElement.lua:199-219`、`input/InputDisplayManager.lua:689-747` | 按钮键位只显示 `axisNames[1]` |
| `MENU_EXTRA_1` 定义与默认键 | 1.25 `dataS-archive/inputActions.xml`（`locked="true"`）；安装目录 `profileTemplate/inputBindingDefault_KeyboardMouse.xml:428-430`、`inputBindingDefault_Gamepad.xml:380-382` | 菜单键与默认绑定 |
| `ControlsController` 列表、`InputBinding:getActionBindingsCopy` | 1.24 decompiled `gui/ControlsController.lua:214`；1.25 decompiled `input/InputBinding.lua:2747-2750` | locked 动作不进控制设置 |
| `TabbedMenu.DEFAULT_BUTTON_ACTIONS/onClickMenuExtra1` | 1.24 decompiled `gui/base/TabbedMenu.lua:5-12/:313` | 游戏菜单对 `MENU_EXTRA_1` 的处理 |
| Precision Farming 帮助按钮 | 1.24 decompiled `internalMods/FS25_precisionFarming/scripts/gui/InGameMenuMapFrameExtension.lua:249-257/:282` | 同一键位的显示冲突 |
| `AIJobVehicle:getCanStartAIVehicle`、`getJob` 注册 | gameSource `vehicles/specializations/AIJobVehicle.lua:488-520`、`:75` | 规划模式、服务器跟随当前作业 |
| `AIJobFieldWork/AIJobGoTo:getIsAvailableForVehicle` | gameSource `ai/jobs/AIJobFieldWork.lua:167`、`ai/jobs/AIJobGoTo.lua:92` | 规划模式 |
| 地图页 XML：`shopMoneyBox`、`createJobContainer`、`buttonStartJobContainer`、`fs25_mapButton*` | `dataS-archive/gui/InGameMenuMapFrame.xml` | 按钮位置与样式 |
| `PrecisionFarmingGUI.loadAdditionalGUI` | 1.24 decompiled `internalMods/FS25_precisionFarming/scripts/gui/PrecisionFarmingGUI.lua:4`，用法见 `InGameMenuMapFrameExtension.lua:177` | 向地图页加元素的官方先例 |
| `Gui:loadProfileSet/loadGui/loadGuiRec/getIsDialogVisible/showDialog` | gameSource `gui/base/Gui.lua:182/:280/:347/:499/:524` | GUI 加载与对话框 |
| `GuiElement:clone/setPosition/getDescendantByName` | gameSource `gui/elements/GuiElement.lua:473/:1121/:1475` | 队列行与抽屉位置 |
| `IngameMapElement:panToHotspot`、`setCenterToWorldPosition` | gameSource `gui/elements/IngameMapElement.lua:420`；1.24 decompiled `gui/elements/IngameMapElement.lua:590` | 平移地图 |
| `MessageDialog:onCreate/onOpen` | 1.24 decompiled `gui/dialogs/MessageDialog.lua:35/:46` | 抽屉基类（设为 INFO 类型） |
| `InfoDialog.show` | gameSource `gui/dialogs/InfoDialog.lua:33` | 验证失败、队列已满 |
| `AISystem:update/onClientJoined/startJob/stopJob/stopJobInternal` | gameSource `ai/AISystem.lua:460/:482/:547/:570/:583` | 启动、停止消息、延迟原因、加入同步先例 |
| `AIJob:delete/saveToXMLFile/loadFromXMLFile/readStream/writeStream/update/stop/getNamedParameter/getGroupedParameters/getIsStartable` | gameSource `ai/jobs/AIJob.lua:41/:52/:69/:83/:101/:117/:277/:395/:412/:441` | 序列化、存档、完成消息（`:152` `AIMessageSuccessFinishedJob`） |
| `AIJobLoadAndDeliver` 结束消息 | gameSource `ai/jobs/AIJobLoadAndDeliver.lua:411`（`AIMessageSuccessSiloEmpty`） | 成功判断 |
| `AIJobGoTo:getIsStartable`、`AIJobFieldWork:getIsStartable` | gameSource `ai/jobs/AIJobGoTo.lua:195`、`AIJobFieldWork.lua:243` | 启动检查、权限 |
| `AIJobFieldWork:readStream/writeStream` | gameSource `ai/jobs/AIJobFieldWork.lua:53/:64` | AI 模式设置随作业传输 |
| `AIJobTypeManager:getJobTypeIndex/createJob/getJobTypeByIndex/getJobTypeIndexByName` | gameSource `ai/AIJobTypeManager.lua:81/:92/:110/:116` | 类型索引、名称 |
| `AIJobStartRequestEvent:run`、`AIJobStopEvent:run` | gameSource `ai/events/AIJobStartRequestEvent.lua:76`、`AIJobStopEvent.lua:62` | 原生请求和停止路径 |
| `AIParameterVehicle:saveToXMLFile/setVehicle/getVehicle` | gameSource `ai/parameters/AIParameterVehicle.lua:27/:69/:75` | 车辆参数（无 loadFromXMLFile） |
| `AIParameterPosition:getPosition`、`AIParameterLoadingStation:getString` | gameSource `ai/parameters/AIParameterPosition.lua:71`、`AIParameterLoadingStation.lua:114` | 队列行文字 |
| `AIJobVehicle:onLoad/stopCurrentAIJob/aiJobFinished/getJob/getCanStartAIVehicle/saveToXMLFile` | 1.24 decompiled `vehicles/specializations/AIJobVehicle.lua:77/:170/:215/:273/:316/:434` | lastJob 存档格式、空闲判断 |
| `Enterable:getIsInUse` | gameSource `vehicles/specializations/Enterable.lua:1663` | 启动连接的选择 |
| `VehicleSystem:getVehicleByUniqueId`、`Vehicle:getUniqueId` | gameSource `vehicles/VehicleSystem.lua:271`、`vehicles/Vehicle.lua:4442` | 存档中的车辆 |
| `FSBaseMission:delete/onStartMission/sendInitialClientState/getFarmId/addIngameNotification/getHasPlayerPermission` | 1.25 decompiled `FSBaseMission.lua:167/:367/:774/:1069/:1890/:2072` | 生命周期、权限、提示 |
| `BaseMission:addUpdateable/removeUpdateable` | 1.25 decompiled `BaseMission.lua:548/:562` | 延迟启动与清理 |
| `Mission00:onStartMission` | 1.25 decompiled `mission00.lua:561`（调用父类） | 读档时机 |
| `FSCareerMissionInfo:saveToXMLFile` | 1.24 decompiled `FSCareerMissionInfo.lua:246`（`:351` 同处保存 aiSystem） | 存档时机 |
| `MessageCenter:subscribe/unsubscribeAll`、`MessageType.AI_JOB_STOPPED` | 1.25 decompiled `MessageCenter.lua:27/:68`、`MessageType.lua:133` | 完成订阅 |
| `InputBinding:registerActionEvent/removeActionEventsByTarget/setActionEventTextVisibility`、`InputAction.createFromXML` | 1.25 decompiled `input/InputBinding.lua:603/:882/:927`；1.24 decompiled `input/InputAction.lua:35`（`:49` 读 `locked`） | 菜单键事件 |
| `Connection:sendEvent`、`Server:broadcastEvent`、`NetworkUtil.writeNodeObject/readNodeObject` | 1.24 decompiled `network/Connection.lua:71`、`network/Server.lua:542`、`network/NetworkUtil.lua:16/:28` | 本地事件路径、按对象广播 |
| `XMLFile.loadIfExists/create/iterate` | 1.24 decompiled `xml/XMLFile.lua:12/:19/:187` | 存档文件 |
| `I18N:getText(name, customEnv)` | 1.24 decompiled `I18N.lua:175` | Mod 文本按 Mod 名读取 |
| `Utils.appendedFunction/prependedFunction` | 1.24 decompiled `utils/Utils.lua:380/:387` | 钩子不保留返回值，只用于无返回值的函数 |

GUI 核对（脚本校验于 `dataS-archive`）：三个 GUI XML 用到的 profile（含地图页的 `fs25_mapButton`、`fs25_mapButtonBg(Light)`、`fs25_mapButtonText`、`fs25_mapButtonContainer` 及 `fs25_dialogButtonBox`、`buttonBack`、`fs25_textDefault`、`baseReference`、`emptyPanel`、`newLayer`）、trait、preset 和 profile 字段名全部存在；按钮切片 `gui.button_left/middle/right` 在 `menu/gui.xml` 中存在；XML 中引用的原生文本 `button_createJob/startJob/gotoJob/delete/back` 及脚本里的 `button_startJob/button_cancelJob` 都在 l10n 中。键位核对：安装目录 `profileTemplate/inputBindingDefault_KeyboardMouse.xml`（菜单键 `:404-:454`，`MENU_EXTRA_1` = X `:428-430`）和 `inputBindingDefault_Gamepad.xml`（`MENU_EXTRA_1` = `BUTTON_11` `:380-382`）。

## 构建与测试

从仓库根目录执行：

```powershell
uv run map-helper-mod/tests/run.py
python map-helper-mod/tools/build.py
uv run map-helper-mod/tools/make_icon.py --texconv <texconv.exe路径>
```

`run.py` 用固定版本 Lupa 执行：l10n 检查（脚本用到的 20 个 Mod 文本键都在 modDesc 中，27 种语言齐全、格式参数一致）、31 项行为测试、缺少游戏函数时的降级检查和 7 组多人模拟。`build.py` 输出 `outputs/FS25_MapHelper.zip`，不安装、不改存档、不启动游戏。图标脚本默认使用 PATH 或被忽略的 `work/tools/directxtex/texconv.exe`。

行为测试覆盖：步行/车内/无 AI/暂停/选点时的抽屉状态，hireAssistant 与农场权限（客户端显示和服务器拒绝），加入队列的验证、离开作业菜单和对象所有权，只对当前驾驶车辆显示，帮手工作期间加入（规划模式、隐藏“开始作业”、服务器跟随当前作业并在其后继续），作业菜单出错时也恢复车辆，上限与服务器端验证，按 id 删除和清空，开始队列，成功（含 SiloEmpty）才推进、玩家停止/错误/删除都暂停，启动失败保留队首并显示原生原因，排队的田地作业不带旧帮手设置（替身按原生写入车辆当时的设置、读出存入 pendingData、首次 update 应用），启用 → 未启用 → 启用三个存档连续加载时控件、按键、抽屉的移除与重建，玩家自己座位不算占用，忽略非队列作业，车辆删除与易主，事件序列化，存档往返与丢弃，空队列覆盖旧存档，加入同步，钩子与按钮幂等，菜单键（打开抽屉、在作业菜单中加入队列），抽屉列表与按钮，抽屉右侧滑入与高度随内容，需要地图的操作先关抽屉，客户端只发请求。

多人模拟：服务器和多个客户端各用独立 Lua 环境，经有序队列交换真实 Mod 事件。覆盖：经理请求由服务器应用并广播，无权限成员和其他农场被拒；主机修改与两人同时删除同一项；成功后逐项推进并只通知本农场；玩家停止后各端一致暂停、只有经理能继续；加入时收到当前队列；服务器存档、重载、加入后开始；专用服务器（无本地玩家）在出错后暂停。替身不模拟原生 AI 事件、对象创建、ghost 和断线，不能代替双机实测。

## 游戏内回归清单（全部待执行）

单人、主机 + 客户端、专用服务器各测一遍；每项记录构建提交和 SHA256，并检查 `log.txt` 中没有 `[Map Helper]` 警告和 Lua 错误。

- MAP-01：载入存档后打开地图页，余额下方出现“地图助手”按钮，只有一个；退出到主菜单再载入另一个存档，仍只有一个。日志无 GUI profile 或回调警告。
- MAP-02：鼠标点击按钮和 X 都能打开抽屉；按钮上显示 X；抽屉出现在按钮下方，不遮挡左侧筛选栏；Esc 和“返回”关闭；不同分辨率/超宽屏下位置正确。按 X 时没有原版功能同时触发（键鼠默认表中 X 另外只绑定手持工具、`IMPLEMENT_EXTRA2`、`YARDER_FOLLOW_HOME` 和建造相机缩放，都不在地图页生效）。
- MAP-03：步行打开抽屉，只显示“定位到我”，点击后地图移到玩家位置。
- MAP-04：坐在拖拉机里，“定位到我”把地图移到车辆并显示原生右侧上下文框。
- MAP-05：“创建作业”打开原生作业菜单，作业类型、参数与地图上点车辆再点“创建作业”相同；没有 hireAssistant 权限的成员按钮不可用。
- MAP-06：“设置目的地”进入原生选点和方向，确认后帮手开过去；右键/返回取消选点后地图正常。
- MAP-07：作业菜单中“加入队列”显示在“开始作业”上方，不遮挡参数（参数较多的田地作业、装载和运送也要看）；按钮上显示 X，按 X 同样有效；作业菜单打开期间头部的“地图助手”按钮隐藏，关闭后重新出现；验证失败时出现原生提示；加入后作业菜单关闭，抽屉打开并显示队列，新项在最后；该作业没有被清空（开始队列后照常执行）。
- MAP-08：排 3 项（前往田边 → 田地工作 → 前往农场），“开始队列”后依次执行；每项完成约 1.5 秒后开始下一项；全部完成后出现完成提示；帮手费用正常。
- MAP-09：田地工作排队后再改车辆的帮手设置，开始后确认按新设置执行；客户端排队、主机执行时同样如此；存档读回后开始也按车辆当时的设置。
- MAP-10：执行中用抽屉“取消作业”、车内 H 键、地图上原生“取消作业”分别停止：队列都暂停，剩余项保留，出现暂停提示，“开始队列”可继续。
- MAP-11：制造失败（缺种子/肥料、缺油、没钱、被挡住、田地不属于自己）：队列暂停并显示原生停止原因；帮手数量达上限时开始队列，抽屉显示原生“帮手过多”原因，项不丢失。
- MAP-12：删除单项、清空队列；执行中清空后当前帮手继续工作且完成后不再启动其他项。
- MAP-13：存档、退出、重新载入：队列保留且不自动开始；卖掉其中一辆车后保存再载入，该车队列被丢弃并在日志写 info。
- MAP-14：联机：客户端经理添加/删除/开始，其他客户端抽屉同步；无权限成员和其他农场不能修改；之后加入的玩家看到队列；规划者离开后队列继续；提示只出现在本农场玩家。
- MAP-15：车辆卖出或转给其他农场时队列消失；作业执行中车辆被重置/删除时队列暂停或删除，无报错。
- MAP-16：手柄：不做任何设置，按钮上显示手柄的默认键（`MENU_EXTRA_1` 的手柄默认绑定 `BUTTON_11`，记录它对应的实体按键），按下可打开抽屉，作业菜单中可加入队列；抽屉内可上下选择按钮并确认。控制设置中确认这个菜单键能否修改（代码显示 locked 动作不在列表中）；如果能改，改键后按钮显示新键且两个按钮都跟随。
- MAP-17：切换中文、德文等语言检查抽屉文字长度与换行；队列行过长时滚动显示。
- MAP-18：与 Precision Farming 地图页扩展同时使用（新增的土壤页面、实验室窗口），确认按钮和抽屉互不遮挡。土壤图层下 PF 的“帮助”按钮也显示 X：按 X 打开 PF 帮助、不打开地图助手抽屉，鼠标点击“地图助手”仍打开抽屉；切回其他图层后按 X 打开抽屉。
- MAP-19：载入启用本 Mod 的存档，回主菜单，载入未启用本 Mod 的存档：地图页没有“地图助手”按钮，按 X 时只有原版行为；再载入启用的存档，按钮只有一个且可用。
- MAP-20：右侧布局：按钮右对齐余额底框，位于余额和帮手状态行下方，不遮挡两者；有帮手状态消息（例如帮手开始/完成）时也不重叠；余额位数变化（例如大额买卖后）、切换分辨率和 UI 缩放后重新进入地图页，位置仍正确。
- MAP-21：抽屉高度与滑入：步行时抽屉只有标题、状态和“定位到我”，高度很小；车内显示操作按钮和队列，空队列与 6 项以上队列时高度正确、底部按钮不被遮挡；每次打开都从右侧滑入，停在按钮下方并与按钮右对齐；队列增删时高度随之变化。
- MAP-22：帮手工作期间加入：玩家直接开始一个田地作业（不经队列），帮手驾驶时打开抽屉，“创建作业”显示为“加入队列”，“设置目的地”不可用；点击后作业菜单只显示“加入队列”，没有“开始作业”；作业类型列表与车辆空闲时相同（含“前往”）；加入一项“前往农场”后，当前作业完成约 1.5 秒后自动执行该项。重复一次但在中途停止当前作业：队列暂停，“开始队列”可继续。离开作业菜单后再为空闲车辆打开，“开始作业”重新出现。帮手的行为（转向、设置）不受规划影响。
- MAP-23：队列运行中（两项之间的间隔，或由队列开始的作业执行中）加入新项，新项排在最后并按顺序执行；联机时客户端在帮手工作期间加入，服务器同样在当前作业后继续。
