import Foundation
import CryptoKit

let key = Curve25519.Signing.PrivateKey()
func envelope(_ status: String = "active", expiry: Int64 = 200000, until: Int64 = 173800) throws -> FeatherAccessEnvelope {
    let payload = FeatherAccessLease(version: 1, access_id: "test-access", nonce: "test-nonce",
        server_time: 1000, expires_at: expiry, lease_until: until, status: status)
    let data = try JSONEncoder().encode(payload)
    return FeatherAccessEnvelope(payload: data.base64EncodedString(), signature: try key.signature(for: data).base64EncodedString())
}
let signed = try envelope()
let lease = try signed.verified(publicKey: key.publicKey.rawRepresentation, accessID: "test-access")
assert(lease.state(elapsed: 0) == .active)
assert(lease.state(elapsed: 172799) == .active)
assert(lease.state(elapsed: 172800) == .verificationRequired)
assert(lease.state(elapsed: 199000) == .expired)
assert(lease.state(elapsed: -1) == .verificationRequired)
let short = try envelope(expiry: 1100, until: 1100).verified(publicKey: key.publicKey.rawRepresentation, accessID: "test-access")
assert(short.state(elapsed: 99) == .active)
assert(short.state(elapsed: 100) == .expired)
assert((try? signed.verified(publicKey: key.publicKey.rawRepresentation, accessID: "other")) == nil)
assert((try? signed.verified(publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation, accessID: "test-access")) == nil)
assert((try? envelope(until: 173801).verified(publicKey: key.publicKey.rawRepresentation, accessID: "test-access")) == nil)
let tampered = FeatherAccessEnvelope(payload: Data("{}".utf8).base64EncodedString(), signature: signed.signature)
assert((try? tampered.verified(publicKey: key.publicKey.rawRepresentation, accessID: "test-access")) == nil)
let disabled = try envelope("disabled", until: 1000).verified(publicKey: key.publicKey.rawRepresentation, accessID: "test-access")
assert(disabled.state(elapsed: 0) == .disabled)
let expired = try envelope("expired", expiry: 900, until: 1000).verified(publicKey: key.publicKey.rawRepresentation, accessID: "test-access")
assert(expired.state(elapsed: 0) == .expired)
func elapsed(tick: Double = 110, wall: Double = 1010, boot: String = "A") -> Double? {
    FeatherAccessClock.elapsed(savedTick: 100, currentTick: tick, savedWall: 1000, currentWall: wall, savedBoot: "A", currentBoot: boot)
}
assert(elapsed() == 10)
assert(elapsed(wall: 1000 + 365 * 86400) == nil) // date forward does not fake expiry
assert(elapsed(wall: -10000) == nil) // date backward never adds allowance
assert(elapsed(tick: 99) == nil)
assert(elapsed(boot: "B") == nil) // reboot needs a fresh response
assert(elapsed(tick: 100 + 48 * 3600, wall: 1000 + 48 * 3600) == 48 * 3600)
assert(!FeatherAccessManager.shared.permitsAccess()) // unconfigured base is closed
print("Feather access: signatures, expiry, 48h bound, clock changes, reboot and missing configuration passed")
