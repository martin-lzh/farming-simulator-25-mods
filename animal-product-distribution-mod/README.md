# 动物产品分配

为已有畜舍的牛奶、山羊奶、鸡蛋、羊毛等产品分别选择储存、出售或分配。识别游戏原生 milk / pallets specialization 声明的产品，不硬编码品种。

版本：0.1.0.0。面向 PC 版 FS25 1.24.0.0，modDesc 114。当前为待游戏内验收版本，已完成离线行为和语法检查。

## 操作

打开游戏菜单的“动物”页面，选择畜舍，点击“产品去向”，选择产品和挡位后确认。取消不修改设置。拥有该畜舍的农场成员需具备动物交易权限；设置按畜舍和产品保存，新玩家加入时同步。

| 挡位 | 行为 |
| --- | --- |
| 储存（默认） | 保留游戏原生储罐及托盘生成行为 |
| 出售 | 每游戏小时处理一次，按原生经济价格乘自动出售系数结算；当前原生系数为 90% |
| 分配 | 每游戏小时送往同一农场接收该产品的生产点，按空余容量比例分配并计收原生按距离运费 |

没有接收设施或容量不足时，未分配产品留在畜舍。接收设施是否启用生产不影响其接收库存，与原生生产点分配方式一致。不会送往其他农场。

液体处理畜舍本身储罐的库存；不抽取连接到畜舍的其他外部仓储。托盘类产品处理待生成的产出，不收集地上、拖车上或其他已经生成的托盘。挡位更改时已经请求生成的托盘可能仍出现空托盘，其回调不会消耗已经交给分配逻辑的库存。恢复储存会重新触发原生托盘生成；积压较多时可能因场地或托盘上限而等待。

设置默认储存，畜舍转移所有权后重置为储存。已有生产能力、动物健康、饲料需求及产量计算不变。储罐的原生容量限制仍生效；分配不会赋予牛奶无限容量。未生成托盘的产量沿用原生 pendingLiters 缓冲和存档。

## 构建与安装

从仓库根目录执行：

```powershell
uv run animal-product-distribution-mod/tests/run.py
python animal-product-distribution-mod/tools/build.py
```

输出为 `outputs/FS25_AnimalProductDistribution.zip`。手动把 ZIP 放进游戏 mods 目录，在载入存档时勾选。构建不安装、不修改存档，也不启动游戏。

ZIP 只包含原创脚本、描述文件和图标；不包含游戏反编译文件、第三方代码、测试依赖或分析材料。多人使用时所有参与者需要同一版本。

## 验收边界

尚未在真实游戏中验证菜单布局、存档回读、多人连接或其他 Mod 兼容性。第三方畜舍若替换了原生库存/托盘流程，需单独测试；控制同一产出的其他自动售卖/分配 Mod 也需单独确认兼容性。本版本不处理粪肥、粪浆、动物交易或 DLC 私有输出体系。

手动验收步骤见 DEVELOPMENT.md。卸载前切回储存，让需要的托盘生成并保存；卸载后挡位数据不再生效，库存仍使用原生保存字段。

## English

In the Animals menu, select a husbandry, choose Product destinations, then select a product and Storing, Selling or Distributing. Routing runs hourly on the server. Distribution supplies same-farm production points by available capacity and uses native delivery costs. Existing pallets are left alone. Default mode is Storing. This version has passed offline checks but still requires in-game acceptance testing.
