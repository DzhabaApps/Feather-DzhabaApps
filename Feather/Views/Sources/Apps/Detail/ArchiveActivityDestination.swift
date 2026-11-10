import SwiftUI

struct ArchiveActivityDestination: View {
    @StateObject private var catalog = DzhabaCatalogModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let source = catalog.repository,
                   let app = source.apps.first(where: { $0.id == "com.macport.gtav" }) {
                    SourceAppsDetailView(source: source, app: app)
                } else if catalog.isLoading {
                    ProgressView()
                } else {
                    Text(catalog.error ?? "Карточка GTA V пока недоступна.")
                }
            }
            .toolbar { Button("Закрыть") { dismiss() } }
        }
        .task { await catalog.load() }
    }
}
