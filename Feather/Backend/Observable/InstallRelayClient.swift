import Foundation

struct InstallRelayAuthorization: Sendable {
    let accessID: String
    let credential: String
    let installationID: String
}

struct InstallRelayJob: Decodable, Sendable {
    let id: String
    let control_token: String
    let expires_at: Double
    let upload_url: URL
    let status_url: URL
    let manifest_url: URL
    let page_url: URL
}

struct InstallRelayStatus: Decodable, Sendable {
    let state: String
    let downloaded_bytes: Int64
    let size: Int64
    let file_present: Bool
}

enum InstallRelayError: LocalizedError {
    case unavailable, tooLarge, invalidResponse, expired, busy, failed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Не удалось связаться с сервером установки. Проверьте интернет и попробуйте ещё раз."
        case .tooLarge: "Для этой версии размер приложения не должен превышать 1 ГБ."
        case .invalidResponse: "Сервер установки вернул некорректный ответ. Попробуйте ещё раз."
        case .expired: "Срок ссылки установки закончился. Нажмите «Установить» ещё раз."
        case .busy: "Сервер установки занят. Попробуйте через несколько минут."
        case .failed: "Не удалось подготовить установку. Проверьте подпись приложения и повторите попытку."
        }
    }
}

private final class RelayTransferDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void = { _ in }) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never redirect credentials or installation capabilities.
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { progress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))) }
    }
}

actor InstallRelayClient {
    static let endpoint = URL(string: "https://dzhabaapps.ru/api/install-relay")!
    // Set only in the owner's private diagnostic IPA, never in the public build.
    static var localTLSLabEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "DRStoreLocalTLSLab") as? Bool == true }
    static var semiLocalLabEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "DRStoreSemiLocalLab") as? Bool == true }
    static var localLabEnabled: Bool { localTLSLabEnabled || semiLocalLabEnabled }
    static var enabled: Bool { !localLabEnabled && Bundle.main.object(forInfoDictionaryKey: "DRStoreInstallRelay") as? Bool == true }

    static func semiLocalManifestURL(endpoint: URL, id: UUID, port: Int,
                                     bundleID: String, version: String, title: String) throws -> URL {
        guard endpoint.scheme == "https", endpoint.host == "dzhabaapps.ru",
              endpoint.port == nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              endpoint.path.hasPrefix("/api/install-relay/semi-local/"),
              (4000...8000).contains(port), !bundleID.isEmpty, !version.isEmpty else {
            throw InstallRelayError.invalidResponse
        }
        var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "id", value: id.uuidString),
            URLQueryItem(name: "port", value: String(port)), URLQueryItem(name: "bundle", value: bundleID),
            URLQueryItem(name: "version", value: version), URLQueryItem(name: "title", value: title)]
        guard let url = parts.url else { throw InstallRelayError.invalidResponse }
        return url
    }
    private let endpoint: URL
    private let session: URLSession
    private var currentJob: InstallRelayJob?

    init(endpoint: URL = InstallRelayClient.endpoint, session: URLSession? = nil) {
        self.endpoint = endpoint
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 900
            configuration.httpMaximumConnectionsPerHost = 2
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw InstallRelayError.invalidResponse }
        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401,403,410: throw InstallRelayError.expired
            case 429,503: throw InstallRelayError.busy
            default: throw InstallRelayError.failed
            }
        }
    }

    private func valid(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == endpoint.host && url.port == endpoint.port &&
        url.user == nil && url.password == nil && url.query == nil && url.fragment == nil &&
        url.path.hasPrefix(endpoint.path + "/")
    }

    func prepare(package: URL, bundleID: String, version: String, title: String,
                 authorization: InstallRelayAuthorization,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> InstallRelayJob {
        let size = try package.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 1024 * 1024 * 1024 else { throw InstallRelayError.tooLarge }
        var request = URLRequest(url: endpoint.appendingPathComponent("jobs"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer " + authorization.credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "access_id": authorization.accessID, "installation_id": authorization.installationID,
            "request_id": UUID().uuidString, "size": size, "bundle_id": bundleID, "version": version, "title": title])
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request, delegate: RelayTransferDelegate())
            try check(response)
            guard data.count <= 16384 else { throw InstallRelayError.invalidResponse }
            let job = try JSONDecoder().decode(InstallRelayJob.self, from: data)
            guard [job.upload_url,job.status_url,job.manifest_url,job.page_url].allSatisfy(valid),
                  job.expires_at > Date().timeIntervalSince1970,
                  job.id.range(of: "^[a-f0-9]{48}$", options: .regularExpression) != nil,
                  job.control_token.count == 64 else { throw InstallRelayError.invalidResponse }
            currentJob = job
            try Task.checkCancellation()
            var upload = URLRequest(url: job.upload_url, timeoutInterval: 900)
            upload.httpMethod = "PUT"
            upload.setValue(job.control_token, forHTTPHeaderField: "X-Install-Token")
            upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            upload.setValue(String(size), forHTTPHeaderField: "Content-Length")
            let (_, uploaded) = try await session.upload(for: upload, fromFile: package,
                delegate: RelayTransferDelegate(progress: progress))
            try check(uploaded)
            progress(1)
            return job
        } catch {
            await cancel()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if error is InstallRelayError { throw error }
            throw InstallRelayError.unavailable
        }
    }

    func status(_ job: InstallRelayJob) async throws -> InstallRelayStatus {
        var request = URLRequest(url: job.status_url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(job.control_token, forHTTPHeaderField: "X-Install-Token")
        let (data, response) = try await session.data(for: request, delegate: RelayTransferDelegate())
        try check(response)
        guard data.count <= 16384 else { throw InstallRelayError.invalidResponse }
        return try JSONDecoder().decode(InstallRelayStatus.self, from: data)
    }

    func cancel() async {
        guard let job = currentJob else { return }
        currentJob = nil
        var request = URLRequest(url: job.status_url, timeoutInterval: 10)
        request.httpMethod = "DELETE"
        request.setValue(job.control_token, forHTTPHeaderField: "X-Install-Token")
        _ = try? await session.data(for: request, delegate: RelayTransferDelegate())
    }
}
