import Foundation

@main
struct IconSelectionCheck {
    @MainActor static func main() async throws {
        var systemIcon: String?
        var completion: ((Error?) -> Void)?
        var calls = 0
        let read = { systemIcon }
        let change: (String?, @escaping (Error?) -> Void) -> Void = { _, done in
            calls += 1; completion = done
        }
        let selection = AppIconSelection(readIcon: read, changeIcon: change)
        func complete(_ error: Error?) async throws {
            let done = completion!
            completion = nil
            DispatchQueue.global().async { done(error) }
            let limit = Date().addingTimeInterval(3)
            while selection.isChanging && Date() < limit { try await Task.sleep(nanoseconds: 10_000_000) }
            precondition(!selection.isChanging, "Background callback did not update main actor")
        }
        selection.select("V2Mac")
        selection.select("V1")
        selection.refresh()
        precondition(selection.isChanging && calls == 1 && selection.currentIcon == nil)
        try await complete(nil)
        precondition(selection.currentIcon == "V2Mac" && !selection.showError)
        systemIcon = "V2Mac"
        selection.refresh()
        selection.select("V2Mac")
        precondition(calls == 1)
        let reopened = AppIconSelection(readIcon: read, changeIcon: change)
        precondition(reopened.currentIcon == "V2Mac")
        selection.select("V1")
        try await complete(NSError(domain: "IconTest", code: 1))
        precondition(selection.currentIcon == "V2Mac" && selection.showError)
        selection.showError = false
        selection.select("V1")
        try await complete(nil)
        systemIcon = "V1"
        selection.refresh()
        precondition(selection.currentIcon == "V1")
        selection.select(nil)
        try await complete(nil)
        systemIcon = nil
        selection.refresh()
        precondition(selection.currentIcon == nil && !selection.showError && calls == 4)
        print("Icon selection: background completion, stale read, concurrent request, duplicate, error, reopen and all three choices passed")
    }
}
