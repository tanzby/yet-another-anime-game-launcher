// PROTOTYPE — throwaway. Three structurally different main windows.
import SwiftUI

struct OpenSettingsButton: View {
    @Environment(Proto.self) private var proto
    @Environment(\.openSettings) private var openSettings
    var label: Bool = false
    var iconSide: CGFloat? = nil
    var body: some View {
        Button {
            if proto.settingsStyle == .window { openSettings() } else { proto.showSettingsSheet = true }
        } label: {
            if label { Label("设置", systemImage: "gearshape") } else {
                Image(systemName: "gearshape.fill").frame(width: iconSide, height: iconSide)
            }
        }
    }
}

struct ProgressBlock: View {
    @Environment(Proto.self) private var proto
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(proto.statusText).font(compact ? .callout : .headline)
            ProgressView(value: proto.progress)
            if proto.state != .repairing {
                HStack {
                    Text(proto.sizeText)
                    Spacer()
                    Text(proto.speedText)
                    Text("·")
                    Text(proto.etaText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - A: classic (mirror of the TS launcher)

struct ClassicMain: View {
    @Environment(Proto.self) private var proto
    var body: some View {
        @Bindable var proto = proto
        ZStack(alignment: .bottom) {
            FakeBackground()
            GameLogo()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(40)
            HStack(alignment: .bottom, spacing: 60) {
                Group {
                    if proto.showsProgress || proto.state == .launching {
                        ProgressBlock()
                            .padding(12)
                            .background(.black.opacity(0.35), in: .rect(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Button(action: proto.primaryTapped) {
                        Text(proto.primary.title).font(.title2.bold()).frame(minWidth: 150).frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(proto.primary.tint)
                    .disabled(!proto.primary.enabled)
                    .popover(isPresented: .constant(proto.showsPredownloadOffer), arrowEdge: .top) {
                        Button("预下载 \(proto.predownloadVersion)（8.2 GB）") { proto.startPredownload() }
                            .buttonStyle(.borderless).padding()
                    }
                    OpenSettingsButton(iconSide: 44)
                        .font(.title2)
                        .buttonStyle(.borderedProminent).tint(.white.opacity(0.85)).foregroundStyle(.black)
                        .disabled(proto.state == .running)
                }
                .controlSize(.extraLarge)
            }
            .padding(.horizontal, 60).padding(.bottom, 40)
        }
        .alert("出错了", isPresented: .constant(proto.state == .error)) {
            Button("重试") { proto.primaryTapped() }
            Button("取消", role: .cancel) { proto.state = .notInstalled }
        } message: { Text(proto.errorMessage) }
    }
}

// MARK: - B: full-width glass bottom bar, notices as cards top-right

struct BottomBarMain: View {
    @Environment(Proto.self) private var proto
    var body: some View {
        ZStack {
            FakeBackground()
            GameLogo()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(32)
            notices
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }

    @ViewBuilder var notices: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if proto.state == .error {
                card(icon: "exclamationmark.triangle.fill", tint: .red, title: "下载失败", body: proto.errorMessage) {
                    Button("重试") { proto.primaryTapped() }
                    Button("查看日志") {}
                }
            }
            if proto.state == .updateAvailable {
                card(icon: "arrow.triangle.2.circlepath", tint: .orange, title: "新版本 \(proto.newVersion)",
                     body: "需要下载 12.3 GB。更新前无法启动游戏。") { EmptyView() }
            }
            if proto.showsPredownloadOffer {
                card(icon: "tray.and.arrow.down.fill", tint: .green, title: "\(proto.predownloadVersion) 可预下载",
                     body: "8.2 GB，后台下载，不影响游戏。") {
                    Button("开始预下载") { proto.startPredownload() }
                    Button("稍后") { proto.predownloadDone = true }
                }
            }
            if proto.predownloadDone && proto.state == .ready {
                card(icon: "checkmark.seal.fill", tint: .green, title: "\(proto.predownloadVersion) 预下载完成",
                     body: "新版本上线后只需几分钟即可更新。") { EmptyView() }
            }
        }
        .frame(width: 300)
    }

    func card<A: View>(icon: String, tint: Color, title: String, body: String,
                       @ViewBuilder actions: () -> A) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
            Text(body).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack { actions() }.controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    var bar: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("原神 · 国服").font(.headline)
                Text(proto.state == .notInstalled ? "未安装" : "版本 \(proto.installedVersion) · 62.4 GB")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .leading)
            Group {
                if proto.showsProgress { ProgressBlock(compact: true) }
                else if proto.state == .running {
                    Label("游戏运行中 · 已运行 00:12:34", systemImage: "gamecontroller").foregroundStyle(.secondary)
                } else if proto.state == .launching {
                    HStack { ProgressView().controlSize(.small); Text("正在启动 Wine…") }
                } else { Spacer() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if proto.state == .running {
                    Button("强制结束", role: .destructive) { proto.forceQuit() }
                }
                Button(action: proto.primaryTapped) {
                    Label(proto.primary.title, systemImage: proto.primary.systemImage)
                        .font(.title3.bold()).frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent).tint(proto.primary.tint)
                .disabled(!proto.primary.enabled)
                Menu {
                    Button("检查文件完整性") { proto.repair() }
                    Button("打开游戏目录") {}
                    Button("打开 Wine 命令行") {}
                    Divider()
                    OpenSettingsButton(label: true)
                } label: { Image(systemName: "ellipsis") }
                .menuIndicator(.hidden).fixedSize()
            }
            .controlSize(.extraLarge)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
}

// MARK: - C: sidebar with game info, actions and a task list

struct SidebarMain: View {
    @Environment(Proto.self) private var proto
    var body: some View {
        NavigationSplitView {
            List {
                Section("原神 · 国服") {
                    LabeledContent("已安装", value: proto.state == .notInstalled ? "—" : proto.installedVersion)
                    LabeledContent("最新", value: proto.newVersion)
                    LabeledContent("占用", value: "62.4 GB")
                }
                Section("任务") {
                    if proto.showsProgress {
                        ProgressBlock(compact: true).padding(.vertical, 4)
                    } else if proto.showsPredownloadOffer {
                        Button("预下载 \(proto.predownloadVersion)（8.2 GB）", systemImage: "tray.and.arrow.down") {
                            proto.startPredownload()
                        }
                    } else {
                        Text("无").foregroundStyle(.secondary)
                    }
                }
                if proto.state == .error {
                    Section("错误") {
                        Label(proto.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                }
                Section("操作") {
                    Button("检查文件完整性", systemImage: "checkmark.shield") { proto.repair() }
                    Button("打开游戏目录", systemImage: "folder") {}
                    Button("打开 Wine 命令行", systemImage: "terminal") {}
                    OpenSettingsButton(label: true)
                }
                .buttonStyle(.borderless)
            }
            .navigationSplitViewColumnWidth(260)
        } detail: {
            ZStack(alignment: .bottom) {
                FakeBackground()
                GameLogo()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(32)
                VStack(spacing: 8) {
                    Button(action: proto.primaryTapped) {
                        Label(proto.primary.title, systemImage: proto.primary.systemImage)
                            .font(.title.bold()).frame(minWidth: 220, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent).tint(proto.primary.tint)
                    .controlSize(.extraLarge)
                    .disabled(!proto.primary.enabled)
                    if proto.state == .running {
                        Button("强制结束游戏") { proto.forceQuit() }.buttonStyle(.link).foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 48)
            }
            .ignoresSafeArea()
        }
    }
}
