# 原生 App 的目标架构：七个 SwiftPM target、单向依赖、幂等重跑

原生 Swift 版（地图 #13，票 #22）按下面的模块和缝划分。这是后续骨架（#25）和各模块实现票的前提。前提条件已由其他票定下：macOS 26+、仅 Apple Silicon、Swift 6 strict concurrency、`@Observable`、SwiftPM + XcodeGen、Sophon 用 Swift 重写、只允许 Wine / x86_64 helper / 白名单系统工具作为外部进程（#27）、不兼容 TS 数据（ADR 0001）。

## Target 与依赖

`macos/Package.swift` 一个包放所有库 target，每个库一个测试 target。XcodeGen 的 `project.yml` 只定义 App 和两个 x86_64 helper，App 依赖这个本地包。

```
YaaglApp (XcodeGen app)   SwiftUI 视图、Sparkle、系统通知、组合根
 ├─> Launcher             LauncherModel / SettingsModel、PrimaryAction.derive、JobCoordinator；定义 GameClient 协议
 │    ├─> Platform        DataDirectory、HostsBlocklist(+AdminShell)、Downloader、ToolRunner、日志；定义 ProcessRunning / AdminPrivilege 端口
 │    └─> Wine            WineRuntime(actor)、GameSession(Launch Mutations + journal)、GameHost 准备
 └─> GenshinCN            原神 CN 常量 + GenshinCNClient: GameClient（组合 Sophon + Wine + Platform）
      └─> Sophon          SophonClient、已装版本检测；依赖 swift-protobuf、libzstd、CHDiffPatch(C target)
x86_64 helper（XcodeGen target，放进 Contents/Helpers/）: YaaglWineShim、YaaglGameHost，源码在 macos/Helpers/
```

- `Wine → Platform`，`GenshinCN → {Sophon, Wine, Platform}`，`Launcher → {Platform, Wine}`。`Sophon` 不依赖 `Platform`，只用 URLSession 和文件系统。
- 不设 `Core`（会变成杂物堆）、`Patch`（见术语）、`Updater`（Sparkle 的 `SPUStandardUpdaterController` 本身就是深模块，在 `YaaglApp` 里直接用，appcast 和公钥写在 Info.plist）。
- `Launcher` 与 `YaaglApp` 分开，是因为 App target 无法 `swift test`；业务编排和状态机必须能脱离 UI 测试。
- 游戏无关的东西（数据目录、hosts、Wine 运行时）归 `Platform` / `Wine`，由 `Launcher` 直接使用；游戏相关的东西（端点、game_id、可执行文件名、`removed` 列表、hosts 域名）归 `GenshinCN`。

## GameClient

`GameClient` 协议由 `Launcher` 定义，`GenshinCNClient` 是生产实现，`FakeGameClient` 是测试实现。两个 adapter，所以这条缝是真的：`Launcher` 的状态机、暂停与继续、错误重试都用 Fake 测试，不拉起 Sophon 或 Wine。接口保持很薄：

```swift
protocol GameClient: Sendable {
  func status() async throws -> GameStatus                       // 本地版本、远端版本、可更新、可预下载
  func run(_ job: GameJob) -> AsyncThrowingStream<JobProgress, Error>   // install / update / preDownload / repair
  func launch(_ options: LaunchOptions) async throws -> LaunchOutcome
}
```

保留这个协议是维护者的有意预留（现在只有原神 CN 一个实现）。第二个游戏出现时，以此为起点。

## 状态与并发

- 领域库（`Sophon`、`Wine`、`Platform`、`GenshinCN`）不 import Observation / SwiftUI。共享可变状态放 actor，对外只给 async 函数和 `AsyncStream`。
- `Launcher` 里一个 `@MainActor @Observable LauncherModel` 是主窗口的唯一事实来源，进程内只有一份，在组合根创建并通过 `.environment` 注入。主按钮状态是纯函数 `PrimaryAction.derive(snapshot)`，单独测试。
- 设置是另一个 `@MainActor @Observable SettingsModel`，类型化属性、`didSet` 写入。领域库不读 `UserDefaults`：`Launcher` 启动游戏时把设置快照成值类型 `LaunchOptions` 传入。
- **作业并发（`JobCoordinator`）**：独占作业同时只有一个（Wine 准备、install、update、repair、launch）。预下载可以与启动、运行中重叠（#21 已定：预下载中主按钮仍是「开始游戏」；预下载只写临时目录，不碰游戏文件）。预下载中点「更新」，先取消预下载再更新，复用已缓存的内容。退出 App 时有进行中的作业，取消并保存「未完成作业」。游戏运行中退出启动器，先确认，确认后走 shutdown。

## 暂停、继续与进度

- **暂停 = 取消 Task，继续 = 用同样参数重跑同一个操作。** 每个 Sophon 操作幂等。断点就是磁盘上已有的东西：完整 chunk 缓存、已校验的文件、已下完的 ldiff。不维护 chunk 级进度日志，继续时开头有一次磁盘扫描，是接受的代价。唯一持久化的是「有一个未完成作业（种类 + 目标版本）」，存在 `state.json`，重启后主按钮据此显示「继续」。
- **进度**：`Sophon` 对外只暴露收窄枚举 `SophonProgress`（`preparing`、`downloading(done,total)`、`verifying(done,total)`、`patching(done,total)`、`finalizing`）。操作形状是 `SophonClient.run(_:in:) -> AsyncThrowingStream<SophonProgress, Error>`，消费方 Task 取消即取消作业。生产端限流，每秒最多 4 条。速度和剩余时间由 `Launcher` 用滑动窗口计算，`Sophon` 不算。`Platform` 的下载（Wine、DXMT、ReShade）有自己的进度类型，`Launcher` 把它们和 `SophonProgress` 一起映射成统一的 `JobProgress`。
- **Sophon 接口**：`onlineInfo() async throws -> OnlineInfo`（最新版本、安装大小、可增量更新的旧版本、`preDownload: 目标版本?`，分支为 null 是 `nil`，不是异常）；已装版本检测（`globalgamemanagers` 正则与 `config.ini` 取较小值）也在 `Sophon`，因为 `config.ini` 由它写。
- **临时目录**：`<game>/.yaagl-tmp`（chunk 缓存、ldiff、组装中文件）。放在游戏目录内，是因为游戏目录可能在外置盘，只有同卷才能原子 rename 移入。TS 的位置也是游戏目录内（`.tmp`、`ldiff`），这里换新名字，并在 Sophon 首次运行时删掉遗留的 `<game>/.tmp` 和 `<game>/ldiff`。文件名用完整相对路径，修掉 TS 里按 basename 命名导致撞名的问题。

