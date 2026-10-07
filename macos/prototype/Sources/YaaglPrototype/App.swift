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
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 660)
        .commands {
            CommandMenu("原型") {
                Button(proto.showDebugBar ? "隐藏调试条" : "显示调试条") { proto.showDebugBar.toggle() }
                    .keyboardShortcut("d")
            }
        }
        Settings {
            SettingsWindow()
        }
    }
}

struct RootView: View {
    @Environment(Proto.self) private var proto
    var body: some View {
        @Bindable var proto = proto
        ZStack(alignment: .bottom) {
            switch proto.variant {
            case .classic: ClassicMain()
            case .bottomBar: BottomBarMain()
            case .sidebar: SidebarMain()
            }
            if proto.showDebugBar { DebugBar().padding(.bottom, proto.variant == .bottomBar ? 96 : 8) }
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
    static func runIfRequested(_ proto: Proto) async {
        guard let dir = ProcessInfo.processInfo.environment["PROTO_SHOTS"] else { return }
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        proto.showDebugBar = false
        try? await Task.sleep(for: .seconds(1))
        let states: [GameState] = [.notInstalled, .installing, .ready, .updateAvailable,
                                   .predownloadAvailable, .repairing, .running, .error]
        for v in MainVariant.allCases {
            proto.variant = v
            for s in states {
                proto.state = s
                if s.isTransferring || s == .installing { proto.progress = 0.42 }
                try? await Task.sleep(for: .milliseconds(400))
                if let w = NSApp.windows.first(where: { $0.title.hasPrefix("Yaagl") }) {
                    capture(w, to: url.appending(path: "main-\(v.rawValue)-\(s.rawValue).png"))
                }
            }
        }
        let win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 560),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        for pane in SettingsPane.allCases {
            win.title = pane.rawValue
            win.contentView = NSHostingView(rootView: pane.content.frame(width: 560, height: 560))
            win.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(500))
            capture(win, to: url.appending(path: "settings-\(pane).png"))
        }
        win.title = "Wine"
        win.contentView = NSHostingView(rootView: WineSettings(previewConfirm: true).frame(width: 560, height: 560))
        try? await Task.sleep(for: .milliseconds(800))
        capture(win, to: url.appending(path: "settings-wine-confirm.png"))
        win.orderOut(nil)
        NSApp.terminate(nil)
    }

    /// Real window pixels (materials, button tints) via screencapture.
    static func capture(_ w: NSWindow, to url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
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
