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

    init(readIcon: @escaping () -> String?, changeIcon: @escaping (String?, @escaping (Error?) -> Void) -> Void) {
        self.readIcon = readIcon
        self.changeIcon = changeIcon
        currentIcon = readIcon()
    }

    func refresh() {
        if !isChanging { currentIcon = readIcon() }
    }

    func select(_ key: String?) {
        guard !isChanging, key != currentIcon else { return }
        isChanging = true
        changeIcon(key) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isChanging = false
                if error == nil {
                    self.currentIcon = key
                } else {
                    self.currentIcon = self.readIcon()
                    self.showError = true
                }
            }
        }
    }
}
