# Development / 开发说明

[English](#english) · [中文](#中文)

## English

Each implemented Mod lives in its own `<feature>-mod/` folder with GIANTS Engine Lua source, `modDesc.xml`, `release.json`, README, DEVELOPMENT and CHANGELOG. Read [Contributing](CONTRIBUTING.md#english), [AGENTS.md](AGENTS.md) and the target Mod's development guide before editing. Do not create placeholder Mods or temporary worktrees.

### Setup and boundaries

- Use Python and [uv](https://docs.astral.sh/uv/getting-started/installation/) for development tools. Test runners declare their dependencies; `uv run <mod>-mod/tests/run.py` resolves them. Players need neither development tools nor a loader.
- Verify game APIs and XML against the official GIANTS SDK and local references for the target version. Keep game files, third-party tools, extraction scripts, analysis and logs in ignored `work/`; never force-add ignored material.
- Builds write to ignored `outputs/`. Each Mod's `tools/build.py` selects package contents by allowlist. Preserve original runtime assets; never package game content, SDK references or local settings.
- The game installation is read-only. Builds do not install Mods, change saves, or start or stop the game. On an explicit installation request, with the game closed, copy only that Mod's package into the mods folder and report the replaced files and SHA256.
- Use uv for Python and npm for frontend dependencies, if any. New runtime text covers all 27 supported game languages; reuse native translations where appropriate.

### Checks and builds

Run from the repository root:

```powershell
python tools/check_repository.py
python tools/check_syntax.py
python tools/ci.py validate
python -m unittest discover -s tools/tests -v
python tools/ci.py build
uv run animal-products-manager-mod/tests/run.py
uv run fill-type-selector-mod/tests/run.py
uv run map-helper-mod/tests/run.py
uv run production-overflow-mod/tests/run.py
```

For documentation-only changes, check instructions, links and whitespace, plus repository and metadata validation. For tooling or packaging changes, run relevant tool tests and the build. For behavior changes, run the affected Mod's tests and record separate in-game checks. Offline behavior tests and multiplayer simulations are not real game sessions.

### Versions and releases

Keep the four-part version in `modDesc.xml` unless the maintainer requests a release. Record Mod changes under `Unreleased`, pairing each English CHANGELOG line with its Chinese line. Commit and push to `dev`; open a `dev` → `main` PR only when requested. Only the maintainer merges: new numbered versions reaching `main` publish automatically. See [Releases](releases/README.md).

The [Steam build monitor](docs/game-build-monitor.md) checks the public Steam Build ID every six hours and opens compatibility issues from `main`. Steam is one store: its build change is an update signal, not a display version or proof of compatibility with GIANTS or Epic builds.

### License history

On 2026-10-18 the maintainer chose PolyForm Noncommercial License 1.0.0 for future releases of this project's original code. Animal Products Manager 1.0.0.0 and 1.0.0.1 retain MIT; versions from 1.0.0.2 use PolyForm. Fill Type Selector, Map Helper and Production Overflow use PolyForm from their first 1.0.0.0 release. Root and per-Mod LICENSE files retain the required copyright notice and unmodified license text. Third-party material keeps its own terms; game assets and gameplay screenshots are not relicensed by the software license.

## 中文

- 每个功能独立放在 <feature>-mod/，包含实际源码、README.md、DEVELOPMENT.md 和 CHANGELOG.md；按需要加入 assets/、tests/ 和构建入口。
- 尚未确定功能，不创建占位插件或无效构建脚本。
- 实现前核对 Farming Simulator 25 对应版本的开发资料与本机参考，记录已验证的接口与版本；不沿用其他游戏的加载器、SDK 或引擎接口。
- 游戏文件、第三方工具、提取脚本、分析笔记和日志仅放在 work/。
- 构建产物放入 outputs/，安装包只包含原创内容及允许分发的依赖。
- 游戏安装目录只读；构建不自动安装 Mod、不修改存档、不启动或关闭游戏。维护者明确要求时，代理可在游戏关闭后把指定构建复制到 mods 目录，只替换同一 Mod 的旧文件，并报告替换内容和 SHA256。
- Python 依赖优先使用 uv，前端依赖使用 npm。
- 离线检查与游戏内验收分别记录。
- 官方游戏更新：[Steam 构建监测](docs/game-build-monitor.md)每六小时匿名查询 Steam 正式分支的 Build ID，变化时在 `main` 上创建兼容性检查 Issue。游戏也在 GIANTS 商店和 Epic 销售，Steam 构建变化只是更新信号，不代表版本号或兼容性。
- 确定远程仓库后再配置 Git 同步；不得将本项目推送到其他游戏的仓库。

### 环境与检查

开发工具需要 Python 和 [uv](https://docs.astral.sh/uv/getting-started/installation/)，测试入口会声明并解析依赖。玩家不需要开发工具或加载器。新增运行时文案覆盖游戏支持的 27 种语言，原生术语优先复用游戏译文。修改前阅读[参与贡献](CONTRIBUTING.md#中文)、[AGENTS.md](AGENTS.md)及目标 Mod 开发说明；使用现有工作目录，不建立临时工作树。

从仓库根目录运行：

```powershell
python tools/check_repository.py
python tools/check_syntax.py
python tools/ci.py validate
python -m unittest discover -s tools/tests -v
python tools/ci.py build
uv run animal-products-manager-mod/tests/run.py
uv run fill-type-selector-mod/tests/run.py
uv run map-helper-mod/tests/run.py
uv run production-overflow-mod/tests/run.py
```

仅文档变化核对步骤、链接、空白以及仓库和元数据校验；工具或打包变化运行相关工具测试及构建；行为变化运行对应 Mod 测试，并另记实际游戏验收。离线行为测试和联机模拟不等于实机测试。

### 版本与发布

维护者未要求新版本时，保留 `modDesc.xml` 四段版本号，把 Mod 改动放在 `Unreleased`，每行英文后紧跟对应中文。任务结束提交并推送 `dev`，只在要求时打开 `dev` → `main` PR，由维护者合并；新编号版本进入 `main` 自动发布。完整流程见[发布说明](releases/README.md)。

### 许可

2026-10-18：维护者决定把本仓库自己的代码从 MIT 改为 PolyForm Noncommercial License 1.0.0（可免费用于非商业用途，不允许商用），从下一个版本起生效；已发布的 1.0.0.0 和 1.0.0.1 仍为 MIT。`LICENSE` 第一行是 PolyForm 要求的 `Required Notice:` 版权行，其后是 polyformproject/polyform-licenses 1.0.0 标签下的原文，不改写。GitHub 不会把它识别为标准开源许可，会显示为 Other。第三方文件保留各自的许可。

上述 MIT 历史版本指动物产品管理，1.0.0.2 起使用 PolyForm；肥料选择、地图助手和生产余量处理从首个正式版 1.0.0.0 起使用 PolyForm。软件许可不重新授权游戏资源或实机截图。
