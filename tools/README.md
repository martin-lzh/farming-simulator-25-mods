# tools

## English

- `ci.py`: validates versions, runs each Mod's Lua tests, builds the CI packages, shows the release plan and publishes (`validate`, `build`, `release-plan`, `publish`).
- `modrelease.py`: release planning and publishing shared verbatim with the other Mod repositories; change it in all three.
- `check_repository.py` and `check_syntax.py`: keep local-only material out of git and check tracked Python, JSON and XML.
- `tests/`: tests for the tools above.

## 中文

- `ci.py`：校验版本、运行各 Mod 的 Lua 测试、构建 CI 安装包、显示发布计划并发布（`validate`、`build`、`release-plan`、`publish`）。
- `modrelease.py`：与其他 Mod 仓库完全相同的发布逻辑，修改时三个仓库一起改。
- `check_repository.py` 和 `check_syntax.py`：防止本地资料进入仓库，并检查已跟踪的 Python、JSON 和 XML。
- `tests/`：上述工具的测试。
