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

`gamemode=on` means `gamepolicyd` reported both `isIdentifiedGame=1` and `isGameFullscreen=1` (logged in `logs/gamehost.log`). Game progress can be checked in `wineprefix/drive_c/users/crossover/AppData/LocalLow/miHoYo/原神/output_log.txt` (`Genshin Start Log:` lines).
