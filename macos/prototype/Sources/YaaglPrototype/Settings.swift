// PROTOTYPE — throwaway. Settings pages, items mirror src/config + hk4e/config.
// All values are local @State; nothing is saved.
import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "通用", game = "游戏", wine = "Wine", advanced = "高级"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .game: "gamecontroller"
        case .wine: "wineglass"
        case .advanced: "exclamationmark.triangle"
        }
    }
    @MainActor @ViewBuilder var content: some View {
        switch self {
        case .general: GeneralSettings()
        case .game: GameSettings()
        case .wine: WineSettings()
        case .advanced: AdvancedSettings()
        }
    }
}

/// Style 1 (chosen): a separate Settings window (⌘,) with a sidebar,
/// like macOS System Settings.
@Observable @MainActor
final class SettingsNav {
    static let shared = SettingsNav()
    var pane: SettingsPane? = .general
    var previewWineConfirm = false
}

struct SettingsWindow: View {
    @Bindable private var nav = SettingsNav.shared
    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $nav.pane) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                if nav.pane == .wine && nav.previewWineConfirm { WineSettings(previewConfirm: true) }
                else { (nav.pane ?? .general).content }
            }
            .navigationTitle(nav.pane?.rawValue ?? "")
        }
        .frame(width: 760, height: 540)
    }
}

/// Style 2: a sheet over the main window with a sidebar.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pane: SettingsPane? = .general
    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            (pane ?? .general).content
                .toolbar { Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .frame(width: 760, height: 540)
    }
}

struct GeneralSettings: View {
    @State private var language = "跟随系统"
    @State private var proxy = false
    @State private var proxyHost = "127.0.0.1:7890"
    @State private var autoUpdate = true
    @State private var metalHUD = false
    @State private var retina = true
    @State private var leftCmd = true
    var body: some View {
        Form {
            Section("游戏") {
                LabeledContent("安装位置") {
                    HStack {
                        Text("~/Games/Genshin Impact").foregroundStyle(.secondary)
                        Button("在访达中显示") {}
                        Button("更改…") {}
                    }
                }
                Button("检查文件完整性…") {}
            }
            Section("显示与输入") {
                Toggle("Retina 模式", isOn: $retina)
                Toggle("Metal HUD", isOn: $metalHUD)
                Toggle("把左 ⌘ 键映射为 Ctrl", isOn: $leftCmd)
            }
            Section {
                Toggle("为游戏启用 HTTP 代理", isOn: $proxy)
                TextField("代理地址", text: $proxyHost).disabled(!proxy)
            } header: { Text("网络") } footer: {
                Text("代理只作用于游戏，不影响启动器本身。").font(.caption).foregroundStyle(.secondary)
            }
            Section("启动器") {
                Picker("界面语言", selection: $language) {
                    Text("跟随系统").tag("跟随系统")
                    Text("简体中文").tag("简体中文")
                    Text("English").tag("English")
                }
                Toggle("自动检查更新", isOn: $autoUpdate)
                LabeledContent("版本 1.0.0 (prototype)") { Button("检查更新…") {} }
                LabeledContent("数据目录") { Button("打开 Yaagl 数据目录") {} }
                Button("恢复推荐设置") {}
            }
        }
        .formStyle(.grouped)
    }
}

struct GameSettings: View {
    @State private var gameMode = true
    @State private var hdr = false
    @State private var metalFX = false
    @State private var customRes = false
    @State private var width = "2560"
    @State private var height = "1600"
    @State private var steamPatch = true
    @State private var timeoutFix = true
    @State private var blockNet = false
    @State private var patchOff = false
    var body: some View {
        Form {
            Section("画面") {
                Toggle(isOn: $gameMode) {
                    Text("原生全屏 + 游戏模式")
                    Text("全屏时覆盖刘海区域，并启用 macOS 游戏模式。")
                }
                Toggle("HDR", isOn: $hdr)
                Toggle(isOn: $metalFX) {
                    Text("MetalFX 超分")
                    Text("以一半分辨率渲染，再放大到 Retina 输出。")
                }
                Toggle("自定义分辨率", isOn: $customRes)
                if customRes {
                    HStack {
                        TextField("宽", text: $width).frame(width: 80)
                        Text("×")
                        TextField("高", text: $height).frame(width: 80)
                    }
                }
            }
            Section("兼容性修复") {
                Toggle("Steam 补丁", isOn: $steamPatch)
                Toggle("Timeout Fix", isOn: $timeoutFix)
                Toggle("Launch Fix（屏蔽 hosts）", isOn: $blockNet)
                Toggle("关闭 AC 补丁", isOn: $patchOff)
            }
        }
        .formStyle(.grouped)
    }
}

struct WineSettings: View {
    /// Snapshot mode opens the confirmation directly.
    var previewConfirm = false
    @State private var installed = "11.0-1-crossover-signed-experimental"
    @State private var selection = "11.0-1-crossover-signed-experimental"
    @State private var confirming = false
    var body: some View {
        Form {
            Section {
                // Picking a version asks right away; no separate "apply" button.
                Picker("Wine 版本", selection: $selection) {
                    Text("11.0-1 CrossOver（推荐）").tag("11.0-1-crossover-signed-experimental")
                    Text("10.4 CrossOver").tag("10.4")
                }
                .onChange(of: selection) { _, new in if new != installed { confirming = true } }
            } footer: {
                Text("切换会重新下载 Wine 并重建前缀，大约需要几分钟。").font(.caption).foregroundStyle(.secondary)
            }
            Section("工具") {
                Button("打开 Wine 命令行") {}
                Button("在访达中显示 Wine 前缀") {}
            }
        }
        .formStyle(.grouped)
        .onAppear { if previewConfirm { selection = "10.4"; confirming = true } }
        .alert("切换到 10.4 CrossOver？", isPresented: $confirming) {
            Button("切换并重启 Yaagl") { installed = selection }
            Button("取消", role: .cancel) { selection = installed }
        } message: {
            Text("会重新下载 Wine（约 420 MB）并重建前缀，游戏文件不受影响。切换期间不能启动游戏。")
        }
    }
}

struct AdvancedSettings: View {
    @State private var fps = "不解锁"
    @State private var reshade = false
    var body: some View {
        Form {
            Section {
                Label("在不清楚作用的情况下，请不要改动这里的设置。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Section {
                Picker("帧率限制解锁", selection: $fps) {
                    ForEach(["不解锁", "120", "144", "165", "240"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("ReShade", isOn: $reshade)
            }
        }
        .formStyle(.grouped)
    }
}

/// "关于 Yaagl" uses the system's standard About panel; licenses go in
/// its credits. No custom window.
@MainActor
enum About {
    static func show() {
        let credits = NSAttributedString(
            string: "Wine 11.0-1 CrossOver · DXMT v0.70\n\n开源许可\nsteam.exe 与 lsteamclient.dll — Valve, BSD-3-Clause\nSparkle — MIT",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Yaagl",
            .applicationVersion: "1.0.0",
            .version: "prototype",
            .credits: credits,
        ])
    }
}
