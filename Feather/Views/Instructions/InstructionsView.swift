import SwiftUI
import NukeUI
import AVKit
import Combine

@MainActor
final class InstructionPlayback: ObservableObject {
    private static weak var active: InstructionPlayback?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var error: String?
    private(set) var time = 0.0
    private(set) var duration = 0.0
    var fullScreen = false
    var fullScreenVisible = false
    var inlineVisible = false
    var controller: AVPlayerViewController?
    var controllerDelegate: NSObject?
    private var timeObserver: Any?
    private var observation: NSKeyValueObservation?
    private var resourceLoader: InstructionResourceLoader?
    private var diagnosticLabel: UILabel?
    var transportDiagnostics: [String: Int] { resourceLoader?.diagnostics ?? [:] }

    func start(_ url: URL) {
        Self.active?.stop()
        stop()
        guard StoreInstruction.isTrusted(url) else { error = "Видео недоступно."; return }
        error = nil
        let loader = InstructionResourceLoader(url: url)
        resourceLoader = loader
        let item = AVPlayerItem(asset: loader.makeAsset())
        item.preferredForwardBufferDuration = 5
        let player = AVPlayer(playerItem: item)
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self, weak player] _ in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player else { return }
                let seconds = player.currentTime().seconds
                self.time = seconds.isFinite ? max(0, seconds) : 0
                let length = player.currentItem?.duration.seconds ?? 0
                self.duration = length.isFinite ? max(0, length) : 0
                self.updateDiagnostics()
            }
        }
        Self.active = self
        observation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            if item.status == .failed {
                Task { @MainActor [weak self] in
                    guard self?.player?.currentItem === item else { return }
                    self?.error = "Не удалось открыть видео. Проверьте интернет и попробуйте ещё раз."
                }
            }
        }
        player.play()
    }

    func pause() { player?.pause() }
    func leaveInline() {
        inlineVisible = false
        // AVKit presents its own fullscreen controller. That presentation can
        // disappear/dismantle the SwiftUI host without ending this playback session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.inlineVisible, !self.fullScreen else { return }
            self.stop()
        }
    }
    func attachDiagnostics(to controller: AVPlayerViewController) {
        guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview" else { return }
        controller.contentOverlayView?.subviews.filter { $0.accessibilityIdentifier == "instruction-ui-state" }.forEach { $0.removeFromSuperview() }
        let label = UILabel(frame: CGRect(x: 1, y: 1, width: 2, height: 2))
        label.text = " "
        label.textColor = .clear
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "instruction-ui-state"
        label.accessibilityLabel = "Playback diagnostics"
        controller.contentOverlayView?.addSubview(label)
        diagnosticLabel = label
        updateDiagnostics()
    }
    private func updateDiagnostics() {
        guard let diagnosticLabel else { return }
        let state: [String: Any] = ["time": time, "duration": duration, "rate": player?.rate ?? 0,
            "fullscreen": fullScreen, "ready": player?.currentItem?.status == .readyToPlay,
            "item": player?.currentItem.map { String(ObjectIdentifier($0).hashValue) } ?? "none"]
        if let data = try? JSONSerialization.data(withJSONObject: state), let value = String(data: data, encoding: .utf8) {
            diagnosticLabel.accessibilityValue = value
        }
    }
    func stop() {
        if Self.active === self { Self.active = nil }
        observation = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        controller?.player = nil
        controller?.delegate = nil
        controller = nil; controllerDelegate = nil; diagnosticLabel = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        resourceLoader?.invalidate()
        resourceLoader = nil
        time = 0; duration = 0
    }
}

@MainActor
private struct InstructionNativePlayer: UIViewControllerRepresentable {
    let playback: InstructionPlayback
    func makeCoordinator() -> Coordinator { Coordinator(playback) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = playback.player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        controller.delegate = context.coordinator
        playback.controller = controller
        playback.controllerDelegate = context.coordinator
        controller.loadViewIfNeeded()
        playback.attachDiagnostics(to: controller)
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== playback.player {
            controller.player = playback.player
            controller.delegate = context.coordinator
            playback.controller = controller
            playback.controllerDelegate = context.coordinator
            playback.attachDiagnostics(to: controller)
        }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        // The session retains both controller and delegate across AVKit fullscreen
        // transitions. Only leaving the instruction releases the player's item.
    }
    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        weak var playback: InstructionPlayback?
        init(_ playback: InstructionPlayback) { self.playback = playback }
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            playback?.fullScreen = true
            coordinator.animate(alongsideTransition: nil) { [playback = self.playback] transition in
                playback?.fullScreen = !transition.isCancelled
                playback?.fullScreenVisible = !transition.isCancelled
            }
        }
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            // AVKit can pause while collapsing; restore the prior transport state.
            let resume = (playerViewController.player?.rate ?? 0) > 0
            coordinator.animate(alongsideTransition: nil) { [playback = self.playback] transition in
                guard !transition.isCancelled else { return }
                playback?.fullScreen = false
                playback?.fullScreenVisible = false
                if resume { playerViewController.player?.play() }
            }
        }
    }
}

