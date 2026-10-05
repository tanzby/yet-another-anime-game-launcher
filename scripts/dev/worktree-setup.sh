#!/bin/sh
# Prepare a fresh git worktree of this repo for development (idempotent).
#
# A new worktree only contains tracked files. Claude Code copies the small
# gitignored inputs listed in .worktreeinclude on creation; this script fills
# in whatever is still missing (also for worktrees made with plain
# `git worktree add`) and installs dependencies.
set -eu
root=$(git rev-parse --show-toplevel)
main=$(git -C "$root" worktree list --porcelain | sed -n '1s/^worktree //p')
cd "$root"

# Gitignored inputs that cannot be regenerated cheaply: take them from the
# main checkout.
for f in bin neutralino.js pnpm-workspace.yaml; do
  if [ ! -e "$f" ] && [ -e "$main/$f" ]; then
    cp -R "$main/$f" "$f"
    echo "copied $f from the main checkout"
  fi
done

# Channel secrets are decoded from the tracked base64 file (see configure.sh).
if [ ! -f src/clients/secret.ts ]; then
  base64 -d -i src/clients/secret.b64 -o src/clients/secret.ts
  echo "decoded src/clients/secret.ts"
fi

# Sophon server build (74 MB, only needed for `pnpm start` / build-app.js):
# share the main checkout's copy instead of rebuilding it.
if [ ! -e sophon_server/build ] && [ -d "$main/sophon_server/build" ]; then
  ln -s "$main/sophon_server/build" sophon_server/build
  echo "linked sophon_server/build to the main checkout"
fi

# pnpm 11 fails on dependency build scripts not approved in
# pnpm-workspace.yaml (gitignored, per machine); none are needed here.
if [ ! -d node_modules/.bin ]; then
  pnpm install --frozen-lockfile --config.strict-dep-builds=false
fi

if [ ! -e bin ] || [ ! -e neutralino.js ]; then
  echo "bin/ or neutralino.js missing: run 'node_modules/.bin/neu update'" >&2
fi
echo "worktree ready: $root"
