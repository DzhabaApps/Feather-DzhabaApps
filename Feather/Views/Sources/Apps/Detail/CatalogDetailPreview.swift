import SwiftUI

// Reached only from the isolated preview root.
struct CatalogDetailPreview: View {
    @StateObject private var model = DzhabaCatalogModel(preview: true)
    var body: some View {
        NavigationStack {
            if let source = model.repository, let app = source.apps.first {
                SourceAppsDetailView(source: source, app: app)
            }
        }
    }
}

// Uses the real public GTA entry only in the isolated simulator preview root.
struct GameDetailPreview: View {
    @StateObject private var model = DzhabaCatalogModel()
    var body: some View {
        NavigationStack {
            if let source = model.repository,
               let app = source.apps.first(where: { $0.id == "com.macport.gtav" }) {
                SourceAppsDetailView(source: source, app: app)
                    .task {
                        await InstructionCatalog.shared.load(force: true)
                        // The detail view may already be loading the shared index.
                        for _ in 0..<150 {
                            if InstructionCatalog.shared.instructions.contains(where: { $0.id == "gta-v-install" }) { break }
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                        let report: [String: Any] = [
                            "files": app.additionalFiles?.count ?? 0,
                            "videoResolved": InstructionCatalog.shared.instructions.contains { $0.id == "gta-v-install" }
                        ]
                        if let data = try? JSONSerialization.data(withJSONObject: report) {
                            try? data.write(to: URL.documentsDirectory.appendingPathComponent("compact-game-ready.json"))
                        }
                    }
            } else { ProgressView("Загружаем карточку игры…") }
        }.task { await model.load() }
    }
}
