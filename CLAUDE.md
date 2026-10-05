@AGENTS.md

## Claude Code

- If the session is in the main checkout, call `EnterWorktree` before editing anything. It symlinks `node_modules` and `sophon_server/build` from the main checkout (`.claude/settings.json`) and copies the `.worktreeinclude` files, so the worktree is ready at once. Run `scripts/dev/worktree-setup.sh` only if the branch changes `pnpm-lock.yaml`.
