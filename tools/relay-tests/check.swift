import Foundation

final class Stub: URLProtocol, @unchecked Sendable {
    static var calls: [String] = []
    static var foreign = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.calls.append(request.httpMethod! + " " + path)
        let id = String(repeating: "a", count: 48)
        let base = "https://fixture.invalid/api/install-relay"
        var body: [String: Any] = [:]
        if request.httpMethod == "POST" {
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-credential")
            body = ["id":id, "control_token":String(repeating:"b",count:64),"expires_at":Date().timeIntervalSince1970+600,
                "upload_url": (Self.foreign ? "https://foreign.invalid" : base) + "/jobs/\(id)/package",
                "status_url":base+"/jobs/\(id)","manifest_url":base+"/download/\(id)/token/manifest.plist",
                "page_url":base+"/download/\(id)/token/install"]
        } else if request.httpMethod == "PUT" {
            assert(request.value(forHTTPHeaderField:"Authorization") == nil)
            assert(request.value(forHTTPHeaderField:"X-Install-Token") == String(repeating:"b",count:64))
            body = ["status":"ready"]
        } else if request.httpMethod == "DELETE" { body = ["status":"cancelled"] }
        else { body = ["state":"consumed","downloaded_bytes":32,"size":32,"file_present":false] }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Checks {
    static func main() async throws {
        let endpoint = URL(string: "https://dzhabaapps.ru/api/install-relay/semi-local/fixture/manifest.plist")!
        let title = "HD Rezka & тест + 2 / ? #"
        let manifestURL = try InstallRelayClient.semiLocalManifestURL(endpoint: endpoint, id: UUID(), port: 4567,
            bundleID: "fixture.app", version: "1.6.0", title: title)
        let queries = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)!.queryItems!
        assert(queries.count == 5 && queries.first(where: { $0.name == "title" })!.value == title)
        let encoded = manifestURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        assert(encoded.removingPercentEncoding == manifestURL.absoluteString)
        do {
            _ = try InstallRelayClient.semiLocalManifestURL(endpoint: URL(string: "https://foreign.invalid/manifest")!,
                id: UUID(), port: 4567, bundleID: "fixture.app", version: "1", title: title)
            fatalError("Foreign semi-local endpoint accepted")
        } catch InstallRelayError.invalidResponse {}
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        try Data(repeating:1,count:32).write(to:file)
        let cfg = URLSessionConfiguration.ephemeral;cfg.protocolClasses=[Stub.self]
        let session = URLSession(configuration:cfg)
        let client = InstallRelayClient(endpoint:URL(string:"https://fixture.invalid/api/install-relay")!,session:session)
        let auth = InstallRelayAuthorization(accessID:"fixture",credential:"fixture-credential",installationID:"fixture-installation")
        let job = try await client.prepare(package:file,bundleID:"fixture.app",version:"1",title:"Fixture",authorization:auth,progress:{_ in})
        let state = try await client.status(job)
        assert(state.state == "consumed" && !state.file_present)
        await client.cancel()
        assert(Stub.calls.filter{$0.hasPrefix("PUT")}.count == 1)
        assert(Stub.calls.filter{$0.hasPrefix("DELETE")}.count == 1)
        Stub.calls=[];Stub.foreign=true
        do {
            _ = try await client.prepare(package:file,bundleID:"fixture.app",version:"1",title:"Fixture",authorization:auth,progress:{_ in})
            fatalError("Foreign upload endpoint accepted")
        } catch InstallRelayError.invalidResponse {}
        assert(!Stub.calls.contains{$0.hasPrefix("PUT")})
        session.invalidateAndCancel()
        print("Relay client: authenticated create, file upload, isolated control token, status, cancellation and foreign endpoint rejection passed")
    }
}
