import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum GameDataSource {
    static let blockSize: Int64 = 256 * 1024 * 1024

    struct Metadata: Decodable {
        let type: String
        let name: String
        let size: Int64?
    }

    private struct DownloadLink: Decodable {
        let href: URL
    }

    static func accepts(_ url: URL) -> Bool {
        secure(url) && ["disk.yandex.ru", "yadi.sk"].contains(url.host?.lowercased() ?? "")
            && url.path.hasPrefix("/d/") && url.pathComponents.count == 3
    }

    private static func secure(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil
    }

    static func acceptsDownload(_ url: URL?) -> Bool {
        guard let url, secure(url), let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".storage.yandex.net") || host.hasSuffix(".disk.yandex.ru")
            || host.hasSuffix(".disk.yandex.net")
    }

    static func safeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\")
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static func resolve(_ url: URL) async throws -> (Metadata, URL) {
        guard accepts(url) else { throw URLError(.unsupportedURL) }
        let metadata = try await fetch(Metadata.self, share: url, endpoint: "")
        guard metadata.type == "file" else { throw Failure.folder }
        guard let size = metadata.size, size > 0, safeName(metadata.name) else { throw Failure.changed }
        let link = try await fetch(DownloadLink.self, share: url, endpoint: "/download")
        guard acceptsDownload(link.href) else { throw URLError(.badServerResponse) }
        return (metadata, link.href)
    }

    private static func fetch<T: Decodable>(_ type: T.Type, share: URL, endpoint: String) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "cloud-api.yandex.net"
        components.path = "/v1/disk/public/resources" + endpoint
        components.queryItems = [URLQueryItem(name: "public_key", value: share.absoluteString)]
        guard let url = components.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.url?.host == components.host else { throw URLError(.badServerResponse) }
        if http.statusCode == 429 { throw Failure.rateLimited }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(type, from: data)
    }

    static func range(from offset: Int64, size: Int64) -> ClosedRange<Int64>? {
        guard offset >= 0, offset < size else { return nil }
        return offset...(offset + min(blockSize, size - offset) - 1)
    }

    static func checkedETag(_ response: HTTPURLResponse, range: ClosedRange<Int64>, size: Int64,
                            previous: String?) throws -> String {
        if response.statusCode == 412 { throw Failure.changed }
        let expected = "bytes \(range.lowerBound)-\(range.upperBound)/\(size)"
        guard response.statusCode == 206,
              response.value(forHTTPHeaderField: "Content-Range") == expected,
              let etag = response.value(forHTTPHeaderField: "ETag"),
              etag.hasPrefix("\""), etag.hasSuffix("\"") else { throw URLError(.badServerResponse) }
        guard previous == nil || previous == etag else { throw Failure.changed }
        return etag
    }

    enum Failure: LocalizedError {
        case folder, changed, rateLimited

        var errorDescription: String? {
            switch self {
            case .folder: return "Для загрузки нужна ссылка на один файл, например ZIP."
            case .changed: return "Файл на Яндекс Диске изменился. Удали старую загрузку и начни заново."
            case .rateLimited: return "Яндекс Диск временно ограничил выдачу ссылок. Попробуй чуть позже."
            }
        }
    }
}
