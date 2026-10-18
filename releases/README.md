# Releases

Each Mod is versioned and released on its own, with tags named `<mod>-v<version>` (for example `animal-products-manager-v0.1.3.3`). Pull requests into `main` exist to ship new versions: merging one is the maintainer's approval, and CI then publishes automatically. The same flow and the same release code run in the sibling repositories [old-market-simulator-mods](https://github.com/martin-lzh/old-market-simulator-mods) and [parisian-bistro-simulator-mods](https://github.com/martin-lzh/parisian-bistro-simulator-mods).

## How a version ships

1. **Work on `dev`.** Changes are recorded under `Unreleased` in the Mod's `CHANGELOG.md`; the `modDesc.xml` version stays as it is.
2. **Test in game.** Before any release, beta included, the maintainer tests the build in game. Test builds are identified by commit and SHA256.
3. **Prepare the version** (only on the maintainer's instruction). Update `<version>` in `modDesc.xml`, the Mod README and the root README; move `Unreleased` into `## X.Y.Z.W — YYYY-MM-DD`; set `prerelease` in `release.json`.
4. **Open a PR from `dev` to `main`.** CI checks repository boundaries and syntax, runs the Lua behavior tests and multiplayer simulations, builds `FS25_<Name>.zip` and shows a **Release plan** table in the build job summary.
5. **The maintainer merges.** The release job publishes every new version and promotes betas, using the packages built and verified in the same run.

## Betas and stable releases

`"prerelease": true` in a Mod's `release.json` publishes the version as a GitHub pre-release: a closed beta for a few early testers. When it's ready for everyone, set `"prerelease": false` without changing the version and merge again; CI turns the existing release into a stable one without re-uploading anything. A stable release is never turned back into a beta.

## The release plan

| Result | Meaning |
| --- | --- |
| publish | New numbered version: it is released when the PR is merged. |
| promote | Existing beta whose `release.json` now says stable. |
| current | Already released; nothing to do. |
| waiting | Already released; its `Unreleased` changes ship with the next version. |
| error | Something must be fixed before merging. CI fails. |

Errors include: a version not newer than the latest release; a new version while `Unreleased` still has entries; no CHANGELOG entry for the version; a status note in the version heading; a tag without a release; `release.json` asking for a beta when the release is already stable.

## What the release job guarantees

- It publishes the `FS25_<Name>.zip` built in the same CI run, after checking that its `modDesc.xml` version and build evidence match the merged commit.
- It creates a draft, uploads the ZIP and `SHA256SUMS.txt`, downloads them again to compare the bytes, then publishes and checks that the tag points at the merged commit.
- Published files and tags are never replaced or moved. A broken release is fixed with a new patch version. Documentation-only changes wait for the next version.
- After an interrupted run, rerun the failed jobs. A leftover draft is only reused when it belongs to the same commit and notes.

The ZIP keeps the name the game expects (`FS25_<Name>.zip`, without a version), so players can replace the file in their `mods` folder directly.

## Commands

```powershell
python tools/ci.py validate
python tools/ci.py build
$env:GH_TOKEN = gh auth token; python tools/ci.py release-plan --repository martin-lzh/farming-simulator-25-mods
```

`release-plan` only reads from GitHub. Publishing runs only in CI on `main`.

## Shared release code

[`tools/modrelease.py`](../tools/modrelease.py) and its tests are identical in all three Mod repositories. Change them in all three together. This repository's `tools/ci.py` builds and checks the packages and describes the Mods to the shared code.

## History

The `animal-products-manager-*.md` files are development notes for versions 0.1.0 to 0.1.3.3, written before automatic releases. Those builds were still named Animal Product Distribution (`FS25_AnimalProductDistribution.zip`); the files and paths were renamed with the Mod before 1.0.0.0. The first GitHub release is published when the first PR into `main` is merged.
