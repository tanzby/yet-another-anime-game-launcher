# Genshin on macOS: Game Mode and process cleanup

## Game Mode

macOS enables Game Mode only when **both** hold for the front process, as decided by `gamepolicyd`:

- `isIdentifiedGame`: LaunchServices maps the process to a **registered app bundle** with `LSApplicationCategoryType = public.app-category.games`. An unbundled binary's embedded `__info_plist` is not enough: it was tested and reported `isIdentifiedGame=0`.
- `isGameFullscreen`: the window is in a **native full-screen Space**. Wine's mac driver offers native full screen only for resizable windows; the game's window is not resizable, so before this change it never got one.

Implementation (setting "Native full screen + Game Mode", on by default, `config_game_mode`):

- `src/wine/game-host.ts` installs `native/gamehost/wine-shim.c` as `<wine>/lib/wine/x86_64-unix/wine` and keeps the original host as `wine-host`. Wine execs that path for every new Windows process. When `argv[1]` contains the game executable, the shim execs `YaaglGame.app/Contents/MacOS/wine` instead. That file is a copy of `wine-host` in a bundle registered with `lsregister`. All other processes run `wine-host` unchanged.
- The bundle copy is re-signed with `-i com.3shain.yaagl.game`. If the code-signing identifier differs from the bundle identifier, every `getaddrinfo` in the process stalls for about 35 s.
- `native/gamehost/gamehost.c` is injected with `DYLD_INSERT_LIBRARIES`. It links only libSystem and attaches once `winemac.so` is loaded. It does four things:
  - moves the game window (at least half the screen) into a native full-screen Space;
  - keeps winemac from dropping the full-screen behavior;
  - logs `gamepolicyd`'s verdict through `GPProcessMonitor` in the private GamePolicy framework;
  - answers lookups of the Mac's own `<host>.local` name from the interface address. That lookup is mDNS, which counts as Local Network access, and the bundled game is silently held about 35 s on it. Other names use the system resolver.
- The process exits if it is still running 15 s after its window closed.

## Process cleanup

`Wine.shutdown()` runs `wineserver -k`, then kills every process of the prefix. A process belongs to the prefix if it maps files from `/tmp/.wine-<uid>/server-<dev>-<inode of prefix>`, or if its working directory is inside the prefix. The second rule catches orphans whose wineserver died, such as `winedevice.exe`. Shutdown runs before each launch. After the game exits, the launcher waits at most 15 s for Wine to exit on its own before forcing shutdown.

## Verification

`scripts/dev/yaagl-diag` prints text only. With `--launch`, it starts Yaagl using `YAAGL_AUTOLAUNCH=1` (no clicks). Yaagl then quits after the game exits and its patches are reverted. The tool always cleans up the prefix when it finishes.

```bash
scripts/dev/yaagl-diag watch --launch --timeout 60 --until gamemode
scripts/dev/yaagl-diag watch --launch --timeout 150 --until exit --close-after 40
scripts/dev/yaagl-diag ps
scripts/dev/yaagl-diag kill --orphans
```

`--autoplay` loads `native/gamehost/gamehost-dev.m` into the game (`YAAGL_GAMEHOST_DEV`). It clicks into the world, then logs frame-interval statistics for an idle phase and a camera-turn phase (`frames: … p50/p99/max, hitches50`) and saves a PNG of each from the game's own drawable. The turn is driven by `turner.exe` (`SendInput` inside the prefix). Synthetic AppKit events do not turn the camera. Build it with `LLVM_MINGW=… native/gamehost/build.sh`.

```bash
scripts/dev/yaagl-diag watch --launch --autoplay --timeout 200
```

Measured on 2026-10-04 (M5 Pro, DXMT, native full screen, fast continuous turn):

| Retina | Phase | fps | p99 | Max | Hitches > 50 ms |
| --- | --- | --- | --- | --- | --- |
| On (3024×1898) | Idle | 51.8 | 20.5 ms | 32.7 ms | 0 |
| On (3024×1898) | Turn | 54.0 | 25.4 ms | 42.6 ms | 0 |
| Off (1512×949) | Idle | 59.8 | 17.2 ms | 36.2 ms | 0 |
| Off (1512×949) | Turn | 59.8 | 19.1 ms | 25.1 ms | 0 |

GPTK 4 Beta 2 (`--runtime wine-gptk4`; the runtime dir is selected through `YAAGL_WINE_RUNTIME`, dev only), same spot, Retina on:

| Run | Phase | fps | p99 | Max | Hitches > 50 ms |
| --- | --- | --- | --- | --- | --- |
| First (cold D3DMetal cache) | Idle | 59.4 | 47.6 ms | 71.1 ms | 5 |
| First (cold D3DMetal cache) | Turn | 51.8 | 100.9 ms | 143.3 ms | 24 |
| Second (warm cache) | Idle | 57.9 | 51.3 ms | 142.6 ms | 7 |
| Second (warm cache) | Turn | 59.4 | 28.3 ms | 135.7 ms | 2 |

GPTK's turn stutter is mostly D3DMetal shader compilation. Its cache is `$TMPDIR/../C/d3dm`, and the second run through the same area is smooth. Idle hitches remain; DXMT has none. In the spawn-area screenshots, DXMT and GPTK show the same background haze: luma 160.6 vs 159.9, contrast 36.7 vs 35.0. Missing volumetric fog is not reproduced there. Scenes where the fog is prominent (forest, night, god rays) are not covered by the script. DXMT stays the default.

`gamemode=on` means `gamepolicyd` reported both `isIdentifiedGame=1` and `isGameFullscreen=1` (logged in `logs/gamehost.log`). Game progress can be checked in `wineprefix/drive_c/users/crossover/AppData/LocalLow/miHoYo/原神/output_log.txt` (`Genshin Start Log:` lines).
