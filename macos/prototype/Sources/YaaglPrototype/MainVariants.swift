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

// MARK: - B (chosen): floating Liquid Glass bar, events as system notifications

struct BottomBarMain: View {
    @Environment(Proto.self) private var proto
    var body: some View {
        ZStack(alignment: .bottom) {
            FakeBackground().ignoresSafeArea()
            notices
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 52).padding(.trailing, 20)
            bar.padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    /// Events go to macOS Notification Center (UNUserNotificationCenter in
    /// the real app). `swift run` has no bundle, so this draws a stand-in.
    @ViewBuilder var notices: some View {
        if let n = systemNotification {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.title2).foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.blue.gradient, in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text("Yaagl").font(.headline); Spacer(); Text("现在").font(.caption).foregroundStyle(.secondary) }
                        Text(n.title).font(.callout.weight(.semibold))
                        Text(n.body).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(14)
                .frame(width: 340)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                Text("[示意] macOS 系统通知，窗口在后台也会弹出")
                    .font(.caption2).foregroundStyle(.white.opacity(0.85)).shadow(radius: 2)
            }
        }
    }

    var systemNotification: (title: String, body: String)? {
        switch proto.state {
        case .updateAvailable: ("原神 \(proto.newVersion) 已发布", "需要下载 12.3 GB，更新后才能启动游戏。")
        case .predownloadAvailable: ("\(proto.predownloadVersion) 可以预下载了", "8.2 GB，后台下载，不影响游戏。")
        case .error: ("下载失败", "网络连接已中断。已下载的部分会保留，重试会从断点继续。")
        default: nil
        }
    }

    /// Persistent state stays in the window; notifications are transient.
    @ViewBuilder var status: some View {
        if proto.showsProgress {
            ProgressBlock(compact: true)
        } else {
            switch proto.state {
            case .running:
                Label("游戏运行中 · 已运行 00:12:34", systemImage: "gamecontroller").foregroundStyle(.secondary)
            case .launching:
                HStack { ProgressView().controlSize(.small); Text("正在启动 Wine…") }
            case .updateAvailable:
                Label("新版本 \(proto.newVersion) · 需下载 12.3 GB", systemImage: "arrow.down.circle")
            case .predownloadAvailable:
                HStack(spacing: 10) {
                    Label("\(proto.predownloadVersion) 可预下载 · 8.2 GB", systemImage: "tray.and.arrow.down")
                    Button("预下载") { proto.startPredownload() }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            case .error:
                HStack(spacing: 10) {
                    Label("下载失败：网络连接已中断，进度已保留", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).lineLimit(1)
                    Button("查看日志") {}.buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            default:
                Text("需要约 62.5 GB 可用空间").foregroundStyle(.secondary)
            }
        }
    }

    /// Whether the bar has something to say besides its buttons.
    var hasStatus: Bool { proto.state != .ready }

    /// One glass capsule: status (when there is any) + primary button + ⋯.
    /// It shrinks to just the buttons when idle and grows leftwards when a
    /// download, update notice or error appears.
    var bar: some View {
        HStack(spacing: 14) {
            if hasStatus {
                status
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            Button(action: proto.primaryTapped) {
                Label(proto.primary.title, systemImage: proto.primary.systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 132, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(proto.primary.tint)
            .disabled(!proto.primary.enabled)

            Menu {
                Button("检查文件完整性", systemImage: "checkmark.shield") { proto.repair() }
                Button("打开游戏目录", systemImage: "folder") {}
                Button("打开 Wine 命令行", systemImage: "terminal") {}
                Divider()
                OpenSettingsButton(label: true)
            } label: {
                Image(systemName: "ellipsis").font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(8)
        .frame(maxWidth: hasStatus ? .infinity : nil)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.smooth, value: hasStatus)
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
