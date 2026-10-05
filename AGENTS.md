# AGENTS.md

Yaagl is a macOS launcher for anime games (Genshin, HSR, ZZZ, Honkai, SCZ). It runs the Windows game through a modified Wine with DXMT. The stack is TypeScript, SolidJS and Vite on NeutralinoJS, with native C/ObjC helpers for the Wine side. This repo is the fork `tanzby/yet-another-anime-game-launcher`; the upstream is `yaagl/` (3Shain).

## Workflow: one worktree per change

Every feature, fix or experiment is developed and discussed in its own git worktree and branch, never in the main checkout.

- **Keep the main checkout on `main` and clean.** It is shared by every session and tool working on this repo. Two sessions editing it at once overwrite each other's changes and git state.
- **Put worktrees under `.claude/worktrees/<name>`** (gitignored), so Claude Code and other tools find them in one place. Start each worktree from the latest `origin/main`.
- **Run `scripts/dev/worktree-setup.sh` first in a new worktree.** A worktree only contains tracked files. The script brings in the gitignored build inputs (`bin/`, `neutralino.js`, `pnpm-workspace.yaml`, the decoded `src/clients/secret.ts`, a link to `sophon_server/build`) and runs `pnpm install`. It is idempotent and takes a few seconds.
- **Land changes through a PR.** `main` is protected: changes must go through a PR, and the `tsc` check must pass. PRs are squash-merged. After merging, remove the worktree and its branch.
- **Don't run two game sessions at once.** Worktrees share the installed `/Applications/Yaagl.app`, the data dir `~/Library/Application Support/Yaagl` (Wine runtime, prefix, settings) and the game files. Only one worktree at a time may install the app or run the game or `scripts/dev/yaagl-diag`.
- **Never use bare `git stash` / `git stash pop`.** The stash stack is shared by all worktrees. Prefer a temporary WIP commit.

Plain git (e.g. Codex or a terminal):

```bash
git fetch origin
git worktree add .claude/worktrees/<name> -b <branch> origin/main
cd .claude/worktrees/<name> && scripts/dev/worktree-setup.sh
# after the PR is merged:
git worktree remove .claude/worktrees/<name> && git branch -D <branch>
```

## Commands

- Install deps: `pnpm install`. This also installs the lefthook git hooks: pre-commit runs prettier and eslint `--fix`; pre-push runs tsc, prettier and eslint.
- Checks (same as CI and pre-push): `node_modules/.bin/tsc --noEmit`, `node_modules/.bin/prettier -c ./src`, `node_modules/.bin/eslint ./src --ext .ts --ext .tsx`.
- Tests: `node_modules/.bin/vitest run --threads false`.
- Dev run (CN Genshin): `pnpm start`. Other channels use `pnpm run start-<channel>`.
- Release-style app: `YAAGL_CHANNEL_CLIENT=hk4ecn node build-app.js` produces `Yaagl.app`. It needs `sophon_server/build` (from `./build-sophon.sh`).
- Native helpers: `native/gamehost/build.sh` builds the shipped shim and dylib. `--dev` builds the dev-only companion and `turner.exe`.

Prefer `node_modules/.bin/<tool>` over `pnpm exec <tool>`. pnpm 11 runs a dependency check before `exec` and can fail on unapproved build scripts.

## Architecture

- **One channel per build.** The game channel is picked at build time from `YAAGL_CHANNEL_CLIENT` (`src/clients/<channel>.ts`, re-exported by a Vite plugin). Each channel has its own app name, bundle id and data dir.
- **Game logic** lives in `src/clients/mhy/<game>/` (launch, update, patch) and `src/clients/seasun/`. Genshin is `hk4e`: `program-launch-game.ts`, plus `config/` for its settings.
- **Wine** lives in `src/wine/`:
  - `wine.ts` handles process exec, registry props and `shutdown()` (prefix-scoped cleanup).
  - `wine-install-program.ts` installs and updates the runtime.
  - `game-host.ts` covers the Game Mode identity and the native full-screen helpers.
- **Settings** are in `src/config/` (shared) and `src/clients/mhy/*/config/` (per game). Each setting is a small SolidJS component persisted with `getKey`/`setKey`. Every UI string needs a key in all `src/locale/*.ts` files (typed against `zh_CN`).
- **Utilities** are in `src/utils/`: `exec` and file helpers in `neu.ts`, and shell quoting in `command-builder.ts`. Reuse `cp`, `forceMove`, `fileOrDirExists`, `getKeyOrDefault` and `wait` rather than hand-rolled shell. `build()` escapes newlines, so shell scripts passed through `exec` must be one line.
- **Native helpers** are in `native/gamehost/`. They are x86_64, since Wine runs under Rosetta. The game-host design and measurements are in `docs/genshin-macos.md`.

## Verification

Game behavior is verified with deterministic, time-boxed text output, not screenshots. Always close the game afterwards; `yaagl-diag watch` cleans up the prefix itself.

- `scripts/dev/yaagl-diag watch --launch --timeout 60 --until gamemode` checks Game Mode, full screen and the front app.
- `scripts/dev/yaagl-diag watch --launch --until exit --close-after 40` checks the exit path and any leftover Wine processes.
- `scripts/dev/yaagl-diag watch --launch --autoplay` enters the world and reports frame times and GPU usage while turning the camera.
- `scripts/dev/yaagl-diag ps` / `kill --orphans` inspect or clean up Wine processes.

`--launch` starts the installed `/Applications/Yaagl.app` with `YAAGL_AUTOLAUNCH=1`. So build it and install it first (`build-app.js`, then copy to `/Applications`) to test a change in the real app.

## Fork notes

- **Upstream coupling.** Before shipping a fork release, check for hardcoded upstream references: the updater owner and proxy, the bundle id (`com.3shain.yaagl`), the wine tag list in `src/wine/distro.ts`, and the DXMT version gate.
- **Releases.** Only a tag push (`build-ontag.yaml`) produces packages, as a draft release. The tag must be valid semver. Apps are not codesigned.
