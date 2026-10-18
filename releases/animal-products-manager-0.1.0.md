# 动物产品分配 0.1.0.0

日期：2026-10-17。目标：PC FS25 1.24.0.0 / modDesc 114。

动物页面 → 选择畜舍 → 产品去向 → 选择产品 → 储存、出售或分配。

实现按游戏小时自动出售或向本农场生产点分配，支持奶类和未生成托盘的动物产出。默认储存，既有托盘不自动回收。包含模式存档、多人加入同步、权限验证和所有权变更重置。

离线验证：24 项原创 Lua 行为测试通过，4 个运行时 Lua 文件通过 Luau 编译语法检查，XML 引用及 6 文件 ZIP 白名单检查通过。测试覆盖注册代理、重复加载和禁用后的菜单行为。

构建：`python animal-products-manager-mod/tools/build.py`。
产物：`outputs/FS25_AnimalProductsManager.zip`（不纳入 Git）。

未执行游戏内、联机或专用服务器验收；未安装 Mod、修改存档或操作游戏进程。手动验收步骤见 `animal-products-manager-mod/DEVELOPMENT.md`。此版本供验收，不表示已验证所有原生和第三方畜舍的运行兼容性。
