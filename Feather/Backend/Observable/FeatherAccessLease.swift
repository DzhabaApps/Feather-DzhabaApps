import Foundation
import CryptoKit

struct FeatherAccessConfiguration: Codable {
    let version: Int
    let access_id: String
    let credential: String
}

struct FeatherAccessEnvelope: Codable {
    let payload: String
    let signature: String

    func verified(publicKey: Data, accessID: String) throws -> FeatherAccessLease {
        guard let bytes = Data(base64Encoded: payload), bytes.count <= 4096,
              let signatureBytes = Data(base64Encoded: signature),
              try Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signatureBytes, for: bytes)
        else { throw FeatherAccessError.invalidResponse }
        let lease = try JSONDecoder().decode(FeatherAccessLease.self, from: bytes)
        guard lease.version == 1, lease.access_id == accessID,
              lease.server_time > 0,
              ["active", "expired", "disabled", "pending"].contains(lease.status),
              lease.lease_until >= lease.server_time,
              lease.lease_until - lease.server_time <= 48 * 3600,
              lease.status != "active" || (lease.expires_at > lease.server_time && lease.lease_until <= lease.expires_at)
        else { throw FeatherAccessError.invalidResponse }
        return lease
    }
}

struct FeatherAccessLease: Codable {
    let version: Int
    let access_id: String
    let nonce: String
    let server_time: Int64
    let expires_at: Int64
    let lease_until: Int64
    let status: String

    // Calendar settings never determine subscription expiry.
    func state(elapsed: TimeInterval) -> FeatherAccessState {
        guard elapsed >= 0, elapsed.isFinite else { return .verificationRequired }
        if status == "disabled" { return .disabled }
        if status == "pending" { return .verificationRequired }
        let now = Double(server_time) + elapsed
        if status == "expired" || now >= Double(expires_at) { return .expired }
        return now < Double(lease_until) ? .active : .verificationRequired
    }
}

enum FeatherAccessState: String {
    case active, expired, disabled, verificationRequired
}

enum FeatherAccessClock {
    static func elapsed(savedTick: TimeInterval, currentTick: TimeInterval,
                        savedWall: TimeInterval, currentWall: TimeInterval,
                        savedBoot: String, currentBoot: String) -> TimeInterval? {
        let elapsed = currentTick - savedTick
        guard elapsed.isFinite, elapsed >= 0, !savedBoot.isEmpty, savedBoot == currentBoot,
              abs((currentWall - savedWall) - elapsed) <= 120 else { return nil }
        return elapsed
    }
}

enum FeatherAccessError: LocalizedError {
    case invalidResponse, unavailable, expired, disabled
    var errorDescription: String? {
        switch self {
        case .expired: return "Подписка закончилась. Продлите подписку в боте."
        case .disabled: return "Доступ к этой сборке отключён. Откройте актуальную ссылку в боте или обратитесь в поддержку."
        default: return "Не удалось проверить подписку. Подключитесь к интернету и повторите проверку."
        }
    }
}
