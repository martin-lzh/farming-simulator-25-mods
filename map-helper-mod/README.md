# Map Helper · 地图助手

<p align="center">
  <a href="LICENSE"><img alt="License: PolyForm Noncommercial 1.0.0" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue"></a>
  <img alt="Farming Simulator 25 1.25" src="https://img.shields.io/badge/Farming%20Simulator%2025-1.25-5c8a1f">
  <img alt="Platform: PC" src="https://img.shields.io/badge/platform-PC-lightgrey">
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">中文</a>
</p>

## English

Version 0.1.0.0 · Farming Simulator 25 1.25 (PC)

Plan worker jobs for your vehicles straight from the map. Map Helper adds a page to the left sidebar of the map, next to the map filters and Active Workers. It shows which of your fields need the work your vehicle does, lets you set up jobs with the game's own job settings and keeps them in a to-do list: when one job is done, the next one starts by itself.

### Open the page

- Press **Left Alt + M** anywhere in the game, on foot or in a vehicle. The map opens on the Map Helper page. You can change the key in the controls.
- Or open the map in the in-game menu and click **Map Helper** below your balance, or press the key shown on it (X by default).
- Or browse the sidebar pages with the arrows at the top of the sidebar until you reach Map Helper.

### The page, from top to bottom

**Vehicle.** The page works with the vehicle you are sitting in. To plan for another of your vehicles, click it on the map while the page is open; click the vehicle card to go back to yours. The card shows the vehicle's name and whether a worker is driving it, the queue is paused or jobs are waiting. On your own vehicle, clicking the card moves the map to it.

**Places.** The selector above the list chooses what it shows, one kind at a time:

| Choice | What the list shows |
| --- | --- |
| Fields needing this work | First your accepted contracts whose job the vehicle and its tools can do (for example a ploughing contract when a plough is attached), then your own fields that need what they do: for example plowing on stubble, sowing on prepared soil, lime, fertilizer or herbicide (by what is in the sprayer), weeding, rolling, mulching stubble, mowing ready grass, harvesting the crops the header takes, removing foliage, stone picking. Each row names the work. |
| My fields | All your fields with their state, such as Ready to harvest, Growing, Needs lime or Plowed. |
| Contracts | Your accepted field contracts with their progress. Contracts this vehicle can work on come first and name the work. |
| Stations | Where the vehicle can load or deliver. Only offered when it can do delivery jobs. |

The page starts with Fields needing this work when it recognises the vehicle's tools, otherwise with My fields, and remembers your choice for each vehicle while you play. Field states are read every few seconds, at the same point of each field the game uses for the field's state. Click a place to move the map there and fill in the job below: a field or contract sets field work there (or Go to, if the vehicle can't do field work), a station sets load and deliver or deliver with that station.

**Job.** The game's own job settings, the same as when you create a job for the vehicle on the map: job type, target position and direction (picked on the map), stations, fill type and looping. Then:

| Button | Key | What it does |
| --- | --- | --- |
| Add to queue | Z | Adds the job at the end of the queue. If no worker is driving the vehicle, the job starts right away. |
| Insert as next | X | Adds the job at the front, so it runs next. |

The keys are shown on the buttons; controllers have their own default buttons. If something in the job is missing or wrong, the game's own warning tells you what.

**Command queue.** A to-do list for the vehicle. The job a worker is driving now comes first, with what it is doing, the distance left to its target and, on a contract field, the contract's progress. Below it are the waiting jobs, numbered in the order they run. Select a row to:

| Button | What it does |
| --- | --- |
| Arrows | Move a waiting job up or down. |
| Edit | Load a waiting job into the job settings above. Change it, then click **Save** (Z), or **Cancel** (X) to leave it as it was. |
| Delete | Remove a waiting job. On the current job it reads **Cancel job** and stops the worker. |
| Clear queue | Remove all waiting jobs. |
| Resume | Shown when jobs are waiting but no worker is driving, for example after a stop. Starts the first waiting job. |

When a job is done, it disappears and the next one starts a moment later. You can add, move, edit and delete waiting jobs at any time, also while a worker is driving. The queue then continues after the current job, even one you started yourself. A vehicle can have up to 10 waiting jobs.

Field work uses the worker settings your vehicle has when that job starts, not the ones it had when you queued it. If you change the settings in between, the new settings apply.

If you stop a job, or a job can't be finished (for example out of fuel or seed, blocked, or the field isn't ready), the queue pauses. The remaining jobs stay, the card shows the reason, and you get a message. Fix the problem and click **Resume**, or add a job: the queue continues with its first waiting job. The queue also pauses when the next job can't start, for example because too many workers are active.

