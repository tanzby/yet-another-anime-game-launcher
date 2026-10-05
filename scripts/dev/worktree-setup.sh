#!/bin/sh
# Prepare a fresh worktree of this repo for development (idempotent): bring in
# the gitignored inputs listed in .worktreeinclude from the main checkout,
# decode secret.ts, link the Sophon build and install dependencies.
set -eu
cd "$(git rev-parse --show-toplevel)"
main=$(git worktree list --porcelain | sed -n '1s/^worktree //p')

# .worktreeinclude is also what Claude Code copies when it creates a worktree.
grep -v -e '^#' -e '^$' .worktreeinclude | sed 's#/$##' | while read -r f; do
  if [ -e "$f" ]; then continue; fi
  if [ -e "$main/$f" ]; then
    cp -cR "$main/$f" "$f" # APFS clone: no extra disk space
    echo "copied $f from the main checkout"
  else
    echo "$f is missing: fetch it as at the end of configure.sh" >&2
  fi
done

# Channel secrets are decoded from the tracked base64 file (as configure.sh).
[ -f src/clients/secret.ts ] || base64 -d -i src/clients/secret.b64 -o src/clients/secret.ts

# The Sophon server build (74 MB) is only needed by `pnpm start` and
# build-app.js: share the main checkout's copy.
if [ ! -e sophon_server/build ] && [ -d "$main/sophon_server/build" ]; then
  ln -s "$main/sophon_server/build" sophon_server/build
fi

# Near no-op when up to date; also refreshes deps after a lockfile change.
# --ignore-workspace: otherwise pnpm walks up to the main checkout's
# (gitignored) pnpm-workspace.yaml and installs there instead. pnpm 11 fails on
# unapproved dependency build scripts; none are needed for development.
pnpm install --ignore-workspace --frozen-lockfile --prefer-offline --config.strict-dep-builds=false
echo "worktree ready: $PWD"
