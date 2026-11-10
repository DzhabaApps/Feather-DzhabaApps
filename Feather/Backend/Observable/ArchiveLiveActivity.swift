#if ARCHIVE_LIVE_ACTIVITY_TEST && !targetEnvironment(macCatalyst)
import ActivityKit
import UIKit

final class ArchiveLiveActivity {
    private var lastUpdate = -Double.infinity

    @available(iOS 16.2, *)
    func begin(title: String, received: Int64, total: Int64?) {
        guard UIApplication.shared.applicationState == .active,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if Activity<ArchiveActivityAttributes>.activities.isEmpty {
            let data = state(received: received, total: total, phase: .downloading)
            _ = try? Activity.request(attributes: ArchiveActivityAttributes(title: title),
                content: ActivityContent(state: data, staleDate: Date().addingTimeInterval(120)),
                pushType: nil)
        }
        lastUpdate = -Double.infinity
        update(received: received, total: total, force: true)
    }

    @available(iOS 16.2, *)
    func update(received: Int64, total: Int64?, force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastUpdate >= 8,
              let activity = Activity<ArchiveActivityAttributes>.activities.first else { return }
        lastUpdate = now
        let data = state(received: received, total: total, phase: .downloading)
        Task {
            await activity.update(ActivityContent(state: data, staleDate: Date().addingTimeInterval(120)))
        }
    }

    @available(iOS 16.2, *)
    func end(received: Int64, total: Int64?, success: Bool) {
        guard let activity = Activity<ArchiveActivityAttributes>.activities.first else { return }
        let data = state(received: received, total: total, phase: success ? .ready : .paused)
        Task {
            await activity.end(ActivityContent(state: data, staleDate: nil),
                               dismissalPolicy: .after(Date().addingTimeInterval(90)))
        }
    }

    @available(iOS 16.2, *)
    private func state(received: Int64, total: Int64?, phase: ArchiveActivityAttributes.Phase) -> ArchiveActivityAttributes.ContentState {
        let size = total ?? 0
        let fraction = size > 0 ? min(1, max(0, Double(received) / Double(size))) : 0
        return .init(fraction: fraction,
                     bytes: GameDataSource.progressText(received: received, total: size), phase: phase)
    }
}
#endif
