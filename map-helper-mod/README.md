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

Give orders to the vehicle you are sitting in straight from the map. Map Helper adds a drawer to the map page of the in-game menu, so you no longer have to find your vehicle on the map and click it first. You can also line up several worker jobs for one vehicle: when one job is done, the next one starts by itself.

### How to use

1. Open the in-game menu and go to the map page.
2. Click **Map Helper** on the right, below your balance and the worker status line, or press the key shown on the button.
3. The drawer slides in from the right, under the button, for the vehicle you are sitting in:

| Button | What it does |
| --- | --- |
| Center on me | Moves the map to your vehicle and selects it. On foot, it moves the map to you. |
| Create job | Opens the game's job menu for your vehicle. While a worker is driving it, this button reads **Add to queue** (see Command queue). |
| Start queue / Cancel job | Starts the jobs waiting in the queue, or stops the worker who is driving your vehicle. While the job menu is open, it shows Start job and starts the job you are setting up. |
| Set destination | Pick a point and a direction on the map; a worker drives your vehicle there right away. Only available while no worker is driving your vehicle. |
| Clear queue | Removes all waiting jobs. |

On foot, the drawer is small and only offers Center on me. **Back** or Esc closes the drawer.

Map Helper uses the game's own menu key: X on the keyboard by default, and controllers have their own default button. The key is shown on the button. On the map page it opens the drawer. In the job menu it adds the job to the queue, and the Map Helper button is hidden there. On the Precision Farming soil map, X opens its Help instead; click Map Helper there.

### Command queue

1. Sit in the vehicle, open Map Helper and click **Create job**. Set up the job as usual, for example Go to with a point near the field.
2. Click **Add to queue**, just above Start job, or press the key shown on it. The job menu closes and the drawer opens on the queue, with the new job at the end.
3. Repeat for the next jobs, for example field work on that field, then Go to back to the farm. A vehicle can have up to 10 waiting jobs.
4. Click **Start queue**. The first job starts. Each time a job is finished, the next one starts a moment later.

You can keep adding jobs while a worker is driving, like adding items to a to-do list. **Create job** then reads **Add to queue**, and the job menu only offers Add to queue, not Start job. The queue continues after the current job, even if you started that job yourself and not from the queue. To queue a drive somewhere, choose the Go to job type in the job menu: Set destination starts right away, so it is only offered while no worker is driving.

Field work uses the worker settings your vehicle has when that job starts, not the ones it had when you queued it. If you change the settings in between, the new settings apply.

If you stop a job, or a job can't be finished (for example out of fuel or seed, blocked, or the field isn't ready), the queue pauses. The remaining jobs stay, and you get a message. Fix the problem and click **Start queue** to continue, or remove jobs with **Delete**. The queue also pauses when the next job can't start, for example because too many workers are active; the drawer shows the reason.

Queued jobs are kept when you save. After loading, the queue waits until you click **Start queue**. A worker who was driving when you saved isn't restarted, just like in the base game.

Multiplayer:

- The server and every player need the same version of the Mod.
- Farm members who are allowed to hire workers can add, remove, start and clear the queue of their farm's vehicles. Other players can open the drawer but can't change the queue.
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

直接在地图上给你正在驾驶的车辆下达指令。地图助手在游戏菜单的地图页面加入一个抽屉，你不必再先在地图上找到自己的车辆、点击它。你还可以为一台车辆排好多个帮手作业：一个作业完成后，下一个会自动开始。

### 使用方法

1. 打开游戏菜单，进入地图页面。
2. 点击右侧余额和帮手状态行下方的“地图助手”，或按按钮上显示的按键。
3. 抽屉从右侧滑出，位于按钮下方，针对你当前驾驶的车辆：

| 按钮 | 作用 |
| --- | --- |
| 定位到我 | 将地图移到你的车辆并选中它。步行时将地图移到你所在的位置。 |
| 创建作业 | 为你的车辆打开游戏的作业菜单。帮手正在驾驶时，此按钮显示为“加入队列”（见“指令队列”）。 |
| 开始队列 / 取消作业 | 开始队列中等待的作业，或停止正在驾驶你车辆的帮手。作业菜单打开时，此按钮显示“开始作业”，开始你正在设置的作业。 |
| 设置目的地 | 在地图上选择地点和方向，帮手会立即把车开过去。只在没有帮手驾驶你的车辆时可用。 |
| 清空队列 | 删除所有等待中的作业。 |

步行时，抽屉较小，只提供“定位到我”。按“返回”或 Esc 关闭抽屉。

地图助手使用游戏自带的菜单键：键盘默认为 X，手柄也有自己的默认按键。按键显示在按钮上。在地图页面按下会打开抽屉；在作业菜单中按下会把作业加入队列，此时“地图助手”按钮隐藏。在精准农业的土壤图层上，X 会打开它的帮助，此时请直接点击“地图助手”。

### 指令队列

1. 坐进车辆，打开地图助手，点击“创建作业”。照常设置作业，例如选择“前往”，目的地设在田地附近。
2. 点击“开始作业”上方的“加入队列”，或按其上显示的按键。作业菜单关闭，抽屉打开并显示队列，新作业排在最后。
3. 按同样方法添加后续作业，例如在这块田地进行田地工作，再“前往”返回农场。每台车辆最多可有 10 个等待中的作业。
4. 点击“开始队列”。第一个作业开始；每完成一个作业，稍后会自动开始下一个。

帮手驾驶期间也可以继续添加作业，就像往待办清单里添项。此时“创建作业”显示为“加入队列”，作业菜单只提供“加入队列”，不提供“开始作业”。队列会在当前作业之后继续，即使这个作业是你直接开始、而不是从队列开始的。想让车辆排队开往某处，请在作业菜单中选择“前往”作业类型：“设置目的地”会立即出发，所以只在没有帮手驾驶时提供。

田地工作使用该作业开始时车辆的帮手设置，而不是加入队列时的设置。中途修改设置，开始时按新设置执行。

如果你停止了作业，或作业无法完成（例如燃料或种子用完、被挡住、田地未准备好），队列会暂停：剩余作业保留，并提示你。解决问题后点击“开始队列”继续，或用“删除”移除作业。下一个作业无法开始时（例如在岗帮手太多），队列同样暂停，抽屉会显示原因。

保存游戏时，队列中的作业一并保存。读档后，队列会等待你点击“开始队列”。保存时正在工作的帮手不会重新开始，与原版相同。

多人游戏：

- 服务器和所有玩家需要安装同一版本的 Mod。
- 有雇佣帮手权限的农场成员可以添加、删除、开始和清空本农场车辆的队列。其他玩家可以打开抽屉，但不能修改队列。
- 队列由服务器执行：安排队列的玩家离开后队列会继续，之后加入的玩家也能看到。
- 队列暂停或完成的提示只发给车辆所属农场的成员。

地图助手使用游戏自带的帮手作业，例如前往、田地工作、运送、装载和运送，帮手费用与原版相同。修改地图页面或帮手菜单的其他 Mod 可能无法与本 Mod 共用，请先在单独的存档中试用。

### 安装与更新

把 `FS25_MapHelper.zip` 放进 `文档\My Games\FarmingSimulator2025\mods`，载入存档时勾选本 Mod。更新时用新 ZIP 替换旧 ZIP，原有队列保留。

### 卸载

让队列执行完或将其清空，保存后再删除 ZIP。帮手和游戏自带的作业不受影响。

### 许可

PolyForm Noncommercial 1.0.0 许可，见 [LICENSE](LICENSE)。可免费用于非商业用途，不允许商用。
