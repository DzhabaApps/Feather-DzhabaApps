import Foundation

final class Stub: URLProtocol, @unchecked Sendable {
    static var calls = 0
    static var foreign = false
    static var busyFirst = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        assert(request.httpMethod == "POST" && request.url!.path == "/api/install-manifest/jobs")
        assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-credential")
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let payload = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        assert(payload["title"] as? String == "HD & тест + 2 / #")
        assert(payload["port"] as? Int == 4567)
        let base = Self.foreign ? "https://foreign.invalid/api/install-manifest" : "https://fixture.invalid/api/install-manifest"
        let body: [String: Any] = ["id": payload["id"]!, "expires_at": Date().timeIntervalSince1970 + 600,
            "manifest_url": base + "/fixture-token/manifest.plist", "page_url": base + "/fixture-token/install"]
        let status = Self.busyFirst && Self.calls == 1 ? 503 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Checks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Stub.self]
        let session = URLSession(configuration: config)
        let client = InstallManifestClient(endpoint: URL(string: "https://fixture.invalid/api/install-manifest")!, session: session)
        let auth = InstallAuthorization(accessID: "fixture", credential: "fixture-credential", installationID: "installation")
        let result = try await client.prepare(id: UUID(), port: 4567, bundleID: "test.app", version: "1",
            title: "HD & тест + 2 / #", authorization: auth)
        assert(Stub.calls == 1 && result.installationURL!.scheme == "itms-services")
        let parts = URLComponents(url: result.installationURL!, resolvingAgainstBaseURL: false)!
        assert(parts.queryItems!.first(where: { $0.name == "url" })!.value == result.manifest_url.absoluteString)
        Stub.foreign = true
        do {
            _ = try await client.prepare(id: UUID(), port: 4567, bundleID: "test.app", version: "1",
                title: "HD & тест + 2 / #", authorization: auth)
            fatalError("Foreign manifest accepted")
        } catch InstallManifestError.invalidResponse {}
        Stub.foreign = false; Stub.calls = 0; Stub.busyFirst = true
        _ = try await client.prepare(id: UUID(), port: 4567, bundleID: "test.app", version: "1",
            title: "HD & тест + 2 / #", authorization: auth)
        assert(Stub.calls == 2)
        session.invalidateAndCancel()
        print("Manifest client: authenticated metadata only, direct system URL, foreign URL rejection and bounded retry passed")
    }
}
