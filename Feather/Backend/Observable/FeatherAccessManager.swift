import Foundation
import Combine
import CryptoKit
import Security
import Darwin

final class FeatherAccessManager: ObservableObject, @unchecked Sendable {
    static let shared = FeatherAccessManager()
    @Published private(set) var state: FeatherAccessState = .verificationRequired
    @Published private(set) var isChecking = false
    @Published private(set) var hasChecked = false
    @Published private(set) var expiresAt: Date?
    private let lock = NSLock()
    private let configuration: FeatherAccessConfiguration?
    private let publicKey: Data?
    private var cache: Cache?
    private var refreshing = false
    private var nextAttempt: TimeInterval = 0
    private var nextBackgroundRefresh: TimeInterval = 0
    private var timer: AnyCancellable?
    private let endpoint = URL(string: "https://dzhabaapps.ru/api/feather/access/lease")!
    private static let processIdentity = UUID().uuidString

    private struct Cache: Codable {
        let envelope: FeatherAccessEnvelope
        let tick: TimeInterval
        let boot: String
        let wall: TimeInterval
    }

    private init() {
        configuration = Bundle.main.url(forResource: "feather-access", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(FeatherAccessConfiguration.self, from: $0) }
        publicKey = Bundle.main.url(forResource: "FeatherAccessPublicKey", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let data = readKeychain(), let saved = try? JSONDecoder().decode(Cache.self, from: data),
           !saved.boot.isEmpty, saved.boot == Self.bootIdentity() { cache = saved }
        // Restore verified access before SwiftUI renders its first frame.
        let initial = snapshot()
        state = initial.0
        expiresAt = initial.1
        isChecking = configuration != nil && initial.0 == .verificationRequired
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.publish()
            self.timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                self?.publish()
                self?.refreshIfDue()
            }
        }
    }

    // mach_continuous_time advances through sleep and ignores manual date changes.
    private static func tick() -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
    }

    private static func bootIdentity() -> String {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, u_int(mib.count), &boot, &size, nil, 0) == 0 else { return "process:\(processIdentity)" }
        return "\(boot.tv_sec):\(boot.tv_usec)"
    }

    private func snapshot() -> (FeatherAccessState, Date?) {
        lock.lock(); defer { lock.unlock() }
        guard let configuration, configuration.version == 1, let publicKey, let cache,
              let lease = try? cache.envelope.verified(publicKey: publicKey, accessID: configuration.access_id)
        else { return (.verificationRequired, nil) }
        // Reboot, ambiguous clock continuity or clock tampering requires a fresh server answer.
        guard let elapsed = FeatherAccessClock.elapsed(savedTick: cache.tick, currentTick: Self.tick(),
            savedWall: cache.wall, currentWall: Date().timeIntervalSince1970,
            savedBoot: cache.boot, currentBoot: Self.bootIdentity())
        else { return (.verificationRequired, Date(timeIntervalSince1970: Double(lease.expires_at))) }
        return (lease.state(elapsed: elapsed), lease.expires_at > 0 ? Date(timeIntervalSince1970: Double(lease.expires_at)) : nil)
    }

    func requireAccess() throws {
        let current = snapshot().0
        if current != .active {
            publish()
            switch current {
            case .expired: throw FeatherAccessError.expired
            case .disabled: throw FeatherAccessError.disabled
            default: throw FeatherAccessError.unavailable
            }
        }
    }

    func permitsAccess() -> Bool { (try? requireAccess()) != nil }

    private func publish() {
        let current = snapshot()
        DispatchQueue.main.async { [weak self] in
            self?.state = current.0
            self?.expiresAt = current.1
        }
    }

    private func beginRefresh(force: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !refreshing, force || Self.tick() >= nextAttempt else { return false }
        refreshing = true
        nextAttempt = Self.tick() + 60
        nextBackgroundRefresh = Self.tick() + 300
        return true
    }

    private func refreshIfDue() {
        lock.lock()
        let due = configuration != nil && !refreshing && Self.tick() >= nextBackgroundRefresh
        lock.unlock()
        if due { Task { await self.refresh() } }
    }

    private func finishRefresh(_ newCache: Cache?) {
        lock.lock()
        if let newCache {
            cache = newCache
            nextBackgroundRefresh = Self.tick() + 3600
        }
        refreshing = false
        lock.unlock()
        if let newCache, let data = try? JSONEncoder().encode(newCache) { writeKeychain(data) }
        publish()
        DispatchQueue.main.async { [weak self] in
            self?.hasChecked = true
            self?.isChecking = false
        }
    }

    func refresh(force: Bool = false) async {
        guard beginRefresh(force: force) else { publish(); return }
        DispatchQueue.main.async { [weak self] in self?.isChecking = true }
        var received: Cache?
        defer { finishRefresh(received) }
        guard let configuration, let publicKey else { return }
        let nonce = UUID().uuidString
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let installation = installationIdentity() else { return }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["access_id": configuration.access_id, "nonce": nonce,
            "installation_id": installation])
        // Charge request duration against the allowance; never grant extra time for a slow response.
        let tick = Self.tick()
        let wall = Date().timeIntervalSince1970
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 16384,
                  http.url?.host == endpoint.host else { return }
            let envelope = try JSONDecoder().decode(FeatherAccessEnvelope.self, from: data)
            let lease = try envelope.verified(publicKey: publicKey, accessID: configuration.access_id)
            guard lease.nonce == nonce else { return }
            received = Cache(envelope: envelope, tick: tick, boot: Self.bootIdentity(), wall: wall)
        } catch {
            // Keep the previous verified lease on timeout, 5xx or invalid response.
        }
    }

    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ru.dzhabaapps.feather.access",
         kSecAttrAccount as String: configuration?.access_id ?? "unconfigured"]
    }
    private func readKeychain() -> Data? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
    private func writeKeychain(_ data: Data) {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(keychainQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    private func installationIdentity() -> String? {
        var query = keychainQuery
        query[kSecAttrAccount as String] = "device:\(configuration?.access_id ?? "unconfigured")"
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let identity = String(data: data, encoding: .utf8) { return identity }
        let identity = UUID().uuidString
        query[kSecValueData as String] = Data(identity.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess ? identity : nil
    }
}
