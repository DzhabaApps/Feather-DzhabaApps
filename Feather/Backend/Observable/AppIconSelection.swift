import Foundation
import Combine

/// UIKit may complete an icon change on a background queue.
@MainActor
final class AppIconSelection: ObservableObject {
    @Published private(set) var currentIcon: String?
    @Published private(set) var isChanging = false
    @Published var showError = false
    private let readIcon: () -> String?
    private let changeIcon: (String?, @escaping (Error?) -> Void) -> Void
    private let defaults: UserDefaults
    private let savedIconKey = "drStore.confirmedAppIcon"

    init(readIcon: @escaping () -> String?, defaults: UserDefaults = .standard, changeIcon: @escaping (String?, @escaping (Error?) -> Void) -> Void) {
        self.readIcon = readIcon
        self.defaults = defaults
        self.changeIcon = changeIcon
        if let saved = defaults.string(forKey: savedIconKey) {
            currentIcon = saved.isEmpty ? nil : saved
        } else {
            currentIcon = readIcon()
        }
    }

    func refresh() {
        guard !isChanging else { return }
        // Some signed builds report nil even after a successful alternate-icon change.
        // Preserve the last successful request, including an explicit primary selection.
        if let saved = defaults.string(forKey: savedIconKey) {
            currentIcon = saved.isEmpty ? nil : saved
        } else {
            currentIcon = readIcon()
        }
    }

    func select(_ key: String?) {
        // Always allow a reset to primary, even when UIKit's stale value is nil.
        guard !isChanging else { return }
        showError = false
        isChanging = true
        changeIcon(key) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isChanging = false
                if error == nil {
                    self.defaults.set(key ?? "", forKey: self.savedIconKey)
                    self.currentIcon = key
                } else {
                    self.showError = true
                }
            }
        }
    }
}
