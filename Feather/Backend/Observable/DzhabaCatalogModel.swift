import Foundation
import Combine
import AltSourceKit

@MainActor
final class DzhabaCatalogModel: ObservableObject {
    static let url = URL(string: "https://raw.githubusercontent.com/DzhabaApps/Dzhaba-Apps/refs/heads/main/DzhabaApps.json")!
    @Published private(set) var repository: ASRepository?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let cacheURL = URL.cachesDirectory.appendingPathComponent("dzhabaapps-catalog-v1.json")
    init(preview: Bool = false) {
        let url = preview ? Bundle.main.url(forResource: "CatalogPreview", withExtension: "json") : cacheURL
        if let url, let data = try? Data(contentsOf: url) {
            repository = try? JSONDecoder().decode(ASRepository.self, from: data)
        }
    }
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 8 * 1024 * 1024 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(ASRepository.self, from: data)
            repository = decoded
            error = nil
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            self.error = repository == nil
                ? "Не удалось загрузить магазин. Проверьте интернет и попробуйте ещё раз."
                : "Не удалось обновить каталог. Показываем сохранённые приложения."
        }
    }
}
