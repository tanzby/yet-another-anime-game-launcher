# AGENTS.md

Yaagl is a macOS launcher for anime games. It runs the Windows game through a modified Wine with DXMT, using TypeScript, SolidJS and Vite on NeutralinoJS, with native helpers in `macos/Helpers/`. This repo is the fork `tanzby/yet-another-anime-game-launcher` of upstream `yaagl/` (3Shain); PRs target this fork's `main`.

## Workflow: one worktree per change

Every change is made in its own git worktree and branch, never in the main checkout.

- **Keep the main checkout clean.** It stays on `main` and is shared by every session and tool.
- **Create worktrees under `.claude/worktrees/<name>`** (gitignored), branched from `origin/main`. If it has no `node_modules`, run `scripts/dev/worktree-setup.sh` (idempotent) first.
- **Land changes via PR.** `main` is protected (PR and `tsc` check required) and PRs are squash-merged.
- **Clean up unasked after a merge or release**: remove the worktree and branch, fast-forward `main` in the main checkout, delete temp files, and remove other merged worktrees that no session is using. A squash-merged branch looks unmerged to git; it is safe to delete when `git merge-tree --write-tree origin/main <branch>` equals `git rev-parse 'origin/main^{tree}'`.
- **Only one worktree may run the game at a time** (install the app, run the game or `scripts/dev/yaagl-diag`). All worktrees share `/Applications/Yaagl.app`, `~/Library/Application Support/Yaagl` (Wine, prefix, settings) and the game files.
- **The stash stack is shared by all worktrees.** Never use bare `git stash` / `git stash pop`; prefer a WIP commit.

Plain git:

```bash
git fetch origin && git worktree add .claude/worktrees/<name> -b <branch> origin/main
git worktree remove .claude/worktrees/<name>   # after merge, then git branch -D <branch>
```

## Commands

- First-time setup of the main checkout: `pnpm install` and `./configure.sh`. `configure.sh` decodes `src/clients/secret.ts` and downloads the pinned NeutralinoJS `bin/` and `neutralino.js`.
- Checks are the `pre-push` jobs in `lefthook.yml`, the same ones CI runs. Tests: `node_modules/.bin/vitest run --threads false`.
- Dev run: `pnpm start` (CN Genshin) or `pnpm run start-<channel>`. To build the app: `YAAGL_CHANNEL_CLIENT=hk4ecn node build-app.js`, which needs `sophon_server/build` from `./build-sophon.sh`.
- Call tools as `node_modules/.bin/<tool>` rather than `pnpm exec`. pnpm 11's pre-exec dependency check can fail on unapproved build scripts.

- Native app (`macos/`): `scripts/dev/macos-check` runs `swift test`, then `xcodegen generate` and `xcodebuild` (needs Xcode 26+ and `brew install xcodegen`). It is the `macos` job in CI and `pre-push`. The layout follows `docs/adr/0002-native-architecture.md`.

## Architecture

- **Channels**: the game channel is fixed at build time by `YAAGL_CHANNEL_CLIENT` (`src/clients/<channel>.ts`). Each channel is a separate app with its own bundle id and data dir.
- **Games**: per-game logic is in `src/clients/mhy/<game>/` (Genshin is `hk4e`) and `src/clients/seasun/`. Settings are SolidJS components in `src/config/` and `*/config/`. Every UI string needs a key in all `src/locale/*.ts`.
- **Wine**: runtime, process and prefix code is in `src/wine/`. The Game Mode and full-screen design is in `docs/genshin-macos.md`.
- **Shell from TypeScript**: reuse the helpers in `src/utils/` rather than hand-rolled shell. `build()` escapes newlines, so a shell script passed to `exec` must be a single line.

## Verification

Verify game behavior with deterministic, time-boxed text output, not screenshots, and always close the game afterwards. Use `scripts/dev/yaagl-diag`; its commands are documented in `docs/genshin-macos.md`. It launches the installed `/Applications/Yaagl.app`, so build and install a change before testing it in the real app.

## Fork notes

Before a fork release, check for upstream-hardcoded values: the updater owner, the bundle id `com.3shain.yaagl`, the wine tag list in `src/wine/distro.ts`, and `CURRENT_DXMT_VERSION`. Only a semver tag push produces packages: `build-ontag.yaml` publishes the release. Apps are not codesigned.

## Agent skills

### Issue tracker

Issues live in this fork's GitHub Issues (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md` and `docs/adr/`, created lazily. See `docs/agents/domain.md`.
