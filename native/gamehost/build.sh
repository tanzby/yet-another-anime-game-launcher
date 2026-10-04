#!/bin/sh
# Build the x86_64 (Rosetta) game-host helpers into $1 (default: sidecar/gamehost).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/../../sidecar/gamehost}"
mkdir -p "$out"
clang -arch x86_64 -O2 -Wall -Wextra -o "$out/yaagl-wine-shim" "$here/wine-shim.c"
clang -arch x86_64 -O2 -Wall -Wextra -dynamiclib -o "$out/yaagl-gamehost.dylib" "$here/gamehost.c"
codesign -f -s - "$out/yaagl-wine-shim" "$out/yaagl-gamehost.dylib" 2>/dev/null
