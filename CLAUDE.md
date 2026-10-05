@AGENTS.md

## Claude Code

- Start feature work in a worktree. If the session is in the main checkout, enter one first with the `EnterWorktree` tool. It creates `.claude/worktrees/<name>` on branch `worktree-<name>` from `origin/main`. Then run `scripts/dev/worktree-setup.sh`. From a terminal, `claude -w <name>` does the same, and the desktop app has a worktree option when starting a session.
- `.worktreeinclude` copies the small gitignored build inputs into worktrees that Claude Code creates. The setup script covers the rest.
- Inside a worktree, run git commands in plain form from the worktree directory, without `cd` into the main checkout or `git -C <path>`. Leave the worktree with `ExitWorktree` only when the user asks.
