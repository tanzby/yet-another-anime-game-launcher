// PROTOTYPE — throwaway. Fake state machine for the main window.
import SwiftUI

enum GameState: String, CaseIterable, Identifiable {
    case wineSetup, notInstalled, installing, installPaused, ready,
         updateAvailable, updating, predownloadAvailable, predownloading,
         repairing, launching, running, error
    var id: String { rawValue }

    var debugName: String {
        switch self {
        case .wineSetup: "准备 Wine"
        case .notInstalled: "未安装"
        case .installing: "安装中"
        case .installPaused: "安装已暂停"
        case .ready: "可启动"
        case .updateAvailable: "有更新"
        case .updating: "更新中"
        case .predownloadAvailable: "可预下载"
        case .predownloading: "预下载中"
        case .repairing: "修复中"
        case .launching: "启动中"
        case .running: "运行中"
        case .error: "出错"
        }
    }

    /// States that advance a fake progress bar.
    var isTransferring: Bool {
        [.wineSetup, .installing, .updating, .predownloading, .repairing].contains(self)
    }
}

enum MainVariant: String, CaseIterable, Identifiable {
    case classic = "A", bottomBar = "B", sidebar = "C"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .classic: "A 经典（复刻 TS 版）"
        case .bottomBar: "B 底部玻璃条"
        case .sidebar: "C 侧边栏"
        }
    }
}

enum SettingsStyle: String, CaseIterable, Identifiable {
    case window = "独立设置窗口（⌘,）"
    case sheet = "主窗口内 sheet"
    var id: String { rawValue }
}

/// What the primary button shows for the current state.
struct PrimaryAction {
    var title: String
    var systemImage: String
    var enabled: Bool
    var tint: Color = .accentColor
}

@Observable @MainActor
final class Proto {
    var state: GameState = .ready { didSet { if oldValue != state { progress = 0 } } }
    var variant: MainVariant = .classic
    var settingsStyle: SettingsStyle = .window
    var showSettingsSheet = false
    var showDebugBar = true
    var progress: Double = 0
    var predownloadDone = false
    var errorMessage = "下载 chunk 7f3a9c… 失败：网络连接已中断（NSURLErrorDomain -1005）。已下载的部分会保留，重试会从断点继续。"

    let installedVersion = "5.8.0"
    let newVersion = "6.0.0"
    let predownloadVersion = "6.1.0"
    let installDir = "~/Games/Genshin Impact"

    init() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(150))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard state.isTransferring else { return }
        progress = min(1, progress + 0.004)
        if progress >= 1 {
            if state == .predownloading { predownloadDone = true }
            state = .ready
        }
    }

    // MARK: fake numbers

    var totalGB: Double {
        switch state {
        case .updating: 12.3
        case .predownloading: 8.2
        case .wineSetup: 0.42
        default: 62.5
        }
    }
    var speedText: String { state == .installPaused ? "已暂停" : "23.4 MB/s" }
    var etaText: String {
        let remaining = (1 - progress) * totalGB * 1024 / 23.4
        let m = Int(remaining / 60)
        return m > 0 ? "剩余约 \(m) 分钟" : "剩余不到 1 分钟"
    }
    var sizeText: String {
        String(format: "%.1f / %.1f GB", progress * totalGB, totalGB)
    }

    var statusText: String {
        switch state {
        case .wineSetup: "正在下载 Wine 11.0-1（CrossOver）…"
        case .installing, .installPaused: "正在下载游戏文件 \(newVersion)"
        case .updating: "正在更新 \(installedVersion) → \(newVersion)"
        case .predownloading: "正在预下载 \(predownloadVersion)"
        case .repairing: "正在校验文件 \(Int(progress * 48213)) / 48213"
        case .launching: "正在启动…"
        case .running: "游戏运行中"
        case .error: "出错了"
        default: ""
        }
    }

    var primary: PrimaryAction {
        switch state {
        case .wineSetup: .init(title: "准备中…", systemImage: "hourglass", enabled: false)
        case .notInstalled: .init(title: "安装游戏", systemImage: "arrow.down.circle.fill", enabled: true)
        case .installing: .init(title: "暂停", systemImage: "pause.fill", enabled: true, tint: .gray)
        case .installPaused: .init(title: "继续", systemImage: "play.fill", enabled: true)
        case .ready, .predownloadAvailable, .predownloading:
            .init(title: "开始游戏", systemImage: "play.fill", enabled: true)
        case .updateAvailable: .init(title: "更新游戏", systemImage: "arrow.triangle.2.circlepath", enabled: true, tint: .orange)
        case .updating: .init(title: "更新中…", systemImage: "hourglass", enabled: false)
        case .repairing: .init(title: "修复中…", systemImage: "wrench.and.screwdriver", enabled: false)
        case .launching: .init(title: "启动中…", systemImage: "hourglass", enabled: false)
        case .running: .init(title: "运行中", systemImage: "gamecontroller.fill", enabled: false, tint: .green)
        case .error: .init(title: "重试", systemImage: "arrow.clockwise", enabled: true, tint: .red)
        }
    }

    /// Fake transitions for the primary button.
    func primaryTapped() {
        switch state {
        case .notInstalled: state = .installing   // real app: folder picker first
        case .installing: state = .installPaused
        case .installPaused: let p = progress; state = .installing; progress = p
        case .ready, .predownloadAvailable, .predownloading: launch()
        case .updateAvailable: state = .updating
        case .error: state = .installing
        default: break
        }
    }

    func launch() {
        state = .launching
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if state == .launching { state = .running }
        }
    }

    func startPredownload() { state = .predownloading }
    func repair() { state = .repairing }
    func forceQuit() { state = .ready }

    var showsProgress: Bool { state.isTransferring || state == .installPaused }
    var showsPredownloadOffer: Bool { state == .predownloadAvailable && !predownloadDone }
}

/// Stand-in for the game's official background art.
struct FakeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 0.85),
                                    Color(red: 0.93, green: 0.78, blue: 0.62)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "mountain.2.fill")
                .resizable().scaledToFit()
                .foregroundStyle(.white.opacity(0.18))
                .padding(.horizontal, 80).offset(y: 120)
            Text("[官方背景图]")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
        }
    }
}

struct GameLogo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("原神").font(.system(size: 44, weight: .heavy, design: .serif))
            Text("GENSHIN IMPACT").font(.caption.weight(.semibold)).tracking(4)
        }
        .foregroundStyle(.white)
        .shadow(radius: 6)
    }
}
