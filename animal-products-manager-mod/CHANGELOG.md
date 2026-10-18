# Changelog / 版本记录

## Unreleased

## 1.0.0.1 — 2026-10-18

- New Mod icon: a milk can and an egg with arrows to the three destinations, store, sell and distribute.
- 新的 Mod 图标：奶罐和鸡蛋，箭头分别指向储存、出售和分配三种去向。
- The description in the in-game Mods list now explains, in all 27 languages, what each mode does and how to open the dialog (Animals page, **Product destinations**, default key X).
- 游戏内 Mod 列表中的简介改为全部 27 种语言的详细说明，介绍各挡位的作用和打开弹窗的方法（“动物”页面，“产品去向”，默认按键 X）。
- Mod names in other languages now start every word with a capital letter, as in the English name.
- 其他语言的 Mod 名称改为每个单词首字母大写，与英文名称一致。
- If another Mod causes an error while products are sold or delivered, the error now appears in the game log instead of being hidden. Product that wasn't sold or delivered stays with the barn and is handled in the next in-game hour.
- 如果其他 Mod 在出售或分配产品时出错，错误现在会显示在游戏日志中，不再被隐藏。未售出或未送达的产品仍归畜舍，在下一游戏小时继续处理。

## 1.0.0.0 — 2026-10-18

- First release. Choose for each husbandry product, such as milk, goat milk, eggs and wool, whether it is stored, sold automatically every in-game hour, or delivered to your own production points.
- 首个正式版本。为每种畜舍产品（如牛奶、山羊奶、鸡蛋、羊毛）选择继续储存、每游戏小时自动出售，或送往自己农场的生产点。
- Open the Animals page, select a husbandry and click **Product destinations** to set all of its products in one dialog.
- 在“动物”页面选择畜舍，点击“产品去向”，在一个弹窗中设置该畜舍的全部产品。
- Works in multiplayer: farm members allowed to trade animals can change the settings, and the server handles sales and deliveries once per hour.
- 支持多人游戏：有动物交易权限的农场成员可以修改设置，出售和分配由服务器每小时统一处理。
- Available in all 27 game languages.
- 支持全部 27 种游戏语言。
- The Mod file is now `FS25_AnimalProductsManager.zip`. If you played a test version, delete the old `FS25_AnimalProductDistribution.zip` from your mods folder, add the new file and set your product destinations again; settings from test versions don't carry over.
- Mod 文件改名为 `FS25_AnimalProductsManager.zip`。如果玩过测试版，请从 mods 目录删除旧的 `FS25_AnimalProductDistribution.zip`，放入新文件后重新设置产品去向；测试版的设置不会保留。

## 0.1.4.0 — 2026-10-18

- Adds localized Mod names, descriptions, menu labels and help text for all 27 game languages and regional variants, including Traditional Chinese, French, Spanish, Japanese and Korean.
- 补齐全部 27 种游戏语言及地区变体的 Mod 名称、简介、菜单入口和说明文字，包括繁体中文、法语、西班牙语、日语和韩语等。
- The Mod is renamed Animal Products Manager in every game language. Saved settings carry over; just replace the old ZIP with the new one.
- Mod 在所有游戏语言中更名，中文名为“动物产品管理”。原有设置保留，直接用新 ZIP 替换旧 ZIP 即可。

## 0.1.3.3 — 2026-10-18

- Product destinations follow the husbandry's native `activeFillTypes`: with only goats, the wool slot reserved in the husbandry configuration no longer appears; sheep and milk subtypes likewise follow the animals actually kept.
- 产品去向按当前畜舍原生 `activeFillTypes` 筛选；只养山羊时不再显示畜舍配置中预留的羊毛，绵羊与奶类子类型同样按实际动物显示。
- The entry is hidden when the husbandry currently has no animal outputs; third-party husbandries without an active-products field keep the compatible fallback. Young animals or temporarily zero output don't stop you from presetting a product.
- 无当前动物产出时隐藏入口；第三方畜舍未提供活动产品字段时保留兼容回退。幼龄或暂时零产量不影响预先设置对应产品。
- The full supported list is still used for saving modes, join synchronization and settling leftover stock; hidden rows don't delete old settings or restored quantities.
- 完整支持列表继续用于模式保存、加入同步和遗留库存结算；隐藏行不删除旧设置或恢复数量。
- Added 7 behavior regressions and 1 multi-husbandry multiplayer simulation; 60 behavior tests and 10 multiplayer simulations pass. The in-game interface still needs a retest.
- 新增 7 项行为回归和 1 组多畜舍联机模拟；60 项行为测试、10 组联机模拟通过。真实游戏界面待复测。

## 0.1.3.2 — 2026-10-18

- The icon now uses a BC1/DXT1 DDS with full mipmaps, avoiding the performance warnings for an uncompressed PNG and CPU-generated mipmaps at runtime.
- 图标改用 BC1/DXT1 DDS，包含完整 mipmap，避免未压缩 PNG 和运行时 CPU 生成 mipmap 的性能警告。
- The PNG moved to the source-art folder and is no longer packaged; the build checks the DDS format and mipmap data.
- PNG 移到制作素材目录，不再打包；构建时验证 DDS 格式和 mipmap 数据。
- The user confirmed that the 0.1.3.1 single dialog displays and edits correctly. This version doesn't change the interface scripts or core logic.
- 用户已确认 0.1.3.1 单弹窗显示和修改正常。本次不修改界面脚本及核心逻辑。