Queued jobs are kept when you save. After loading, the queue waits until you click **Resume** or add a job. A worker who was driving when you saved isn't restarted, just like in the base game.

On the Precision Farming soil map, X opens its Help instead; click Map Helper there.

### Multiplayer

- The server and every player need the same version of the Mod.
- Farm members who are allowed to hire workers can plan and change the queues of their farm's vehicles. Other players can look at the page but can't change the queue.
- The server runs the queues: they keep going when the player who planned them leaves, and players who join later see them.
- Messages about a paused or finished queue go to the members of the vehicle's farm.

Map Helper uses the game's own worker jobs, such as go to, field work, deliver and load and deliver, and worker costs stay the same. Other Mods that change the map page or the worker menus may not work together with it; try them in a separate save first.

### Install and update

Put `FS25_MapHelper.zip` in `Documents\My Games\FarmingSimulator2025\mods` and activate the Mod when you load a save. To update, replace the old ZIP with the new one; your queues are kept.

### Uninstall

Let your queues finish or clear them, save, then remove the ZIP. Workers and the game's own jobs are not affected.

### License

PolyForm Noncommercial License 1.0.0, see [LICENSE](LICENSE). Free for non-commercial use; commercial use is not allowed.

## 中文

版本 0.1.0.0 · 模拟农场 25 1.25（PC）

直接在地图上为你的车辆安排帮手作业。地图助手在地图左侧边栏加入一个页面，与地图筛选和“在岗帮手”并列。它列出哪些田地需要你的车辆所做的作业，让你用游戏自带的作业设置安排作业，并把作业放进待办清单：一个作业完成后，下一个会自动开始。

### 打开页面

- 在游戏中任何时候按 **左 Alt + M**，步行或驾驶时都可以。地图会直接打开地图助手页面。按键可在控制设置中更改。
- 或者在游戏菜单中打开地图，点击余额下方的 **地图助手**，或按其上显示的按键（默认为 X）。
- 或者用边栏顶部的箭头翻页，直到地图助手页面。

### 页面内容（自上而下）

**车辆。** 页面作用于你当前驾驶的车辆。要为你的其他车辆安排作业，在页面打开时在地图上点击那台车辆；点击车辆卡片即可回到你自己的车辆。卡片显示车辆名称，以及是否有帮手在驾驶、队列是否暂停、有几个作业在等待。显示的是你自己的车辆时，点击卡片会把地图移到车辆处。

**地点。** 列表上方的选择器决定列表显示的内容，每次只显示一类：

| 选项 | 列表内容 |
| --- | --- |
| 需要此作业的田地 | 先列出已接合同中这台车辆及其农具能完成的（例如挂着犁时的犁地合同），再列出你的田地中需要这台车辆及其农具作业的那些：例如在收割后的田地上犁地、在整好的土地上播种、按喷洒机里装的东西施石灰、施肥或除草剂、除草、镇压、粉碎残茬、割成熟的草、收割割台能收的作物、去除茎叶、捡石头。每一行写明需要的作业。 |
| 我的田地 | 你所有的田地及其状态，例如可收获、生长中、需要石灰、已犁地。 |
| 合同 | 已接受的田地合同及其进度。这台车辆能做的合同排在前面并写明作业。 |
| 站点 | 车辆可以装货或卸货的地方。只在车辆能执行运送类作业时提供。 |

