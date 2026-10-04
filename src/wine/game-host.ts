import { join } from "path-browserify";
import {
  cp,
  exec,
  fileOrDirExists,
  forceMove,
  log,
  mkdirp,
  readFile,
  resolve,
  writeFile,
} from "@utils";

// Native helpers built from native/gamehost (see build.sh).
const SHIM = "./sidecar/gamehost/yaagl-wine-shim";
const DYLIB = "./sidecar/gamehost/yaagl-gamehost.dylib";
const BUNDLE = "./YaaglGame.app";
const BUNDLE_ID = "com.3shain.yaagl.game";
const LSREGISTER =
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

async function same(a: string, b: string) {
  try {
    await exec(["cmp", "-s", a, b]);
    return true;
  } catch {
    return false;
  }
}

function infoPlist(displayName: string) {
  // gamepolicyd identifies games through the LaunchServices record of a
  // registered bundle; the embedded plist of an unbundled binary is not enough.
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>wine</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>${displayName}</string>
  <key>CFBundleDisplayName</key><string>${displayName}</string>
  <key>CFBundleIconFile</key><string>icon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSPrincipalClass</key><string>WineApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSSupportsGameMode</key><true/>
</dict>
</plist>
`;
}

/**
 * Run the game process from a registered game .app (so macOS can enable Game
 * Mode) and inject the helper that moves its window into a native
 * full-screen Space. Returns the environment for the game launch, or {} when
 * the helpers are unavailable (the game then runs as before).
 */
export async function prepareGameHost(
  runtimePath: string,
  displayName: string,
  gameExecutable: string
): Promise<{ [key: string]: string }> {
  const shim = resolve(SHIM);
  const dylib = resolve(DYLIB);
  const present = await Promise.all([shim, dylib].map(fileOrDirExists));
  if (!present.every(Boolean)) return {};
  try {
    const unixDir = join(runtimePath, "lib", "wine", "x86_64-unix");
    const loader = join(unixDir, "wine");
    const host = join(unixDir, "wine-host");
    if (!(await fileOrDirExists(host))) {
      // A fresh runtime: keep its host as wine-host. Never move the shim there.
      if (await same(shim, loader)) throw new Error("wine-host is missing");
      await forceMove(loader, host);
    }
    if (!(await same(shim, loader))) await cp(shim, loader);

    // Rebuild and re-register the bundle only when its contents change.
    const contents = join(resolve(BUNDLE), "Contents");
    const exe = join(contents, "MacOS", "wine");
    const source = join(contents, "MacOS", ".wine-host");
    const plistPath = join(contents, "Info.plist");
    const plist = infoPlist(displayName);
    let changed = false;
    if (!(await same(host, source))) {
      await Promise.all([
        mkdirp(join(contents, "MacOS")),
        mkdirp(join(contents, "Resources")),
      ]);
      await cp(host, source);
      await cp(host, exe);
      // The signing identifier must match the bundle identifier, or every
      // getaddrinfo in the process stalls for ~30s.
      await exec(["codesign", "-f", "-s", "-", "-i", BUNDLE_ID, exe]);
      if (await fileOrDirExists(resolve("./icon.icns"))) {
        await cp(
          resolve("./icon.icns"),
          join(contents, "Resources", "icon.icns")
        );
      }
      changed = true;
    }
    if ((await readFile(plistPath).catch(() => "")) !== plist) {
      await writeFile(plistPath, plist);
      changed = true;
    }
    if (changed) await exec([LSREGISTER, "-f", resolve(BUNDLE)]);
    return {
      YAAGL_GAME_HOST_EXE: exe,
      YAAGL_GAME_HOST_MATCH: gameExecutable,
      // The shim injects it into the game process only.
      YAAGL_GAME_HOST_DYLIB: dylib,
      YAAGL_GAMEHOST_LOG: resolve("./logs/gamehost.log"),
    };
  } catch (e) {
    await log(`game host unavailable: ${String(e)}`);
    return {};
  }
}
