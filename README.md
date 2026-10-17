# Farming Simulator 25 Mods

## 中文

Farming Simulator 25 原创 Mod 开发目录。

- [动物产品分配](animal-product-distribution-mod/README.md)：在动物页面为畜舍产品选择储存、出售或分配；0.1.3.3 按实际动物筛选产品；0.1.2.0 核心逻辑和 0.1.3.1 单弹窗均经用户实测通过。

每项功能使用独立的 `<feature>-mod/` 目录，确定功能后再创建。

| 目录 | 用途 |
| --- | --- |
| assets/ | 原创宣传图和文档图片 |
| docs/ | 设计说明和兼容性记录 |
| tools/ | 实际使用的开发、检查和打包工具 |
| releases/ | 版本说明和验收记录 |
| work/ | 本地游戏参考、第三方工具、分析资料和日志，不提交 |
| outputs/ | 构建产物和安装包，不提交 |

开发约定见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## English

Workspace for original Farming Simulator 25 Mods. [Animal Product Distribution](animal-product-distribution-mod/README.md) adds storing, selling and distribution controls for husbandry outputs; the user has confirmed core behavior in 0.1.2.0; the user has also confirmed the 0.1.3.1 dialog displays and edits correctly.

Create an independent `<feature>-mod/` directory when a feature is defined. Shared folders contain artwork (`assets/`), documentation (`docs/`), development tools (`tools/`) and release records (`releases/`). Local references belong in ignored `work/`; generated packages belong in ignored `outputs/`.