## 0.1.3.1 — 2026-10-18

- Fixed product rows keeping the template width, which clipped the right-hand mode arrows inside the scroll area.
- 修复产品行沿用模板宽度，导致右侧挡位箭头被滚动区域裁切的问题。
- The dialog height follows the number of products and the actual height of the description text, showing up to four rows; more products scroll.
- 弹窗高度按产品数量和说明文字实际高度调整，最多显示四行，更多产品滚动查看。
- Added layout-bounds and repeated-open height regressions; 53 tests pass. The in-game layout still needs a retest.
- 增加布局边界及重复打开的高度回归，53 项测试通过；实际游戏布局待复测。

## 0.1.3.0 — 2026-10-18

- Product destinations moved into a single dialog with one row per product, using native selector controls and the production-chain mode translations.
- 产品去向改为单个弹窗，每种产品一行，使用原生选择控件及生产链挡位翻译。
- All changes are confirmed together; Back discards the draft, and unchanged products send no request.
- 所有修改统一确认；返回丢弃草稿，未改动的产品不发送请求。
- Many products scroll; confirming re-checks the husbandry's state, ownership and permissions.
- 产品较多时滚动显示；确认时重新校验畜舍状态、所有权和权限。
- Added 5 interface behavior regressions and updated the existing menu tests; 52 tests pass. In-game testing of the new interface is pending.
- 新增 5 项界面行为回归并更新原有菜单测试，52 项测试通过；新界面游戏内验收待执行。

## 0.1.2.0 — 2026-10-17

- Settlement excludes independent income and expenses picked up by the synced balance listener, such as loan repayments and borrowing, fixing double sales and goods rolled back after freight was paid.
- 结算时剔除同步余额监听器的还贷、借款等独立收支，修复重复出售和已付运费却回滚货物的兼容问题。
- Stock recovery is kept for failures before writing, partial credits and errors after writing; nested notifications and other husbandry/farm settlements are handled.
- 保留写入前失败、部分入账及写入后抛错的库存恢复逻辑；处理嵌套通知及其他畜舍/农场结算。
- After a husbandry changes owner and its modes reset, the server resumes native pallet spawning; this doesn't trigger while loading or on clients.
- 畜舍易主重置挡位后，由服务端恢复原生托盘生成；加载阶段和客户端不触发。
- If the owner changes or the mode switches back to storing during a callback, spawning resumes after the temporary stock hiding is lifted, so the backlog no longer waits for new output.
- 回调中易主或切回储存时，在解除临时库存隐藏后恢复生成，避免积压一直等待新产量。
- The two-level selection interface reuses the native production-chain mode translations; three duplicated custom translations were removed.
- 两级选择界面复用原生生产链挡位翻译，删除三条重复的自定义翻译。
- Added 10 regression tests; 47 behavior tests pass. In-game and multiplayer testing is pending.
- 新增 10 项回归测试，47 项行为测试通过；游戏内及多人验收待执行。

## 0.1.1.0 — 2026-10-17

- Fixed saved modes being cleared when restoring the savegame owner; a notification with the same owner no longer triggers a reset.
- 修复恢复存档所有者时清空已保存挡位的问题，相同所有者通知不再触发重置。
- Settlement uses the native husbandry hourly event and skips stock while loading is unfinished, for deleted husbandries, without a valid farm, or on callback re-entry.
- 改用原生畜舍小时事件结算，阻止加载未完成、已删除、无有效农场及回调重入时处理库存。
- Distribution, sales and fees follow the actual writes and balance changes; unsold quantities are returned on failure or partial completion.
- 按实际写入和余额变化处理分配、出售及费用，失败或部分成交时返还未成交数量。
- When storage refuses returned stock, the restored quantity is kept and saved; old product records are cleared when a savegame is rewritten.
- 仓库拒绝返还时保留并保存恢复数量；清除重写存档中旧的产品记录。
- Duplicate receiving storages and self-delivery are excluded; regression tests cover errors and the full loading order.
- 排除重复接收仓库和自配送；增加异常和完整加载顺序回归测试。
- 37 behavior tests pass; 500 native distribution comparisons and 50 SDK pallet save/reload rounds were checked locally.
- 37 项行为测试通过；本机完成 500 组原生分配对照及 50 轮 SDK 托盘保存/重载核对。
- In-game and multiplayer testing are still pending.
- 游戏内与联机验收仍待执行。

## 0.1.0.0 — 2026-10-17

- The Animals page offers store, sell and distribute settings per husbandry and per product.
- 动物页面提供按畜舍、按产品的储存、出售和分配设置。
- Supports native milk-type stock and animal output that hasn't been spawned as pallets yet.
- 支持原生奶类库存及尚未生成托盘的动物产出。
- Settles on the server every game hour, using the native sales factor and distribution freight.
- 按游戏小时执行服务端结算，沿用原生出售系数和分配运费。
- Adds mode saving, multiplayer join synchronization, server-side permission checks and a reset on ownership change.
- 添加模式保存、多人加入同步、服务端权限检查和所有权变更重置。
- Provides offline behavior tests, an original icon and an allowlisted ZIP build.
- 提供离线行为测试、原创图标与白名单 ZIP 构建。
- Streamlined Chinese, English and German interface hints and Mod description, keeping the fee and pallet notes.
- 精简中、英、德文界面提示及 Mod 描述，保留费用与托盘处理说明。
- Status: offline validation complete; in-game and multiplayer testing pending.
- 状态：离线验证完成，游戏内及多人验收待执行。
