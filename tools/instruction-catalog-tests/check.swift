import Foundation

final class Stub: URLProtocol {
    static var replies: [String: (Int, Data)] = [:]
    static var cancelled = false
    static var requested: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url!.host!
        Self.requested.append(host)
        if Self.cancelled {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let (status, data) = Self.replies[host] ?? (503, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Checks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let endpoints = [URL(string: "https://primary.test/index")!, URL(string: "https://fallback.test/index")!]
        let data = try JSONEncoder().encode(InstructionIndex(schema_version: 1, instructions: [.sample]))
        let cache = root.appendingPathComponent("cache.json")
        let catalog = InstructionCatalog(session: session, cacheURL: cache, endpoints: endpoints)

        Stub.replies = ["primary.test": (503, Data()), "fallback.test": (200, data)]
        await catalog.load(force: true)
        precondition(catalog.instructions == [.sample] && catalog.error == nil && !catalog.isLoading)
        precondition(Stub.requested == ["primary.test", "fallback.test"])
        let cachedData = try Data(contentsOf: cache)
        precondition(cachedData == data)

        Stub.requested = []
        Stub.replies = ["primary.test": (200, Data("not JSON".utf8)), "fallback.test": (200, data)]
        await catalog.load(force: true)
        precondition(catalog.error == nil && Stub.requested == ["primary.test", "fallback.test"])

        Stub.requested = []
        Stub.replies = ["primary.test": (200, data)]
        await catalog.load(force: true)
        precondition(Stub.requested == ["primary.test"] && catalog.error == nil)

        Stub.cancelled = true
        Stub.requested = []
        await catalog.load(force: true)
        precondition(catalog.error == nil && catalog.instructions == [.sample] && !catalog.isLoading)
        precondition(Stub.requested == ["primary.test"])

        Stub.cancelled = false
        Stub.replies = [:]
        await catalog.load(force: true)
        precondition(catalog.error != nil && catalog.instructions == [.sample] && !catalog.isLoading)
        let restored = InstructionCatalog(session: session, cacheURL: cache, endpoints: endpoints)
        precondition(restored.instructions == [.sample])

        Stub.replies = ["primary.test": (200, data)]
        await catalog.load(force: true)
        precondition(catalog.error == nil && catalog.instructions == [.sample])
        print("Instruction catalog: primary/fallback, malformed JSON, cancellation, offline cache and recovery passed")
    }
}
