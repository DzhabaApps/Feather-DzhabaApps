import SwiftUI
import NukeUI
import AVKit
import Combine

@MainActor
final class InstructionPlayback: ObservableObject {
    private static weak var active: InstructionPlayback?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var error: String?
    private var observation: NSKeyValueObservation?

    func start(_ url: URL) {
        Self.active?.stop()
        stop()
        guard StoreInstruction.isTrusted(url) else { error = "Видео недоступно."; return }
        error = nil
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 5
        let player = AVPlayer(playerItem: item)
        self.player = player
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
    func stop() {
        if Self.active === self { Self.active = nil }
        observation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
    deinit { player?.pause() }
}

private struct InlineInstructionPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}

struct InstructionVideoCard: View {
    let instruction: StoreInstruction
    @StateObject private var playback = InstructionPlayback()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if instruction.is_test {
                Label("Тестовое видео", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(instruction.title).font(.headline)
            ZStack {
                Color.black
                if let player = playback.player, playback.error == nil {
                    InlineInstructionPlayer(player: player)
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
        .onDisappear { playback.stop() }
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
