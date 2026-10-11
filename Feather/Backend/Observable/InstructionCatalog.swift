import Foundation
import Combine

struct StoreInstruction: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let steps: [String]
    let bundle_ids: [String]
    let video_url: URL
    let cover_url: URL
    let aspect_ratio: Double
    let is_test: Bool

    static let sample = StoreInstruction(
        id: "technical-playback-test", title: "Знакомство с видеоинструкциями",
        description: "Тестовый ролик для проверки плеера. Настоящие инструкции появятся позже.",
        steps: ["Нажмите на обложку, чтобы включить видео.", "Попробуйте перемотку и полноэкранный режим."],
        bundle_ids: ["net.whatsapp.WhatsApp1"],
        video_url: URL(string: "https://github.com/DzhabaApps/Dzhaba-Apps/releases/download/dr-store-video-instructions/instruction-c8521388-2799-423c-9d2e-e23f160d5ade-video-c579e69c9e793e7fa34a.mp4")!,
        cover_url: URL(string: "https://github.com/DzhabaApps/Dzhaba-Apps/releases/download/dr-store-video-instructions/instruction-c8521388-2799-423c-9d2e-e23f160d5ade-cover-c65db1a83926f2418489.jpg")!,
        aspect_ratio: 0.5625, is_test: true)

    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return false }
        switch url.host {
        case "github.com": return url.path.hasPrefix("/DzhabaApps/Dzhaba-Apps/releases/download/")
        case "json.dzhabaapps.ru", "dzhabaapps.ru": return url.path.hasPrefix("/instruction-media/")
        default: return false
        }
    }
}

struct InstructionIndex: Codable {
    let schema_version: Int
    let instructions: [StoreInstruction]

    static func decode(_ data: Data) throws -> InstructionIndex {
        guard data.count <= 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        let index = try JSONDecoder().decode(Self.self, from: data)
        guard index.schema_version == 1, index.instructions.count <= 100,
              Set(index.instructions.map(\.id)).count == index.instructions.count,
              index.instructions.allSatisfy({ item in
                  !item.id.isEmpty && item.id.count <= 80 && !item.title.isEmpty && item.title.count <= 120
                  && item.description.count <= 4000 && item.steps.count <= 20
                  && item.steps.allSatisfy({ $0.count <= 1000 }) && item.bundle_ids.count <= 100
                  && item.aspect_ratio.isFinite && (0.2...5).contains(item.aspect_ratio)
                  && StoreInstruction.isTrusted(item.video_url) && StoreInstruction.isTrusted(item.cover_url)
              }) else { throw URLError(.cannotParseResponse) }
        return index
    }
}

@MainActor
final class InstructionCatalog: ObservableObject {
    static let shared = InstructionCatalog()
    static let url = URL(string: "https://raw.githubusercontent.com/DzhabaApps/Dzhaba-Apps/main/DRStore-Instructions.json")!
    @Published private(set) var instructions: [StoreInstruction] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let cacheURL = URL.cachesDirectory.appendingPathComponent("dr-store-instructions-v1.json")
    private var loadedAt: Date?

    init(preview: Bool = false) {
        if preview { instructions = [.sample] }
        else if let data = try? Data(contentsOf: cacheURL), let cached = try? InstructionIndex.decode(data) {
            instructions = cached.instructions
        }
    }

    func forApp(_ bundleID: String) -> [StoreInstruction] {
        instructions.filter { $0.bundle_ids.contains(bundleID) }
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || loadedAt == nil || Date().timeIntervalSince(loadedAt!) > 60 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(
                url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let index = try InstructionIndex.decode(data)
            instructions = index.instructions
            loadedAt = Date()
            error = nil
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            self.error = instructions.isEmpty ? "Не удалось загрузить инструкции. Проверьте интернет и попробуйте ещё раз."
                : "Не удалось обновить инструкции. Показываем сохранённые."
        }
    }
}
