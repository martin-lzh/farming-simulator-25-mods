# 动物产品分配

为已有畜舍的牛奶、山羊奶、鸡蛋、羊毛等产品分别选择储存、出售或分配。识别游戏原生 milk / pallets specialization 声明的产品，不硬编码品种。

版本：0.1.4.0（测试版）。面向 PC 版 FS25 1.24.0.0，modDesc 114。0.1.2.0 核心逻辑已于 2026-10-18 经用户实测确认通过；0.1.3.1 单弹窗显示和修改也经用户实测确认通过；0.1.3.3 按实际动物筛选产品，用户试用反馈正常。0.1.4.0 补齐全部 27 种游戏语言，各语言的游戏内显示待复测。

## 操作

打开游戏菜单的“动物”页面，选择畜舍，点击“产品去向”，在同一个弹窗中为每种产品选择挡位，统一确认。产品较多时可滚动；确认只提交改动项。挡位名称使用原生生产链翻译，跟随游戏语言。取消不修改设置。拥有该畜舍的农场成员需具备动物交易权限；设置按畜舍和产品保存，新玩家加入时同步。

同农场的多位经理可以操作。两人修改同一产品时，以服务器最后接受的设置为准；不同产品分别保存。已打开的弹窗保留本地草稿，查看另一位经理的修改需重新打开；未编辑的行不会覆盖他人的设置。出售和分配只在服务器结算。联机模拟已通过，真实双机验收仍待执行。

产品列表跟随该畜舍实际动物的原生活动产品：只养山羊显示山羊奶，只养绵羊显示羊毛；幼龄或暂时零产量也能设置。动物改变后重新打开弹窗刷新，无当前产出类型时不显示入口。隐藏产品的旧挡位仍保存，遗留库存按原挡位处理；再次饲养对应动物时可继续编辑。未提供原生活动产品字段的第三方畜舍回退到其支持列表。

| 挡位 | 行为 |
| --- | --- |
| 储存（默认） | 保留游戏原生储罐及托盘生成行为 |
| 出售 | 每游戏小时处理一次，按原生经济价格乘自动出售系数结算；当前原生系数为 90% |
| 分配 | 每游戏小时送往同一农场接收该产品的生产点，按空余容量比例分配并计收原生按距离运费 |

没有接收设施或容量不足时，未分配产品留在畜舍。接收设施是否启用生产不影响其接收库存，与原生生产点分配方式一致。不会送往其他农场。

液体处理畜舍本身储罐的库存；不抽取连接到畜舍的其他外部仓储。托盘类产品处理待生成的产出，不收集地上、拖车上或其他已经生成的托盘。挡位更改时已经请求生成的托盘可能仍出现空托盘，其回调不会消耗已经交给分配逻辑的库存。恢复储存会重新触发原生托盘生成；积压较多时可能因场地或托盘上限而等待。

设置默认储存，畜舍转移所有权后重置为储存，并由服务端恢复积压托盘的生成。已有生产能力、动物健康、饲料需求及产量计算不变。储罐的原生容量限制仍生效；分配不会赋予牛奶无限容量。未生成托盘的产量沿用原生 pendingLiters 缓冲和存档。

## 构建与安装

从仓库根目录执行：

```powershell
uv run animal-product-distribution-mod/tests/run.py
python animal-product-distribution-mod/tools/build.py
```

输出为 `outputs/FS25_AnimalProductDistribution.zip`。手动把 ZIP 放进游戏 mods 目录，在载入存档时勾选。构建不安装、不修改存档，也不启动游戏。

ZIP 只包含原创脚本、描述文件和图标；不包含游戏反编译文件、第三方代码、测试依赖或分析材料。多人使用时所有参与者需要同一版本。

## 验收边界

用户已确认 0.1.2.0 核心逻辑实测通过。0.1.3.1 单弹窗显示和修改已实测通过；存档回读、联机客户端及第三方组合的逐项测试记录尚未提供。第三方畜舍若替换了原生库存/托盘流程，需单独测试；控制同一产出的其他自动售卖/分配 Mod 也需单独确认兼容性。本版本不处理粪肥、粪浆、动物交易或 DLC 私有输出体系。

手动验收步骤见 DEVELOPMENT.md。卸载前切回储存，让需要的托盘生成并保存。正常库存使用原生保存字段；若日志出现 retained ... liters ... for recovery，表示仓库拒绝退回的产品暂存在 Mod 的恢复记录中。此时应保持 Mod 启用，排除仓库问题并让游戏小时结算完成返还后再卸载，否则这些恢复记录无法由原生游戏读取。

## English

Animal Products Manager: in the Animals menu, select a husbandry, choose Product destinations, then set Storing, Selling or Distributing for each product in one dialog and confirm once. Only edited rows are submitted. Routing runs hourly on the server. Distribution supplies same-farm production points by available capacity and uses native delivery costs. Existing pallets are left alone. Default mode is Storing. The user confirmed core behavior in 0.1.2.0 on 2026-10-18 and the dialog in 0.1.3.1. Version 0.1.3.3 filters dialog products using the selected barn's native active animal outputs. Inactive products retain saved modes and leftover-stock handling. Version 0.1.4.0 (beta) adds names, descriptions, menu labels and help text for all 27 game languages; in-game checks of each language are pending.