页面识别出车辆的农具时，默认显示“需要此作业的田地”，否则显示“我的田地”；每台车辆的选择在游戏期间会被记住。田地状态每隔几秒读取一次，读取点与游戏记录田地状态时使用的点相同。点击一个地点，地图会移到该处，并在下方填好作业：田地或合同会设为在该处进行田地工作（车辆不能进行田地工作时设为“前往”），站点会设为使用该站点的“装载和运送”或“运送”。

**作业。** 游戏自带的作业设置，与在地图上为车辆创建作业时相同：作业类型、目标位置和方向（在地图上选择）、站点、填充类型和循环。然后：

| 按钮 | 按键 | 作用 |
| --- | --- | --- |
| 加入队列 | Z | 把作业加到队列末尾。没有帮手驾驶这台车辆时，作业会立即开始。 |
| 插入为下一个 | X | 把作业加到队列最前面，下一个就执行它。 |

按键显示在按钮上；手柄有自己的默认按键。作业缺少或填错了什么，游戏自带的提示会告诉你。

**指令队列。** 这台车辆的待办清单。帮手正在执行的作业排在最前，显示它正在做什么、离目标还有多远，以及在合同田地上的合同进度。下面是等待中的作业，按执行顺序编号。选中一行后可以：

| 按钮 | 作用 |
| --- | --- |
| 箭头 | 把等待中的作业上移或下移。 |
| 编辑 | 把等待中的作业载入上方的作业设置。修改后点击 **保存**（Z），或点击 **取消**（X）保持原样。 |
| 删除 | 删除等待中的作业。选中当前作业时显示为 **取消作业**，让帮手停下。 |
| 清空队列 | 删除所有等待中的作业。 |
| 继续队列 | 有作业在等待但没有帮手驾驶时显示，例如停止之后。开始第一个等待中的作业。 |

作业完成后会从列表中消失，稍后下一个作业开始。等待中的作业随时可以添加、移动、编辑和删除，帮手驾驶时也可以。队列会在当前作业之后继续，即使这个作业是你直接开始的。每台车辆最多可有 10 个等待中的作业。

田地工作使用该作业开始时车辆的帮手设置，而不是加入队列时的设置。中途修改设置，开始时按新设置执行。

如果你停止了作业，或作业无法完成（例如燃料或种子用完、被挡住、田地未准备好），队列会暂停：剩余作业保留，卡片显示原因，并提示你。解决问题后点击 **继续队列** 或加入一个作业，队列从第一个等待中的作业继续。下一个作业无法开始时（例如在岗帮手太多），队列同样暂停。

保存游戏时，队列中的作业一并保存。读档后，队列会等待你点击 **继续队列** 或加入作业。保存时正在工作的帮手不会重新开始，与原版相同。

在精准农业的土壤图层上，X 会打开它的帮助，此时请直接点击“地图助手”。

### 多人游戏

- 服务器和所有玩家需要安装同一版本的 Mod。
- 有雇佣帮手权限的农场成员可以为本农场车辆安排和修改队列。其他玩家可以查看页面，但不能修改队列。
- 队列由服务器执行：安排队列的玩家离开后队列会继续，之后加入的玩家也能看到。
- 队列暂停或完成的提示只发给车辆所属农场的成员。

地图助手使用游戏自带的帮手作业，例如前往、田地工作、运送、装载和运送，帮手费用与原版相同。修改地图页面或帮手菜单的其他 Mod 可能无法与本 Mod 共用，请先在单独的存档中试用。

### 安装与更新

把 `FS25_MapHelper.zip` 放进 `文档\My Games\FarmingSimulator2025\mods`，载入存档时勾选本 Mod。更新时用新 ZIP 替换旧 ZIP，原有队列保留。

### 卸载

让队列执行完或将其清空，保存后再删除 ZIP。帮手和游戏自带的作业不受影响。

### 许可

PolyForm Noncommercial 1.0.0 许可，见 [LICENSE](LICENSE)。可免费用于非商业用途，不允许商用。