## 存储、清场与提权

- **偏好**（含游戏目录）用 `UserDefaults`，这是 macOS 惯例，Sparkle 的开关也在这里。**机器状态**放数据目录的 `state.json`：`schemaVersion`（原生标记）、已装 Wine / DXMT 版本、已预下载的目标版本、未完成作业。这类状态描述的是数据目录里的内容，必须与它同生命周期，清场或重装 Wine 时一起消失。`Codable`、原子写入、忽略未知字段。
- **首启清场**在 `Platform` 的 `DataDirectory`：`DataDirectory.prepare()` 没有原生标记就按 ADR 0001 清场，再写入标记，返回已就绪的数据目录值。在它返回之前，其他模块拿不到数据目录路径。
- **提权**：`AdminShell`（进程内 `NSAppleScript`）是 `Platform` 的内部类型，唯一调用方是 `HostsBlocklist`，不对外暴露「以 root 跑任意命令」。`HostsBlocklist.status()` 只读 `/etc/hosts`，不需要权限；`apply()` 弹出密码框。
- `Launcher` 的启动顺序固定：清场 → hosts 检查（不通过则引导，并禁止启动游戏）→ Wine 就绪 → 读取本地与远端游戏状态。

## Wine 与启动会话

- `Wine` 对外两个东西。`WineRuntime`（actor）：确保已安装固定版本、重装、prefix 初始化、DXMT 下载、shutdown。`GameSession`：`launch(options:game:)` 一次调用里完成写注册表、`config.bat`、Launch Mutations、启动、等待退出、清理，清理放 `defer`。
- **崩溃恢复**：改动前先写 mutations journal（数据目录里的小文件，记录要还原的文件改名、注册表项、DXMT DLL），正常还原后删除。`Launcher` 启动时调用 `GameSession.recover()` 重放 journal，取代 TS 的 `patched` 标记。这样「异常退出时是否撤销 HDR / 分辨率注册表」只是 #28 可以直接选的策略，不再是架构问题。
- Game Mode、全屏、刘海区域全在注入 Wine 的 x86_64 shim 与 dylib 里，Swift 不重写；`Wine` 只负责准备 `YaaglGame.app`、`codesign`、`LSRegisterURL` 和传四个 `YAAGL_GAME_HOST*` 环境变量。

## 测试缝

只设两个端口（各有生产实现和测试替身）：`ProcessRunning`（Wine 调用和白名单系统工具都走它，测试记录参数、环境变量、工作目录）和 `AdminPrivilege`。HTTP 不设端口，测试用 `URLProtocol` 打桩，喂录制的 getBuild、manifest、chunk 夹具。文件系统用真实临时目录。节流和速度计算注入 `Clock`。`GameClient` 是第三条缝（见上）。所以 `GameSession` 可完整测试：断言写出的注册表、`config.bat`、文件改动、环境变量表，以及还原后磁盘回到原状。

## 术语

- **ldiff**：Sophon 的增量更新文件，一个文件里拼接多个 HDiffPatch 补丁。只在 `Sophon` 内部出现。
- **Launch Mutations**：启动前对游戏文件、Wine 运行时和 prefix 的改动（`.bak` 改名、DXMT 注入、protonextras、注册表），退出后还原。在 `GameSession` 内部。
- 领域词汇里不单用「Patch」这个词。

## x86_64 helper 的源码位置

`YaaglWineShim` 与 `YaaglGameHost` 的 C 源码放在 `macos/Helpers/`，由骨架票（#25）从 `native/gamehost/` 用 `git mv` 移过去。TS 版已经发布最后一个稳定版，不再需要保持可构建，因此不留并行期的双份或相对引用。开发专用的 `gamehost-dev.m`、`turner.c` 继续用 `build.sh --dev`，不进 `project.yml`。

## Considered Options

- 保留暂定的 `Core / Sophon / Patch / Wine / Updater / App`：否决。`Core` 会变成杂物堆；`Patch` 一词同时指 ldiff 和启动改动，各自的归属不同；`Updater` 只是转发 Sparkle。
- 把 `Launcher` 并进 `App`：否决，状态机和编排无法 `swift test`。
- chunk 级进度日志：否决，多一份必须与磁盘保持一致的状态；幂等重跑已够用。
- 全部设置放 `UserDefaults` 或全部放数据目录 JSON：否决。偏好和机器状态的生命周期不同。
- 给 HTTP、文件系统都设端口：否决，只会多出仅供测试用的间接层。
- 去掉 `GameClient` 协议：维护者选择保留，作为对第二个游戏的预留。

## 未验证

- ad-hoc 签名、未公证的 App 能否拿到 `UNUserNotificationCenter` 授权（地图 Not yet specified 已记录）。通知相关代码只放在 `YaaglApp`，不影响本架构。
