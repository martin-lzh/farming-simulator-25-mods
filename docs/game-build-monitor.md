# Steam game build monitoring / Steam 游戏构建监测

[English](#english) · [中文](#中文)

## English

The [Steam game build monitor](../.github/workflows/game-build-monitor.yml) checks **Farming Simulator 25**, Steam App ID **2300320**, using Valve's anonymous SteamCMD metadata service. It reads `depots.branches.public.buildid` without downloading, updating or launching the game.

Farming Simulator 25 is also sold outside Steam (GIANTS eShop, Epic Games Store). Those builds usually follow the same patch, but the Steam Build ID is only a signal that a game update arrived; it is not a version number and does not prove that the Mods still work.

### Schedule and notifications

Checks run on the default `main` branch every six hours: **00:07, 06:07, 12:07 and 18:07 UTC**. You can also run the workflow from [GitHub Actions](https://github.com/martin-lzh/farming-simulator-25-mods/actions/workflows/game-build-monitor.yml). Pushes to `dev` that touch the monitor's files perform a live read-only check; only this repository's `main` workflow can create notifications.

A changed Build ID creates a bilingual compatibility-check Issue with the previous and current builds, branch-update timestamps, the official Steam news link and a checklist: record the displayed game version, re-extract the game scripts and SDK references into `work/`, diff the GIANTS Lua functions, specializations, events and XML each Mod uses, check `modDesc.xml` descVersion, then run the offline tests and in-game checks. A rollback also counts as a change. Unchanged builds and timestamp-only changes produce no Issue.

The latest monitor Issue created by `github-actions[bot]` is the persistent record, including closed Issues. Keep its hidden metadata when editing or closing it; that avoids repeat alerts without repository write access or an expiring Actions cache. Deleting monitor Issues removes detection history. An interrupted Issue creation is recovered from that history on the next successful run.

One concurrency group serializes scheduled, manual and branch runs. Invalid Steam data, a failed anonymous login, query timeouts and failed GitHub history reads fail the workflow without advancing the recorded build. A run sees only the build available at query time; it cannot reconstruct brief changes between checks.

### Initial baseline

The committed [baseline](../tools/game-build-baseline.json) was queried directly from Valve on **2026-10-27**:

| Field | Value |
| --- | --- |
| Game | Farming Simulator 25 |
| Steam App ID | `2300320` |
| Branch | `public` |
| Build ID | `25879111` |
| Branch updated | `2026-10-20 12:01:22 UTC` |

The local game log of 2026-10-20 matched this build to game version 1.25.0.0 (see [Animal Products Manager's development notes](../animal-products-manager-mod/DEVELOPMENT.md)). With no monitor history, the workflow compares against this baseline rather than accepting whichever build exists on the first run. When a new build appears, check the Mods as described in [Development](../DEVELOPMENT.md) and each Mod's `DEVELOPMENT.md`. The monitor only opens Issues; it never changes Mods, packages or releases.

### Permissions and local checks

No Steam account, Steam API key or additional GitHub secret is needed. The workflow uses the automatically provided `GITHUB_TOKEN` with `contents: read` and `issues: write`. SteamCMD comes from Valve's HTTPS installer endpoint, and its Valve Authenticode signature is checked before it runs. Raw metadata, logs and SteamCMD itself belong only in the ignored `work/` folder.

After installing and initializing SteamCMD in `work/tools/steamcmd/`, a local read-only check is:

```powershell
./work/tools/steamcmd/steamcmd.exe +login anonymous +app_info_update 1 +app_info_print 2300320 +quit
python tools/game_build_monitor.py --steamcmd work/tools/steamcmd/steamcmd.exe
python -m unittest discover -s tools/tests -p test_game_build_monitor.py -v
```

Without `--repository`, the command compares with the committed baseline only. Supplying `--repository martin-lzh/farming-simulator-25-mods` and the `GH_TOKEN` environment variable also reads the bot's Issue history. `--notify` is restricted to this repository's `main` GitHub Actions environment. Never put a token in command arguments or tracked files.

GitHub notifications depend on your repository watch settings and Actions notification preferences. Scheduled runs may be delayed, and GitHub disables schedules in public repositories after 60 days without activity; re-enable the workflow in Actions if that happens.

### Sources

- [Farming Simulator 25 on Steam](https://store.steampowered.com/app/2300320/Farming_Simulator_25/)
- [Valve SteamCMD documentation](https://developer.valvesoftware.com/wiki/SteamCMD)
- [GitHub scheduled workflow rules](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
- The same monitor runs in [old-market-simulator-mods](https://github.com/martin-lzh/old-market-simulator-mods) and [parisian-bistro-simulator-mods](https://github.com/martin-lzh/parisian-bistro-simulator-mods); this copy is adapted for Farming Simulator 25 and GIANTS Lua compatibility checks.

## 中文

[Steam 游戏构建监测](../.github/workflows/game-build-monitor.yml)使用 Valve SteamCMD 匿名查询 **Farming Simulator 25**（Steam App ID **2300320**）的 `depots.branches.public.buildid`。不下载、不更新、不启动游戏。

Farming Simulator 25 也在 Steam 之外销售（GIANTS 商店、Epic Games Store）。这些版本通常同步更新，但 Steam Build ID 只是“游戏有更新”的信号：它不是游戏版本号，也不能证明 Mod 仍然兼容。

### 运行时间与通知

工作流在默认分支 `main` 上每六小时运行一次：**UTC 00:07、06:07、12:07、18:07**，也可在 [GitHub Actions](https://github.com/martin-lzh/farming-simulator-25-mods/actions/workflows/game-build-monitor.yml) 手动运行。推送到 `dev` 且改动了监测相关文件时，执行一次真实的只读查询；只有本仓库 `main` 上的工作流会创建通知。

Build ID 变化时创建一个中英双语的兼容性检查 Issue，列出前后构建、分支更新时间、Steam 官方新闻链接和检查清单：记录游戏显示的版本；把游戏脚本和 SDK 参考重新提取到 `work/`；比较各 Mod 使用的 GIANTS Lua 函数、specialization、事件和 XML；核对 `modDesc.xml` 的 descVersion；再运行离线测试并完成实机检查。回滚也算变化。构建未变或只有时间戳变化时不创建 Issue。

`github-actions[bot]` 创建的最新一条监测 Issue（包括已关闭的）就是持久记录。编辑或关闭时保留其中的隐藏元数据，这样既不会重复提醒，也不需要仓库写权限或会过期的 Actions 缓存。删除监测 Issue 会丢失检测历史。Issue 创建中断时，下一次成功运行会从历史中恢复。

定时、手动和分支运行共用一个串行并发组。Steam 数据无效、匿名登录失败、查询超时或读取 GitHub 历史失败时，工作流失败，不会推进记录的构建。每次运行只能看到查询时的构建，无法还原两次检查之间发生又恢复的短暂切换。

### 初始基线

提交的[基线](../tools/game-build-baseline.json)于 **2026-10-27** 直接从 Valve 查询：

| 字段 | 值 |
| --- | --- |
| 游戏 | Farming Simulator 25 |
| Steam App ID | `2300320` |
| 分支 | `public` |
| Build ID | `25879111` |
| 分支更新时间 | `2026-10-20 12:01:22 UTC` |

2026-10-20 的本机游戏日志确认该构建对应游戏版本 1.25.0.0（见 [Animal Products Manager 开发说明](../animal-products-manager-mod/DEVELOPMENT.md)）。没有监测历史时，工作流与此基线比较，而不是把第一次运行时的构建直接当作基准。出现新构建时，按[开发说明](../DEVELOPMENT.md)和各 Mod 的 `DEVELOPMENT.md` 检查 Mod。监测只创建 Issue，从不修改 Mod、安装包或发布。

### 权限与本地检查

不需要 Steam 账号、Steam API Key 或额外的 GitHub Secret。工作流使用自动提供的 `GITHUB_TOKEN`，权限为 `contents: read` 和 `issues: write`。SteamCMD 来自 Valve 的 HTTPS 安装地址，运行前验证 Valve 的 Authenticode 签名。原始元数据、日志和 SteamCMD 本身只放在被忽略的 `work/` 文件夹。

在 `work/tools/steamcmd/` 安装并初始化 SteamCMD 后，本地只读检查命令：

```powershell
./work/tools/steamcmd/steamcmd.exe +login anonymous +app_info_update 1 +app_info_print 2300320 +quit
python tools/game_build_monitor.py --steamcmd work/tools/steamcmd/steamcmd.exe
python -m unittest discover -s tools/tests -p test_game_build_monitor.py -v
```

不加 `--repository` 时只与提交的基线比较。加上 `--repository martin-lzh/farming-simulator-25-mods` 并设置环境变量 `GH_TOKEN` 时，还会读取机器人的 Issue 历史。`--notify` 只能在本仓库 `main` 分支的 GitHub Actions 环境中使用。不要把令牌写进命令参数或已跟踪的文件。

GitHub 通知取决于仓库的 Watch 设置和 Actions 通知偏好。定时任务可能延迟；公开仓库连续 60 天没有活动时，GitHub 会停用定时任务，届时在 Actions 页面重新启用。

### 参考

- [Steam 上的 Farming Simulator 25](https://store.steampowered.com/app/2300320/Farming_Simulator_25/)
- [Valve SteamCMD 文档](https://developer.valvesoftware.com/wiki/SteamCMD)
- [GitHub 定时工作流规则](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
- [old-market-simulator-mods](https://github.com/martin-lzh/old-market-simulator-mods) 和 [parisian-bistro-simulator-mods](https://github.com/martin-lzh/parisian-bistro-simulator-mods) 运行同样的监测；本仓库的版本针对 Farming Simulator 25 和 GIANTS Lua 兼容性检查做了调整。
