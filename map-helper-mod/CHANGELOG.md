# Changelog / 版本记录

## Unreleased

- First version. Adds a Map Helper page to the left sidebar of the map in the in-game menu, next to the map filters and Active Workers.
- 首个版本。在游戏菜单地图的左侧边栏加入“地图助手”页面，与地图筛选和“在岗帮手”并列。
- Left Alt + M opens the map on the Map Helper page, on foot or in a vehicle. On the map, Map Helper in the button bar at the bottom and its key (X by default) switch to the page.
- 左 Alt + M 直接打开地图并显示地图助手页面，步行或驾驶时都可以。在地图上，底部按钮栏中的“地图助手”及其按键（默认为 X）切换到该页面。
- The page works with the vehicle you are sitting in. Click another of your vehicles on the map to plan for it; click the vehicle card to go back to yours.
- 页面作用于你当前驾驶的车辆。在地图上点击你的其他车辆即可为它安排作业；点击车辆卡片回到你自己的车辆。
- A selector chooses what the places list shows: fields needing the work the vehicle and its tools do, all your fields with their state, your contracts, or the stations for delivery jobs. The choice is remembered for each vehicle.
- 选择器决定地点列表显示的内容：需要车辆及其农具作业的田地、所有田地及其状态、你的合同，或运送作业用的站点。每台车辆的选择会被记住。
- Fields needing the work covers plowing, cultivating, sowing, lime, fertilizer, herbicide, weeding, rolling, mulching, mowing, harvesting, removing foliage and stone picking. Contracts the vehicle can work on come first.
- “需要此作业的田地”涵盖犁地、耕地、播种、施石灰、施肥、喷除草剂、除草、镇压、粉碎残茬、割草、收割、去除茎叶和捡石头。车辆能做的合同排在前面。
- Fields needing this work also lists your accepted contracts whose job the vehicle can do, first; contract fields are not yours, so they were missing before.
- “需要此作业的田地”也会列出车辆能完成的已接合同，并排在最前；合同田地不属于你，之前因此没有显示。
- Fields you merged by working the strip between them show as one row, such as Field No. 3 + 4 + 5.
- 通过耕作中间地带合并的田地显示为一行，例如“田地编号 3 + 4 + 5”。
- Double-click a field or contract to add field work there to the queue straight away.
- 双击田地或合同，可直接把该处的田地工作加入队列。
- Places a worker is already working are marked Worker on it, places waiting in a queue Queued; both come last in the work and contract lists.
- 已有帮手在作业的地点标为“帮手作业中”，在队列中等待的标为“已在队列”；两者在作业和合同列表中排在最后。
- The job form takes only the height its job type needs; with field work the places list shows about ten rows.
- 作业表单只占用该作业类型需要的高度；田地工作时地点列表可显示约十行。
- Click a place to move the map there and fill in the job.
- 点击一个地点，地图会移到该处并填好作业。
- Jobs are set up with the game's own job settings, including picking the target on the map. Add to queue (Z) puts the job at the end, Insert as next (X) puts it first.
- 作业使用游戏自带的作业设置，包括在地图上选择目标。“加入队列”（Z）把作业排到最后，“插入为下一个”（X）把作业排到最前。
- The first job you add to a vehicle without a worker starts right away.
- 为没有帮手驾驶的车辆加入的第一个作业会立即开始。
- The command queue works like a to-do list: the current job shows what it is doing, the distance to its target and the progress of a contract, finished jobs disappear and the next one starts by itself.
- 指令队列就像待办清单：当前作业显示正在做什么、离目标的距离和合同进度，完成的作业自动消失，下一个自动开始。
- Waiting jobs can be moved up or down, edited and deleted at any time, also while a worker is driving. Delete on the current job reads Cancel job and stops the worker.
- 等待中的作业随时可以上移、下移、编辑和删除，帮手驾驶时也可以。选中当前作业时，“删除”显示为“取消作业”，让帮手停下。
- The queue continues after the current job, even one you started yourself.
- 队列会在当前作业之后继续，即使这个作业是你直接开始的。
- Queued field work uses the worker settings the vehicle has when the job starts.
- 排队的田地工作使用作业开始时车辆的帮手设置。
- If a job is stopped or can't be finished, the queue pauses, shows the reason and you get a message. Resume, or adding a job, continues it.
- 作业被停止或无法完成时，队列暂停并显示原因，同时提示你。点击“继续队列”或加入作业即可继续。
- Queues are saved with the game. In multiplayer, the server runs them, farm members allowed to hire workers can change them, and players who join later see them.
- 队列随存档保存。多人游戏中由服务器执行，有雇佣帮手权限的农场成员可以修改，之后加入的玩家也能看到。
- After loading, the queue also continues after a worker that starts on the vehicle, for example one who carries on with the field work he was doing when you saved, one you start yourself or one another Mod starts. Before, only that job ran and the queue stopped.
- 读档后，车辆上开始工作的帮手（例如接着做保存时田地工作的帮手、你自己开始的或其他 Mod 启动的）完成作业后，队列也会继续。之前只执行这一个作业，队列随后停下。
- The next job in the queue starts only once the vehicle has stopped and its implements have finished folding or lifting, so the worker doesn't drive off while a sprayer boom is still folding.
- 队列中的下一个作业要等车辆停稳、农具折叠或升起完毕后才开始，帮手不会在喷杆还在折叠时就开走。
- A queued job whose target is missing in the save file is left out when you load, instead of stopping the save from loading.
- 存档文件中缺少目标的排队作业在读档时被略过，不再导致存档无法载入。
- Attaching or detaching an implement while the Map Helper page is open now also switches the job types: within a few seconds fields are set up as field work (or Go to) to match.
- 在地图助手页面打开时挂上或卸下农具，作业类型也会随之更新：几秒内点击田地会相应地填为田地工作（或前往）。
- Fields needing this work only lists fields where the work can be done now: no lime or rolling on growing crops, stone picking only on worked soil, mulching on harvested or withered crops that haven't been mulched yet, herbicide also on harvested grain and root crops before harvest, and sowing only when the selected seed is in season (rice only on rice fields).
- “需要此作业的田地”只列出现在就能做这项作业的田地：生长中的作物上不施石灰、不镇压，只在整过的土地上捡石头，粉碎收获后或枯萎、尚未粉碎过的作物，除草剂也用于收获后的谷物和收获前的根茎作物，所选种子在播种季节内才列出播种（水稻只在稻田）。
- Available in all 27 game languages.
- 支持全部 27 种游戏语言。

## 0.1.0.0 — 2026-10-21
