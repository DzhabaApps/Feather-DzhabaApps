#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit

@available(iOS 16.2, *)
struct ArchiveActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable {
        case downloading, paused, ready
    }

    struct ContentState: Codable, Hashable {
        let fraction: Double
        let bytes: String
        let phase: Phase
    }

    let title: String
}
#endif