@MainActor
struct InstructionVideoCard: View {
    let instruction: StoreInstruction
    @StateObject private var playback: InstructionPlayback
    @Environment(\.scenePhase) private var scenePhase
    init(instruction: StoreInstruction, playback: InstructionPlayback? = nil) {
        self.instruction = instruction
        _playback = StateObject(wrappedValue: playback ?? InstructionPlayback())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if instruction.is_test {
                Label("Тестовое видео", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(instruction.title).font(.headline)
            ZStack {
                Color.black
                if playback.player != nil, playback.error == nil {
                    InstructionNativePlayer(playback: playback)
                } else {
                    Button {
                        playback.start(instruction.video_url)
                    } label: {
                        ZStack {
                            LazyImage(url: instruction.cover_url) { state in
                                if let image = state.image { image.resizable().scaledToFit() }
                                else { Color(red: 0.16, green: 0.13, blue: 0.23) }
                            }
                            Image(systemName: "play.circle.fill").font(.system(size: 58))
                                .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.5))
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Смотреть видео: \(instruction.title)").accessibilityIdentifier("instruction-start")
                }
            }
            .frame(height: instruction.aspect_ratio < 1 ? 330 : 205)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            if let error = playback.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Попробовать ещё раз") { playback.start(instruction.video_url) }
            }
            if !instruction.description.isEmpty { Text(instruction.description).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(instruction.steps.enumerated()), id: \.offset) { offset, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(offset + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(.quaternary, in: Circle())
                    Text(step).font(.subheadline)
                }
            }
        }
        .onAppear { playback.inlineVisible = true }
        .onDisappear { playback.leaveInline() }
        .onChange(of: scenePhase) { phase in if phase != .active { playback.pause() } }
    }
}

struct AppInstructionsBlock: View {
    let bundleID: String
    @ObservedObject private var catalog = InstructionCatalog.shared
    var body: some View {
        if !catalog.forApp(bundleID).isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Видеоинструкции").font(.title3.weight(.semibold))
                ForEach(catalog.forApp(bundleID)) { InstructionVideoCard(instruction: $0) }
                Divider()
            }.padding(.vertical, 8)
        }
    }
}

struct InstructionsView: View {
    private let preview: Bool
    @StateObject private var catalog: InstructionCatalog
    @State private var search = ""
    @State private var scope = 0
    init(preview: Bool = false) {
        self.preview = preview
        _catalog = StateObject(wrappedValue: preview ? InstructionCatalog(preview: true) : .shared)
    }

    private var filtered: [StoreInstruction] {
        catalog.instructions.filter { item in
            (scope == 0 || (scope == 1 ? item.bundle_ids.isEmpty : !item.bundle_ids.isEmpty))
                && (search.isEmpty || (item.title + " " + item.description).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Короткие видео помогут разобраться с установкой и настройкой приложений.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("Тип инструкций", selection: $scope) {
                        Text("Все").tag(0); Text("Общие").tag(1); Text("Приложения").tag(2)
                    }.pickerStyle(.segmented)
                    if let error = catalog.error {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Обновить") { Task { await catalog.load(force: true) } }
                    }
                    if catalog.isLoading && catalog.instructions.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                    else if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                            Text(search.isEmpty ? "Здесь появятся инструкции" : "Ничего не найдено").font(.headline)
                        }.frame(maxWidth: .infinity).padding(.vertical, 50)
                    }
                    ForEach(filtered) { item in
                        NavigationLink {
                            ScrollView { InstructionVideoCard(instruction: item).padding() }
                                .navigationTitle("Инструкция").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack(spacing: 14) {
                                LazyImage(url: item.cover_url) { state in
                                    if let image = state.image { image.resizable().scaledToFill() }
                                    else { Color.secondary.opacity(0.12) }
                                }.frame(width: 76, height: 98).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.headline).foregroundStyle(.primary)
                                    Text(item.is_test ? "Тестовое видео" : (item.bundle_ids.isEmpty ? "Общая инструкция" : "Для приложения"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }.padding(12).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }
            .navigationTitle("Инструкции")
            .searchable(text: $search, prompt: "Найти инструкцию")
            .refreshable { await catalog.load(force: true) }
            .task { if !preview { await catalog.load() } }
        }
    }
}
