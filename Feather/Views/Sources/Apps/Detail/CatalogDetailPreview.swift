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
