import Foundation

struct InstallAuthorization: Sendable {
    let accessID: String
    let credential: String
    let installationID: String
}
struct InstallManifest: Decodable, Sendable {
    let id: String
    let expires_at: Double
    let manifest_url: URL
    let page_url: URL
    var installationURL: URL? {
        guard let encoded = manifest_url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "itms-services://?action=download-manifest&url=" + encoded)
    }
}
enum InstallManifestError: LocalizedError {
    case unavailable, invalidResponse, expired, busy, timeout
    var errorDescription: String? {
        switch self {
        case .unavailable: "Не удалось связаться с сервером установки. Проверьте интернет и попробуйте ещё раз."
        case .invalidResponse: "Не удалось подготовить установку. Попробуйте ещё раз."
        case .expired: "Срок запроса установки закончился. Нажмите «Установить» ещё раз."
        case .busy: "Установка пока недоступна. Подождите несколько секунд и попробуйте ещё раз."
        case .timeout: "iPhone не завершил установку. Проверьте свободное место и повторите попытку."
        }
    }
}
private final class ManifestSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
actor InstallManifestClient {
    static let endpoint = URL(string: "https://dzhabaapps.ru/api/install-manifest")!
    private let endpoint: URL
    private let session: URLSession
    init(endpoint: URL = InstallManifestClient.endpoint, session: URLSession? = nil) {
        self.endpoint = endpoint
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }
    func prepare(id: UUID, port: Int, bundleID: String, version: String, title: String,
                 authorization: InstallAuthorization) async throws -> InstallManifest {
        guard (4000...8000).contains(port), !bundleID.isEmpty else { throw InstallManifestError.invalidResponse }
        var request = URLRequest(url: endpoint.appendingPathComponent("jobs"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer " + authorization.credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "port": port,
            "bundle": bundleID, "version": version, "title": title,
            "access_id": authorization.accessID, "installation_id": authorization.installationID])
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request, delegate: ManifestSessionDelegate()) }
            catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                if attempt < 2 { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000); continue }
                throw InstallManifestError.unavailable
            }
            guard let http = response as? HTTPURLResponse, data.count <= 8192 else { throw InstallManifestError.invalidResponse }
            if [429,503].contains(http.statusCode), attempt < 2 {
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
                continue
            }
            guard http.statusCode == 200 else {
                if [401,403,410].contains(http.statusCode) { throw InstallManifestError.expired }
                if [429,503].contains(http.statusCode) { throw InstallManifestError.busy }
                throw InstallManifestError.unavailable
            }
            let result = try JSONDecoder().decode(InstallManifest.self, from: data)
            let now = Date().timeIntervalSince1970
            guard result.id.uppercased() == id.uuidString,
                  result.expires_at > now, result.expires_at <= now + 1805,
                  valid(result.manifest_url, suffix: "/manifest.plist"), valid(result.page_url, suffix: "/install"),
                  result.manifest_url.deletingLastPathComponent() == result.page_url.deletingLastPathComponent(),
                  result.installationURL != nil else { throw InstallManifestError.invalidResponse }
            return result
        }
        throw InstallManifestError.busy
    }
    private func valid(_ url: URL, suffix: String) -> Bool {
        url.scheme == "https" && url.host == endpoint.host && url.port == endpoint.port &&
        url.user == nil && url.password == nil && url.query == nil && url.fragment == nil &&
        url.path.hasPrefix(endpoint.path + "/") && url.path.hasSuffix(suffix)
    }
}
