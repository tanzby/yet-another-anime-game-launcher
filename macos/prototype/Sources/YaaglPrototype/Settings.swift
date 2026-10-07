// PROTOTYPE — throwaway. Settings pages, items mirror src/config + hk4e/config.
// All values are local @State; nothing is saved.
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "通用", game = "游戏", wine = "Wine", advanced = "高级", about = "关于"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .game: "gamecontroller"
        case .wine: "wineglass"
        case .advanced: "exclamationmark.triangle"
        case .about: "info.circle"
        }
    }
    @MainActor @ViewBuilder var content: some View {
        switch self {
        case .general: GeneralSettings()
        case .game: GameSettings()
        case .wine: WineSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        }
    }
}

/// Style 1: a separate Settings window with toolbar tabs (⌘,).
struct SettingsWindow: View {
    var body: some View {
        TabView {
            ForEach(SettingsPane.allCases) { pane in
                Tab(pane.rawValue, systemImage: pane.icon) { pane.content }
            }
        }
        .frame(width: 560, height: 520)
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

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Yaagl", value: "1.0.0 (prototype)")
                LabeledContent("Wine", value: "11.0-1 CrossOver")
                LabeledContent("DXMT", value: "v0.70")
            }
            Section("开源许可") {
                DisclosureGroup("steam.exe 与 lsteamclient.dll（Valve, BSD-3-Clause）") {
                    Text("Copyright (c) 2015-2022 Valve Corporation. All rights reserved. …").font(.caption)
                }
                DisclosureGroup("Sparkle（MIT）") { Text("…").font(.caption) }
            }
        }
        .formStyle(.grouped)
    }
}
