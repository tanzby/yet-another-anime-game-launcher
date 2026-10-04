import {
  exec as unixExec,
  exec2 as unixExec2,
  getKey,
  log,
  setKey,
  arrayFind,
  getCPUInfo,
  build,
  env,
  generateRandomString,
  stats,
  resolve,
  writeFile,
} from "@utils";
import { dirname, join } from "path-browserify";
import { WineDistribution } from "./distro";

export async function createWine(options: {
  prefix: string;
  distro: WineDistribution;
}) {
  // Dev/diagnostics: YAAGL_WINE_RUNTIME selects another runtime directory
  // (e.g. ./wine-gptk4) in place of ./wine.
  const runtimePath = resolve(
    (await env("YAAGL_WINE_RUNTIME").catch(() => "")) || "./wine"
  );
  const loaderBin = await getCorrectWineBinary(runtimePath);

  async function cmd(command: string, args: string[]) {
    return await exec("cmd", [command, ...args]);
  }

  async function exec(
    program: string,
    args: string[],
    env?: { [key: string]: string },
    log_file: string | undefined = undefined
  ) {
    return await unixExec(
      program == "copy"
        ? [loaderBin, "cmd", "/c", program, ...args]
        : [loaderBin, program, ...args],
      {
        ...getEnvironmentVariables(),
        ...(env ?? {}),
      },
      false,
      log_file
    );
  }

  async function exec2(
    program: string,
    args: string[],
    env?: { [key: string]: string },
    log_file: string | undefined = undefined
  ) {
    return await unixExec2(
      program == "copy"
        ? [loaderBin, "cmd", "/c", program, ...args]
        : [loaderBin, program, ...args],
      {
        ...getEnvironmentVariables(),
        ...(env ?? {}),
      },
      false,
      log_file
    );
  }

  async function waitUntilServerOff() {
    return await unixExec2([join(dirname(loaderBin), "wineserver"), "-w"], {
      ...getEnvironmentVariables(),
    });
  }

  /**
   * Stop everything running in this prefix: ask wineserver to kill its
   * processes, then kill leftovers it no longer tracks (e.g. a winedevice.exe
   * orphaned after wineserver died).
   */
  async function shutdown() {
    try {
      await unixExec([join(dirname(loaderBin), "wineserver"), "-k"], {
        ...getEnvironmentVariables(),
      });
    } catch {
      // no server running
    }
    // Every process of a prefix maps files from its server directory,
    // /tmp/.wine-<uid>/server-<dev>-<inode of the prefix>; orphans whose
    // server died are caught by their working directory inside the prefix.
    // (build() escapes newlines, so the script is a single line.)
    const script = [
      `dir="/tmp/.wine-$(id -u)/server-$(printf %x $(stat -f %d "$1"))-$(printf %x $(stat -f %i "$1"))"`,
      `{ lsof -t +d "$dir" 2>/dev/null`,
      `for pid in $(ps -axo pid=,command= | awk '$2 ~ /^[CZ]:\\\\/ {print $1}'); do cwd=$(lsof -a -d cwd -Fn -p "$pid" 2>/dev/null | sed -n 's/^n//p'); case "$cwd" in "$1"/*) echo "$pid";; esac; done`,
      `} | sort -u | xargs kill -9 2>/dev/null`,
      `true`,
    ].join("; ");
    await unixExec(["sh", "-c", script, "sh", options.prefix]);
  }

  /** Wait for the prefix to shut down; force it after timeoutMs. */
  async function waitUntilServerOffOrShutdown(timeoutMs: number) {
    const done = await Promise.race([
      waitUntilServerOff().then(() => true),
      new Promise<boolean>(res => setTimeout(() => res(false), timeoutMs)),
    ]);
    if (!done) {
      await log(`Wine did not exit within ${timeoutMs}ms, shutting it down`);
      await shutdown();
    }
  }

  function toWinePath(absPath: string) {
    return "Z:" + `${absPath}`.replaceAll("/", "\\");
  }

  function getEnvironmentVariables() {
    return {
      WINEDEBUG: "fixme-all,err-unwind,+timestamp",
      WINEPREFIX: options.prefix,
    };
  }

  async function openCmdWindow({ gameDir }: { gameDir: string }) {
    return await unixExec2(
      [
        `osascript`,
        "-e",
        [
          "tell",
          "app",
          '"Terminal"',
          "to",
          "do",
          "script",
          `"${build([loaderBin, "cmd"], {
            ...getEnvironmentVariables(),
            WINEPATH: toWinePath(gameDir),
          })
            .replaceAll("\\", "\\\\")
            .replaceAll('"', '\\"')}"`,
        ].join(" "),
        "-e",
        ["tell", "app", '"Terminal"', "to", "activate"].join(" "),
      ],
      {},
      false,
      "/dev/null"
    );
  }

  let netbiosname: string;
  try {
    netbiosname = await getKey("wine_netbiosname");
  } catch {
    netbiosname = `DESKTOP-${generateRandomString(7)}`; // exactly 15 chars
    await setKey("wine_netbiosname", netbiosname);
  }

  async function setProps(props: { retina: boolean; leftCmd: boolean }) {
    const cmd = `@echo off
cd "%~dp0"
reg add "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver" /v RetinaMode /t REG_SZ /d ${
      props.retina ? "y" : "n"
    } /f
reg add "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver" /v LeftCommandIsCtrl /t REG_SZ /d ${
      props.leftCmd ? "y" : "n"
    } /f
`;
    await writeFile(resolve("winedrv_config.bat"), cmd);
    await exec(
      "cmd",
      ["/c", `${toWinePath(resolve("./winedrv_config.bat"))}`],
      {},
      "/dev/null"
    );
    await waitUntilServerOff();
  }

  async function setNVExtension() {
    const cmd = `@echo off
cd "%~dp0"
reg add "HKEY_LOCAL_MACHINE\\SOFTWARE\\NVIDIA Corporation\\Global" /v "{41FCC608-8496-4DEF-B43E-7D9BD675A6FF}" /t REG_BINARY /d 1 /f
reg add "HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\nvlddmkm" /v "{41FCC608-8496-4DEF-B43E-7D9BD675A6FF}" /t REG_BINARY /d 1 /f
reg add "HKEY_LOCAL_MACHINE\\SOFTWARE\\NVIDIA Corporation\\Global\\NGXCore" /v FullPath /t REG_SZ /d "C:\\Windows\\System32" /f
`;
    await writeFile(resolve("winedrv_config.bat"), cmd);
    await exec(
      "cmd",
      ["/c", `${toWinePath(resolve("./winedrv_config.bat"))}`],
      {},
      "/dev/null"
    );
    await waitUntilServerOff();
  }

  return {
    exec,
    exec2,
    waitUntilServerOff,
    waitUntilServerOffOrShutdown,
    shutdown,
    cmd,
    toWinePath,
    prefix: options.prefix,
    runtimePath,
    openCmdWindow,
    setProps,
    setNVExtension,
    attributes: {
      ...options.distro.attributes,
    },
  };
}

export async function getCorrectWineBinary(runtimePath = "./wine") {
  try {
    // use wine64 if it is presented
    // in newer version of wine (esp. WoW64 mode), only one binary `bin/wine` exists
    await stats(join(runtimePath, "bin", "wine64"));
    return resolve(join(runtimePath, "bin", "wine64"));
  } catch {
    return resolve(join(runtimePath, "bin", "wine"));
  }
}

export type Wine = ReturnType<typeof createWine> extends Promise<infer T>
  ? T
  : never;
