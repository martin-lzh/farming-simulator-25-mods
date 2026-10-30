# Contributing / 参与贡献

[English](#english) · [中文](#中文)

## English

Bug reports, translations, documentation and focused code changes are welcome in English or Chinese. Read the [community guidelines](CODE_OF_CONDUCT.md#english). Gameplay help belongs in [Support](SUPPORT.md#english); vulnerabilities follow [Security](SECURITY.md#english).

1. Read [Development](DEVELOPMENT.md#english), [AGENTS.md](AGENTS.md) and the affected Mod's README, DEVELOPMENT and CHANGELOG. Search existing [issues](https://github.com/martin-lzh/farming-simulator-25-mods/issues) before proposing work.
2. Use an existing development checkout and keep each `<feature>-mod/` independent. Keep game files, SDK references, extraction tools and analysis in ignored `work/`; builds belong in `outputs/`. Game installs and saves are not changed by builds.
3. Keep four-part Mod versions unchanged unless the maintainer requests a release. Record Mod changes under `Unreleased`. Keep player guides bilingual, English first, Chinese second; pair English/Chinese CHANGELOG entries. New runtime wording covers all 27 supported languages.
4. Contributions must be original or have compatible terms and attribution. Keep root and per-Mod licenses consistent with PolyForm Noncommercial 1.0.0; historical releases keep their original license.
5. Run the relevant [checks](DEVELOPMENT.md#checks-and-builds), inspect the staged diff and run `python tools/check_repository.py`. Check documentation links and steps; run tests for changed behavior or tooling. State separately what was checked offline and in game.
6. Keep commits focused. Contributors with access push to `dev`; do not create temporary worktrees or push directly to `main`. Open a `dev` → `main` PR only when the maintainer requests one, describing the problem, result, affected Mods, version status and validation. The maintainer merges. See [Releases](releases/README.md).

## 中文

欢迎用中文或英文提交问题、翻译、文档及针对明确问题的代码改动。请阅读[社区规范](CODE_OF_CONDUCT.md#中文)。游戏使用问题见[帮助](SUPPORT.md#中文)，漏洞按[安全反馈](SECURITY.md#中文)处理。

1. 阅读[开发说明](DEVELOPMENT.md#中文)、[AGENTS.md](AGENTS.md)及目标 Mod 的 README、DEVELOPMENT 和 CHANGELOG。提出工作前先搜索已有 [Issue](https://github.com/martin-lzh/farming-simulator-25-mods/issues)。
2. 使用现有开发目录，各 `<feature>-mod/` 保持独立。游戏文件、SDK 参考、提取工具及分析放在忽略的 `work/`；构建产物放在 `outputs/`。构建不修改游戏安装和存档。
3. 未经维护者要求不改变四段版本号，Mod 变化记入 `Unreleased`。玩家说明中英双语、英文在前中文在后；CHANGELOG 中英条目配对。新增运行时文案覆盖支持的 27 种语言。
4. 贡献须为原创，或具兼容条款并注明出处。根目录与各 Mod 许可保持 PolyForm Noncommercial 1.0.0 一致；历史发行版保留原许可。
5. 执行相关[检查](DEVELOPMENT.md#环境与检查)，审查暂存差异并运行 `python tools/check_repository.py`。文档核对步骤和链接，行为及工具变化运行相应测试；分别说明离线检查与实机结果。
6. 按目的组织提交。有权限的贡献者推送到 `dev`，不创建临时工作树或直接推送 `main`。仅在维护者要求时打开 `dev` → `main` PR，说明问题、结果、受影响 Mod、版本情况和验证；由维护者合并。流程见[发布说明](releases/README.md)。
