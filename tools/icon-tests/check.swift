import Foundation

@main
struct IconSelectionCheck {
    @MainActor static func main() async throws {
        let suite = "IconSelectionCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var completion: ((Error?) -> Void)?
        var calls = 0
        // Reproduce the real signed-build behavior: UIKit keeps returning nil.
        let read: () -> String? = { nil }
        var requested: String?
        let change: (String?, @escaping (Error?) -> Void) -> Void = { key, done in
            requested = key
            calls += 1; completion = done
        }
        let selection = AppIconSelection(readIcon: read, defaults: defaults, changeIcon: change)
        func complete(_ error: Error?) async throws {
            let done = completion!
            completion = nil
            DispatchQueue.global().async { done(error) }
            let limit = Date().addingTimeInterval(3)
            while selection.isChanging && Date() < limit { try await Task.sleep(nanoseconds: 10_000_000) }
            precondition(!selection.isChanging, "Background callback did not update main actor")
        }
        // Upgrade recovery: primary must remain callable despite a stale nil read.
        selection.select(nil)
        precondition(calls == 1 && requested == nil)
        try await complete(nil)
        selection.select("V2Mac")
        selection.select("V1")
        selection.refresh()
        precondition(selection.isChanging && calls == 2 && selection.currentIcon == nil)
        try await complete(nil)
        precondition(selection.currentIcon == "V2Mac" && !selection.showError)
        selection.refresh()
        precondition(selection.currentIcon == "V2Mac")
        let reopened = AppIconSelection(readIcon: read, defaults: defaults, changeIcon: change)
        precondition(reopened.currentIcon == "V2Mac")
        selection.select("V1")
        try await complete(NSError(domain: "IconTest", code: 1))
        precondition(selection.currentIcon == "V2Mac" && selection.showError)
        selection.showError = false
        selection.select("V1")
        try await complete(nil)
        selection.refresh()
        precondition(selection.currentIcon == "V1")
        selection.select(nil)
        try await complete(nil)
        selection.refresh()
        precondition(selection.currentIcon == nil && !selection.showError && calls == 5 && requested == nil)
        let primary = AppIconSelection(readIcon: { "V2Mac" }, defaults: defaults, changeIcon: change)
        primary.refresh()
        precondition(primary.currentIcon == nil, "Confirmed primary must survive reopen and stale alternate reads")
        print("Icon selection: persistent success, always-nil UIKit, primary reset, background completion, concurrent request, error and all three choices passed")
    }
}
