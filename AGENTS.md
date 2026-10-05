# AGENTS.md

Yaagl is a macOS launcher for anime games. It runs the Windows game through a modified Wine with DXMT, using TypeScript, SolidJS and Vite on NeutralinoJS, with native helpers in `native/`. This repo is the fork `tanzby/yet-another-anime-game-launcher` of upstream `yaagl/` (3Shain); PRs target this fork's `main`.

## Workflow: one worktree per change

Every feature, fix or experiment is developed and discussed in its own git worktree and branch, never in the main checkout.

- **Keep the main checkout clean.** It stays on `main` and is shared by every session and tool. Concurrent edits there overwrite each other's work and git state.
- **Create worktrees under `.claude/worktrees/<name>`** (gitignored), branched from `origin/main`.
- **Run `scripts/dev/worktree-setup.sh` first.** It is idempotent: it brings in the gitignored build inputs and installs dependencies.
- **Land changes via PR.** `main` is protected: a PR and the `tsc` check are required, and PRs are squash-merged. Remove the worktree and branch after merging.
- **Only one worktree may run the game at a time** (install the app, run the game or `scripts/dev/yaagl-diag`). All worktrees share `/Applications/Yaagl.app`, `~/Library/Application Support/Yaagl` (Wine, prefix, settings) and the game files.
- **The stash stack is shared by all worktrees.** Never use bare `git stash` / `git stash pop`; prefer a WIP commit.

Plain git:

```bash
git worktree add .claude/worktrees/<name> -b <branch> origin/main
git worktree remove .claude/worktrees/<name>   # after merge, then git branch -D <branch>
```

## Commands

- First-time setup of the main checkout: `pnpm install` and `./configure.sh`. `configure.sh` decodes `src/clients/secret.ts` and downloads the pinned NeutralinoJS `bin/` and `neutralino.js`.
- Checks are the `pre-push` jobs in `lefthook.yml`, the same ones CI runs. Tests: `node_modules/.bin/vitest run --threads false`.
- Dev run: `pnpm start` (CN Genshin) or `pnpm run start-<channel>`. To build the app: `YAAGL_CHANNEL_CLIENT=hk4ecn node build-app.js`, which needs `sophon_server/build` from `./build-sophon.sh`.
- Call tools as `node_modules/.bin/<tool>` rather than `pnpm exec`. pnpm 11's pre-exec dependency check can fail on unapproved build scripts.

## Architecture

- **Channels**: the game channel is fixed at build time by `YAAGL_CHANNEL_CLIENT` (`src/clients/<channel>.ts`). Each channel is a separate app with its own bundle id and data dir.
- **Games**: per-game logic is in `src/clients/mhy/<game>/` (Genshin is `hk4e`) and `src/clients/seasun/`. Settings are SolidJS components in `src/config/` and `*/config/`. Every UI string needs a key in all `src/locale/*.ts`.
- **Wine**: runtime, process and prefix code is in `src/wine/`. The Game Mode and full-screen design is in `docs/genshin-macos.md`.
- **Shell from TypeScript**: reuse the helpers in `src/utils/` rather than hand-rolled shell. `build()` escapes newlines, so a shell script passed to `exec` must be a single line.

## Verification

Verify game behavior with deterministic, time-boxed text output, not screenshots, and always close the game afterwards. Use `scripts/dev/yaagl-diag`; its commands are documented in `docs/genshin-macos.md`. It launches the installed `/Applications/Yaagl.app`, so build and install a change before testing it in the real app.

## Fork notes

Before a fork release, check for upstream-hardcoded values: the updater owner, the bundle id `com.3shain.yaagl`, the wine tag list in `src/wine/distro.ts`, and `CURRENT_DXMT_VERSION`. Only a tag push produces packages (`build-ontag.yaml`, draft release, semver tag). Apps are not codesigned.
