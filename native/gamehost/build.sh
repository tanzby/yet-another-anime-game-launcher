#!/bin/sh
# Build the x86_64 (Rosetta) game-host helpers into $1 (default: sidecar/gamehost).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/../../sidecar/gamehost}"
mkdir -p "$out"
clang -arch x86_64 -O2 -Wall -Wextra -o "$out/yaagl-wine-shim" "$here/wine-shim.c"
clang -arch x86_64 -O2 -Wall -Wextra -dynamiclib -o "$out/yaagl-gamehost.dylib" "$here/gamehost.c"
clang -arch x86_64 -O2 -Wall -fobjc-arc -dynamiclib -undefined dynamic_lookup \
  -framework AppKit -framework Metal -framework QuartzCore -framework ImageIO \
  -framework UniformTypeIdentifiers -o "$out/yaagl-gamehost-dev.dylib" "$here/gamehost-dev.m"
codesign -f -s - "$out/yaagl-wine-shim" "$out/yaagl-gamehost.dylib" "$out/yaagl-gamehost-dev.dylib" 2>/dev/null
# Dev-only camera turner for `yaagl-diag watch --autoplay`; needs llvm-mingw
# (https://github.com/mstorsjo/llvm-mingw), e.g. LLVM_MINGW=/path/to/llvm-mingw.
mingw="${LLVM_MINGW:+$LLVM_MINGW/bin/}x86_64-w64-mingw32-clang"
if command -v "$mingw" >/dev/null 2>&1; then
  "$mingw" -O2 -o "$out/turner.exe" "$here/turner.c"
fi
