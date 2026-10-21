# Fill Type Selector · 肥料选择

<p align="center">
  <a href="https://github.com/martin-lzh/farming-simulator-25-mods/releases?q=fill-type-selector&amp;expanded=true"><img alt="Latest release" src="https://img.shields.io/github/v/release/martin-lzh/farming-simulator-25-mods?filter=fill-type-selector-v%2A&amp;include_prereleases&amp;label=latest%20release"></a>
  <a href="LICENSE"><img alt="License: PolyForm Noncommercial 1.0.0" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue"></a>
  <img alt="Farming Simulator 25 1.25" src="https://img.shields.io/badge/Farming%20Simulator%2025-1.25-5c8a1f">
  <img alt="Platform: PC" src="https://img.shields.io/badge/platform-PC-lightgrey">
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">中文</a>
</p>

## English

Version 0.1.0.0 · Farming Simulator 25 1.25 (PC)

**Download:** [GitHub releases](https://github.com/martin-lzh/farming-simulator-25-mods/releases?q=fill-type-selector&expanded=true) (`FS25_FillTypeSelector.zip` under **Assets**)

Choose what an empty fertilizer spreader, sprayer or lime spreader will apply, the same way you choose seeds on a seeder. You no longer have to put some lime or fertilizer in the tank first so that an AI worker spreads the right thing.

### How to use

1. Get into the tractor with the empty spreader or sprayer attached.
2. Press **Y** to switch between the types the implement can apply; **Shift+Y** goes back. The help (F1) shows, for example, **Select fertilizer (Lime)**, and the empty tank shows your choice.
3. If the implement or the combination already uses Y, for example a seeder with several seeds, Precision Farming, or a Pumps n' Hoses tool carrier or hose reel, the key is **Alt+Y**. You can change it in Settings → Controls under Fill Type Selector.

Implements that can only take one type don't get the key. With two choosable implements attached, the key works on the selected one.

### AI workers and automatic buying

- Turn on **AI Worker Refill - Fertilizer** in Settings → Game Settings. A worker with an empty implement then buys the type you chose, lime and herbicide included, at the game's usual refill price.
- With the setting off, the worker stops when the tank is empty, as in the base game.
- The worker follows the game's field rules for the chosen type, for example it skips land that already has lime.
- Lime-only spreaders don't need the key: the worker buys lime for them.
- Manure spreaders that can also spread lime: lime is bought under **AI Worker Refill - Fertilizer**, manure under **AI Worker Refill - Manure**.
- Without a choice, everything works as in the base game: sprayers buy liquid fertilizer, spreaders buy fertilizer.

### Good to know

- When the tank holds something, that content is used and the choice is locked; the key is hidden. Once the tank is empty again, your choice applies again.
- An attached tank with content, such as a front tank, is used before your choice, as in the base game.
- You can only choose what the implement is built to spread: fertilizer, liquid fertilizer, lime, herbicide or manure. A trailer that only carries lime in its tank, such as a universal trailer with a manure spreader, offers manure only.
- With the Pumps n' Hoses pack: manure spreaders can also choose separated manure. The worker buys it when **AI Worker Refill - Manure** is set to buy; with a manure heap selected it uses manure. Drag hose applicators fed through a hose have nothing to choose.
- Slurry tankers that take slurry and digestate: choose which of the two the worker uses. Under **AI Worker Refill - Slurry** it buys the chosen type, or takes it from your slurry pit first and the other type when that runs out. Without a choice the game uses slurry, as before.
- Spreaders with a separate lime setup switch to it when you choose lime, so the worker uses the same working width as with lime in the tank.

### Multiplayer

- Everyone needs the same version of the Mod.
- Players whose farm may use the vehicle can change the choice while the tank is empty and no AI worker is using the implement. It is synchronized, saved with the vehicle, and players who join later receive it.
- If two players change it at the same moment, the change the server receives last applies for everyone.
- Only the server pays for bought fill, so nothing is charged twice.

### Install and update

Put `FS25_FillTypeSelector.zip` in `Documents\My Games\FarmingSimulator2025\mods` and activate the Mod when you load a save. To update, replace the old ZIP with the new one; your choices are kept.

### Uninstall

Remove the ZIP. Vehicles keep their content; the saved choices are simply no longer used.

### License

PolyForm Noncommercial License 1.0.0, see [LICENSE](LICENSE). Free for non-commercial use; commercial use is not allowed.

## 中文

版本 0.1.0.0 · 模拟农场 25 1.25（PC）

**下载：**[GitHub 发布页](https://github.com/martin-lzh/farming-simulator-25-mods/releases?q=fill-type-selector&expanded=true)（在 **Assets** 下载 `FS25_FillTypeSelector.zip`）

像在播种机上选择种子一样，为空的撒肥机、喷雾机或石灰撒布机选择要施用的类型。不必再为了让 AI 帮手撒对东西，先往料箱里装一点石灰或肥料。

### 使用方法

1. 坐进挂着空撒肥机或喷雾机的拖拉机。
2. 按 **Y** 在机具能施用的类型之间切换，**Shift+Y** 反向切换。帮助（F1）中会显示例如“选择肥料（石灰）”，空料箱上会显示你的选择。
3. 如果机具或组合已经使用 Y（例如可选多种种子的播种机、精准农业，或 Pumps n' Hoses 的工具架和软管卷盘），按键改为 **Alt+Y**。可在“设置 → 控制”中“肥料选择”一栏修改。

只能装一种类型的机具不会出现此按键。同时挂着两台可选择的机具时，按键作用于当前选中的那台。

### AI 帮手与自动购买

- 在“设置 → 游戏设置”中开启“AI 帮手补充 - 肥料”。料箱为空时，帮手会按游戏通常的补充价格购买你选择的类型，包括石灰和除草剂。
- 关闭该设置时，与原版相同，料箱空了帮手就会停止。
- 帮手按游戏对所选类型的田地规则工作，例如跳过已经撒过石灰的地块。
- 只能装石灰的撒布机不需要按键，帮手会直接为它购买石灰。
- 也能撒石灰的粪肥撒布机：石灰按“AI 帮手补充 - 肥料”购买，粪肥按“AI 帮手补充 - 粪肥”购买。
- 没有做选择时，一切与原版相同：喷雾机购买液态肥料，撒肥机购买固态肥料。

### 注意事项

- 料箱里有东西时按实际内容施用，选择被锁定，按键隐藏；料箱再次清空后，你的选择重新生效。
- 与原版相同，连接的储箱（例如前置料箱）里有内容时优先使用它，而不是你的选择。
- 只能选择机具本身能施撒的类型：固态肥料、液态肥料、石灰、除草剂或粪肥。只是料箱能装石灰的拖车（例如带粪肥撒布装置的通用拖车）只提供粪肥。
- 安装 Pumps n' Hoses 扩展包时：粪肥撒布机还可以选择分离粪肥。“AI 帮手补充 - 粪肥”设为购买时帮手会购买它；选择粪堆作为来源时改用粪肥。通过软管供料的拖管施肥机没有可选项。
- 能装粪浆和沼渣的罐车：可以选择帮手使用哪一种。按“AI 帮手补充 - 粪浆”的设置购买所选类型，或先从你的粪池调取所选类型，用完后再用另一种。不做选择时和原来一样使用粪浆。
- 带有单独石灰配置的撒肥机，选择石灰后会切换到该配置，帮手使用与装着石灰时相同的作业宽度。

### 多人游戏

- 所有玩家需要安装同一版本。
- 所属农场可以使用该车辆的玩家，可在料箱为空且没有 AI 帮手使用该机具时修改选择。选择会同步、随车辆保存，之后加入的玩家也会收到。
- 两位玩家同时修改时，以服务器最后收到的修改为准，所有人一致。
- 购买费用只由服务器结算，不会重复扣款。

### 安装与更新

把 `FS25_FillTypeSelector.zip` 放进 `文档\My Games\FarmingSimulator2025\mods`，载入存档时勾选本 Mod。更新时用新 ZIP 替换旧 ZIP，原有选择保留。

### 卸载

删除 ZIP 即可。车辆中的物料不变，保存的选择不再使用。

### 许可

PolyForm Noncommercial 1.0.0 许可，见 [LICENSE](LICENSE)。可免费用于非商业用途，不允许商用。
