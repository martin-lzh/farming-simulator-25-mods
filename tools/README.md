# tools

## English

- `ci.py`: validates versions, runs each Mod's Lua tests, builds the CI packages, decides whether a change needs build and test, shows the release plan and publishes (`validate`, `build`, `changes`, `release-plan`, `publish`). `NON_CORE` lists the files that never affect a package or test.
- `changes.py`: classifies the files a pull request or push changed for CI; shared verbatim with the other Mod repositories, change it in all three.
- `modrelease.py`: release planning and publishing shared verbatim with the other Mod repositories; change it in all three.
- `check_repository.py` and `check_syntax.py`: keep local-only material out of git and check tracked Python, JSON and XML.
- `gui_lab/`: GUI preview lab; renders GIANTS GUI XML plus a scenario (screen size, overrides, injected Mod XML) to a static HTML page in `outputs/gui-lab/` for checking layouts without the game (`uv run tools/gui_lab/render.py <scenario.json>`, see `gui_lab/README.md`).
- `tests/`: tests for the tools above.

## 中文

- `ci.py`：校验版本、运行各 Mod 的 Lua 测试、构建 CI 安装包、判断改动是否需要构建和测试、显示发布计划并发布（`validate`、`build`、`changes`、`release-plan`、`publish`）。`NON_CORE` 列出不影响安装包和测试的文件。
- `changes.py`：为 CI 归类拉取请求或推送改动的文件；与其他 Mod 仓库完全相同，修改时三个仓库一起改。
- `modrelease.py`：与其他 Mod 仓库完全相同的发布逻辑，修改时三个仓库一起改。
- `check_repository.py` 和 `check_syntax.py`：防止本地资料进入仓库，并检查已跟踪的 Python、JSON 和 XML。
- `gui_lab/`：GUI 预览工具；把 GIANTS GUI XML 和场景文件（屏幕尺寸、覆盖设置、注入的 Mod XML）渲染成 `outputs/gui-lab/` 下的静态 HTML 页面，无需启动游戏即可检查布局（`uv run tools/gui_lab/render.py <scenario.json>`，见 `gui_lab/README.md`）。
- `tests/`：上述工具的测试。
