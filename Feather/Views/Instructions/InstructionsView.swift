import SwiftUI
import NukeUI
import AVKit
import Combine

@MainActor
final class InstructionPlayback: ObservableObject {
    private static weak var active: InstructionPlayback?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var error: String?
    @Published private(set) var time = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var playing = false
    @Published private(set) var buffering = false
    @Published var fullScreen = false
    var fullScreenVisible = false
    private var timeObserver: Any?
    private var observation: NSKeyValueObservation?
    private var resourceLoader: InstructionResourceLoader?
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
        buffering = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.time = max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0)
                let length = player.currentItem?.duration.seconds ?? 0
                self.duration = length.isFinite ? max(0, length) : 0
                self.playing = player.rate > 0
                self.buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
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
    func toggle() { if player?.rate == 0 { player?.play() } else { pause() } }
    func seek(_ seconds: Double, resume: Bool) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: CMTime(seconds: 0.15, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.15, preferredTimescale: 600)) { [weak self] finished in
            Task { @MainActor [weak self] in if finished && resume { self?.player?.play() } }
        }
    }
    func leaveInline() { if !fullScreen { stop() } }
    func stop() {
        if Self.active === self { Self.active = nil }
        observation = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        resourceLoader?.invalidate()
        resourceLoader = nil
        time = 0; duration = 0; playing = false; buffering = false
    }
}

private final class InstructionLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct InstructionPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> InstructionLayerView {
        let view = InstructionLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: InstructionLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
    static func dismantleUIView(_ view: InstructionLayerView, coordinator: ()) {
        // Detach only the rendering surface. The shared playback model owns the item.
        view.playerLayer.player = nil
    }
}

private struct InstructionPlayerSurface: View {
    @ObservedObject var playback: InstructionPlayback
    let expanded: Bool
    @State private var scrub: Double?
    @State private var resumeAfterScrub = false
    private func stamp(_ value: Double) -> String { let value = Int(max(0, value)); return String(format: "%d:%02d", value / 60, value % 60) }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = playback.player { InstructionPlayerLayer(player: player).ignoresSafeArea(edges: expanded ? .all : []) }
            if playback.buffering { ProgressView().tint(.white).accessibilityLabel("Загрузка видео") }
            VStack {
                HStack {
                    Spacer()
                    Button { playback.fullScreen = !expanded } label: {
                        Image(systemName: expanded ? "xmark" : "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold)).padding(13).background(.black.opacity(0.55), in: Circle())
                    }.accessibilityLabel(expanded ? "Закрыть полный экран" : "На весь экран")
                        .accessibilityIdentifier(expanded ? "instruction-close-fullscreen" : "instruction-fullscreen")
                }
                Spacer()
                VStack(spacing: 6) {
                    Slider(value: Binding(get: { scrub ?? min(playback.time, max(1, playback.duration)) }, set: { scrub = $0 }), in: 0...max(1, playback.duration)) { editing in
                        if editing { resumeAfterScrub = playback.player?.rate != 0; playback.pause() }
                        else if let target = scrub { playback.seek(target, resume: resumeAfterScrub); scrub = nil }
                    }.tint(.white).disabled(playback.duration <= 0).accessibilityLabel("Позиция видео")
                    HStack {
                        Button { playback.toggle() } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill").frame(width: 32, height: 32) }
                            .accessibilityLabel(playback.playing ? "Пауза" : "Воспроизвести")
                        Text("\(stamp(scrub ?? playback.time)) / \(stamp(playback.duration))").font(.caption.monospacedDigit())
                        Spacer()
                    }
                }.padding(10).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }.padding(expanded ? 20 : 10).foregroundStyle(.white)
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
                if let player = playback.player, playback.error == nil {
                    if !playback.fullScreen { InstructionPlayerSurface(playback: playback, expanded: false) }
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
                    }.buttonStyle(.plain).accessibilityLabel("Смотреть видео: \(instruction.title)")
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
        .fullScreenCover(isPresented: $playback.fullScreen) {
            InstructionPlayerSurface(playback: playback, expanded: true)
                .onAppear { playback.fullScreenVisible = true }
                .onDisappear { playback.fullScreenVisible = false }
        }
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
