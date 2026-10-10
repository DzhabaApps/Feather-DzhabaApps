import SwiftUI

// No real applications, accounts or certificates: simulator screenshots only.
struct CopyChoicePreview: View {
    let creating: Bool
    @State private var request: AppInstallRequest?
    var body: some View {
        Group {
            if let request {
                AppInstallationChoiceView(request: request, installer: .shared, creating: creating)
            } else { ProgressView() }
        }
        .onAppear {
            guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview" else { return }
            PreviewLibraryChecks.seedReadyApp()
            let source = URL(string: "https://example.invalid/ready-preview")!
            guard let app = RepositoryInstallCoordinator.shared.libraryApp(for: source) else { return }
            let copies = AppCopyStore.shared
            if (try? copies.copies(for: "preview.ready").isEmpty) == true {
                try? copies.create(originalIdentifier: "preview.ready", name: "Рабочий WhatsApp")
                try? copies.create(originalIdentifier: "preview.ready", name: "Личный WhatsApp")
            }
            request = AppInstallRequest(app: app, originalIdentifier: "preview.ready", originalName: "WhatsApp Plus")
        }
    }
}
