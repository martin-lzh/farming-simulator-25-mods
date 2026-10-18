# Agent instructions

Source, build tooling and release automation for the Farming Simulator 25 Mods (GIANTS Engine, Lua, `modDesc.xml`). The sibling repositories `old-market-simulator-mods` and `parisian-bistro-simulator-mods` follow the same rules; when you change a rule here, change it there too.

## Read first

- `README.md` for what players see, `DEVELOPMENT.md` for workspace conventions, and `releases/README.md` for how releases work.
- The target Mod's `README.md`, `CHANGELOG.md`, `DEVELOPMENT.md`, `modDesc.xml` and `release.json`.

## Hard rules

1. **The game install is read-only.** Builds never install Mods, edit saves, or start or stop the game. The maintainer installs builds and does the in-game testing. When the maintainer explicitly asks, the agent may install a build: with the game closed, copy only that Mod's package into the game's Mods folder, replacing only that Mod's old files, then report what it replaced and the SHA256.
2. **No game content in git.** Game files, third-party references, decompiled scripts, extraction tools, analysis notes and logs stay in the ignored `work/` folder; never `git add -f`. Packages contain only original files, chosen by each Mod's `tools/build.py` allowlist.
3. **Check game APIs against the real game.** Verify Farming Simulator 25 functions, specializations, events and XML against the official SDK sources and local references for the target game version; never invent signatures. Don't copy other games' loaders, SDKs or engine APIs; only the folder layout.
4. **Versions change only when the maintainer says so.** Until then, record every change under `Unreleased` in that Mod's `CHANGELOG.md` and keep the `modDesc.xml` version. Identify test builds by commit and SHA256, not by a made-up version.
5. **Merging into `main` publishes.** Every new numbered CHANGELOG version that reaches `main` is released automatically, so only the maintainer merges. Open a PR to `main` only when the maintainer asks, and never merge it.
6. **Commit and push to `dev` at the end of every task.** Run `python tools/check_repository.py`, review `git diff --staged`, and stage only files that belong to the task. Don't create git worktrees: the ignored `work/` references would be missing from them.
7. **Promotional material stays local.** Posters, generated art, copy and exports for Xiaohongshu, Steam or Nexus go in the ignored `outputs/` folder. Tracked Mod assets and README screenshots are not affected.

Each feature gets its own `<feature>-mod/` folder once it is defined; no placeholder Mods or empty build scripts. Use uv for Python dependencies.

## Player-facing text

READMEs, CHANGELOG entries and release notes say what the Mod does and what the player should do. Leave out disclaimers ("not verified", "does not imply") and developer terms (specializations, `pendingLiters`, descVersion, hashes); those belong in `DEVELOPMENT.md` and `releases/`. Bilingual documents put English first, then 中文, each complete; CHANGELOG entries pair each English line with its Chinese line.

## Releasing a Mod

Do this only when the maintainer asks for a specific Mod and version:

1. The maintainer confirms in-game testing of the build being released (single player, host and client when multiplayer is affected). This applies to betas too.
2. Update `<version>` in `modDesc.xml` (four parts, `X.Y.Z.W`), the Mod README version line and the root README Mod list.
3. Move the `Unreleased` entries into `## X.Y.Z.W — YYYY-MM-DD`, written for players, English and 中文 lines paired. Leave the heading at version and date.
4. Set `"prerelease": true` in `release.json` for a closed beta for a few testers, or `false` for a stable release. To turn an existing beta into a stable release later, set it to `false` without changing the version.
5. Run the validation commands, commit, push `dev` and, when asked, open the PR. Fill in the PR template's version table.
6. Before the maintainer merges, tell them what the CI "Release plan" table says: which Mods will publish or be promoted, and which are skipped and why.

## Validation

```powershell
python tools/check_repository.py
python tools/check_syntax.py
python tools/ci.py validate
python -m unittest discover -s tools/tests -v
python tools/ci.py build
uv run <mod>-mod/tests/run.py
```

Report which of these ran and which didn't. Offline tests and multiplayer simulations are not in-game testing.
