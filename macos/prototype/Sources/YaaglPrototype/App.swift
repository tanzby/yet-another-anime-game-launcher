// PROTOTYPE — throwaway. Entry point, floating debug bar, snapshot mode.
//
// `swift run` opens the window. The pill at the bottom switches layout
// variant (← / → also work), game state and settings style. ⌘D hides it.
// `PROTO_SHOTS=<dir> swift run` writes PNGs of every variant × state and exits.
import AppKit
import SwiftUI

@main
struct YaaglPrototypeApp: App {
    @State private var proto = Proto()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        Window("Yaagl（原型）", id: "main") {
            RootView()
                .environment(proto)
                .transformEnvironment(\.controlActiveState) { if SnapshotRunner.enabled { $0 = .key } }
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 660)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutMenuItem() }
            CommandMenu("原型") {
                Button(proto.showDebugBar ? "隐藏调试条" : "显示调试条") { proto.showDebugBar.toggle() }
                    .keyboardShortcut("d")
            }
        }
        Settings {
            SettingsWindow()
        }
        Window("关于 Yaagl", id: "about") {
            AboutWindow()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("关于 Yaagl") { openWindow(id: "about") } }
}

struct RootView: View {
    @Environment(Proto.self) private var proto
    var body: some View {
        @Bindable var proto = proto
        ZStack(alignment: .top) {
            switch proto.variant {
            case .classic: ClassicMain()
            case .bottomBar: BottomBarMain()
            case .sidebar: SidebarMain()
            }
            if proto.showDebugBar { DebugBar().padding(.top, 8) }
        }
        .sheet(isPresented: $proto.showSettingsSheet) { SettingsSheet() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { cycle(-1); return .handled }
        .onKeyPress(.rightArrow) { cycle(1); return .handled }
        .task { await SnapshotRunner.runIfRequested(proto) }
    }

    func cycle(_ d: Int) {
        let all = MainVariant.allCases
        let i = all.firstIndex(of: proto.variant)!
        proto.variant = all[(i + d + all.count) % all.count]
    }
}

struct DebugBar: View {
    @Environment(Proto.self) private var proto
    var body: some View {
        @Bindable var proto = proto
        HStack(spacing: 10) {
            Text("PROTOTYPE").font(.caption2.bold()).foregroundStyle(.yellow)
            Picker("布局", selection: $proto.variant) {
                ForEach(MainVariant.allCases) { Text($0.name).tag($0) }
            }.fixedSize()
            Picker("状态", selection: $proto.state) {
                ForEach(GameState.allCases) { Text($0.debugName).tag($0) }
            }.fixedSize()
            Picker("设置样式", selection: $proto.settingsStyle) {
                ForEach(SettingsStyle.allCases) { Text($0.rawValue).tag($0) }
            }.fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.black.opacity(0.8), in: .capsule)
        .environment(\.colorScheme, .dark)
        .shadow(radius: 8)
    }
}

/// Writes PNGs of the main window for every variant × state, plus each
/// settings pane in both styles, then quits.
@MainActor
enum SnapshotRunner {
    static let enabled = ProcessInfo.processInfo.environment["PROTO_SHOTS"] != nil

    static func runIfRequested(_ proto: Proto) async {
        guard let dir = ProcessInfo.processInfo.environment["PROTO_SHOTS"] else { return }
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        proto.showDebugBar = false
        await OfficialArt.shared.load()
        try? await Task.sleep(for: .seconds(4))   // let AsyncImage fetch
        let states: [GameState] = [.notInstalled, .installing, .installPaused, .ready, .updateAvailable, .updating, .launching,
                                   .predownloadAvailable, .repairing, .running, .error]
        for v in [MainVariant.bottomBar] {
            proto.variant = v
            for s in states {
                proto.state = s
                proto.progress = 0.42
                try? await Task.sleep(for: .milliseconds(400))
                if let w = NSApp.windows.first(where: { $0.title.hasPrefix("Yaagl") }) {
                    capture(w, to: url.appending(path: "main-\(v.rawValue)-\(s.rawValue).png"))
                }
            }
        }
        let win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 760, height: 540),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 760, height: 540))
        for pane in SettingsPane.allCases {
            win.title = pane.rawValue
            win.contentView = NSHostingView(rootView: SettingsWindowPreview(pane: pane))
            win.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(600))
            capture(win, to: url.appending(path: "settings-\(pane).png"))
        }
        win.title = ""
        win.contentView = NSHostingView(rootView: AboutWindow())
        win.setContentSize(win.contentView!.fittingSize)
        try? await Task.sleep(for: .milliseconds(500))
        capture(win, to: url.appending(path: "about-window.png"))
        win.setContentSize(NSSize(width: 760, height: 540))
        win.title = "Wine"
        win.contentView = NSHostingView(rootView: SettingsWindowPreview(pane: .wine, confirm: true))
        try? await Task.sleep(for: .milliseconds(800))
        capture(win, to: url.appending(path: "settings-wine-confirm.png"))
        win.orderOut(nil)
        NSApp.terminate(nil)
    }

    /// Real window pixels (materials, button tints) via screencapture.
    static func capture(_ w: NSWindow, to url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        p.arguments = ["-x", "-o", "-l", String(w.windowNumber), url.path]
        try? p.run(); p.waitUntilExit()
        if !FileManager.default.fileExists(atPath: url.path), let v = w.contentView { save(v, to: url) }
    }

    static func save(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Settings window body with a given pane selected, for snapshots.
struct SettingsWindowPreview: View {
    var pane: SettingsPane
    var confirm = false
    @State private var sel: SettingsPane?
    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $sel) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            if confirm { WineSettings(previewConfirm: true) } else { pane.content }
        }
        .frame(width: 760, height: 540)
        .onAppear { sel = pane }
    }
}
