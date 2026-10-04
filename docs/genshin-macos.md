# Genshin on macOS: Game Mode and process cleanup

## Game Mode

macOS enables Game Mode only when **both** hold for the front process, as decided by `gamepolicyd`:

- `isIdentifiedGame`: LaunchServices maps the process to a **registered app bundle** with `LSApplicationCategoryType = public.app-category.games`. An unbundled binary's embedded `__info_plist` is not enough: it was tested and reported `isIdentifiedGame=0`.
- `isGameFullscreen`: the window is in a **native full-screen Space**. Wine's mac driver offers native full screen only for resizable windows; the game's window is not resizable, so before this change it never got one.

Implementation (setting "Native full screen + Game Mode", on by default, `config_game_mode`):

- `src/wine/game-host.ts` installs `native/gamehost/wine-shim.c` as `<wine>/lib/wine/x86_64-unix/wine` and keeps the original host as `wine-host`. Wine execs that path for every new Windows process. When `argv[1]` contains the game executable, the shim execs `YaaglGame.app/Contents/MacOS/wine` instead. That file is a copy of `wine-host` in a bundle registered with `lsregister`. All other processes run `wine-host` unchanged.
- The bundle copy is re-signed with `-i com.3shain.yaagl.game`. If the code-signing identifier differs from the bundle identifier, every `getaddrinfo` in the process stalls for about 35 s.
- `native/gamehost/gamehost.c` is injected into the game process only. The shim sets `DYLD_INSERT_LIBRARIES` from `YAAGL_GAME_HOST_DYLIB` when it execs the game and clears it for the game's child processes. It links only libSystem and attaches once `winemac.so` is loaded. It does four things:
  - moves the game window (at least half the screen) into a native full-screen Space;
  - keeps winemac from dropping the full-screen behavior;
  - logs `gamepolicyd`'s verdict through `GPProcessMonitor` in the private GamePolicy framework;
  - answers lookups of the Mac's own `<host>.local` name from the interface address. That lookup is mDNS, which counts as Local Network access, and the bundled game is silently held about 35 s on it. Other names use the system resolver.
- The process exits if it is still running 15 s after its window closed. The launcher cannot time this out itself: its wait on `steam.exe` only returns once the game process is gone.

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

`--autoplay` loads `native/gamehost/gamehost-dev.m` into the game (`YAAGL_GAMEHOST_DEV`). It clicks into the world, then logs frame-interval statistics for an idle phase and a camera-turn phase (`frames: … p50/p99/max, hitches50`) and saves a PNG of each from the game's own drawable. The turn is driven by `turner.exe` (`SendInput` inside the prefix). Synthetic AppKit events do not turn the camera. These dev pieces are not shipped in the app: `--autoplay` builds them with `native/gamehost/build.sh --dev` into the data dir's sidecar. `turner.exe` needs llvm-mingw (`LLVM_MINGW=/path`).

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

Cold-cache turn phase (shader caches moved aside for the run, then restored; `$TMPDIR/../C/d3dm/YuanShen.exe` for GPTK, `$TMPDIR/../C/dxmt/YuanShen.exe` for DXMT):

| Backend | Option | Hitches > 50 ms | p99 |
| --- | --- | --- | --- |
| DXMT | — | 19 | 113.8 ms |
| GPTK | `D3DM_MTL4=1` | 16, 9 | 104.5, 52.3 ms |
| GPTK | `D3DM_MTL4=0` | 8, 12 | 54.3, 73.2 ms |

Turn stutter is first-use shader compilation on both backends. The cache is filled per area and the next pass is smooth (warm: 0–2 hitches on both). The user's GPTK stutter came from a young cache: 59 MB for GPTK vs 272 MB for DXMT. D3DMetal has no async or cache option among its `D3DM_*` variables, and `D3DM_MTL4` / `D3DM_MAX_FPS` made no consistent difference.

Volumetric fog was checked with the scene's own setting, using `--grade 9=1` (fog off) at the spawn point. Background luma was 160.6 for DXMT with fog on, 125.5 for DXMT with fog off, and 159.9 for GPTK with fog on. The fog is rendered, and GPTK renders it like DXMT. DXMT stays the default.

`gamemode=on` means `gamepolicyd` reported both `isIdentifiedGame=1` and `isGameFullscreen=1` (logged in `logs/gamehost.log`). Game progress can be checked in `wineprefix/drive_c/users/crossover/AppData/LocalLow/miHoYo/原神/output_log.txt` (`Genshin Start Log:` lines).
