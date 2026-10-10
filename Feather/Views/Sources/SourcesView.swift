import AltSourceKit
import SwiftUI
import NimbleViews

struct SourcesView: View {
    @StateObject private var catalog: DzhabaCatalogModel
    @State private var category: CatalogCategory
    @State private var search = ""
    private let preview: Bool
    init(previewCategory: CatalogCategory? = nil, previewNews: Bool = false) {
        preview = previewCategory != nil
        _catalog = StateObject(wrappedValue: DzhabaCatalogModel(preview: previewCategory != nil, previewNews: previewNews))
        _category = State(initialValue: previewCategory ?? .all)
    }
    private var apps: [ASRepository.App] {
        (catalog.repository?.apps ?? []).filter { app in
            let matchesCategory = category == .all || CatalogCategory.resolve(bundleID: app.id, metadata: app.category) == category
            let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = text.isEmpty || app.currentName.localizedCaseInsensitiveContains(text)
                || (app.currentDescription?.localizedCaseInsensitiveContains(text) ?? false)
            return matchesCategory && matchesSearch
        }
    }
    var body: some View {
        NBNavigationView("Каталог", displayMode: .inline) {
            List {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(CatalogCategory.storeFilters) { item in
                                    Button { category = item } label: {
                                        Label(item.title, systemImage: item.icon)
                                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                                            .foregroundStyle(category == item ? Color.white : Color.primary)
                                            .background(category == item ? Color.accentColor : Color(UIColor.secondarySystemBackground), in: Capsule())
                                    }.buttonStyle(.plain)
                                    .accessibilityAddTraits(category == item ? .isSelected : [])
                                }
                            }
                        }
                    }.padding(.vertical, 2)
                     .listRowSeparator(.hidden)
                 .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                if let message = catalog.error {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                            Button("Повторить загрузку") { Task { await catalog.load() } }.disabled(catalog.isLoading)
                        }
                    }
                }
                if let source = catalog.repository {
                    if let news = source.news, !news.isEmpty {
                        SourceNewsView(news: news)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                        ForEach(apps, id: \.currentUniqueId) { app in
                            HStack(spacing: 12) {
                                NavigationLink {
                                    SourceAppsDetailView(source: source, app: app)
                                } label: {
                                    FRIconCellView(title: app.currentName, subtitle: SourceAppsCellView.appDescription(app: app), iconUrl: app.iconURL)
                                }.buttonStyle(.plain)
                                DownloadButtonView(app: app)
                            }.padding(.vertical, 2)
                        }
                    if apps.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: search.isEmpty ? category.icon : "magnifyingglass").font(.largeTitle)
                            Text(search.isEmpty ? "В этой категории пока нет приложений" : "Ничего не найдено").font(.headline)
                            Text(search.isEmpty ? "Новые приложения появятся здесь после добавления в каталог." : "Попробуйте другое название или выберите категорию «Все».")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28).listRowSeparator(.hidden)
                    }
                } else if catalog.isLoading {
                    ProgressView("Загружаем приложения…").frame(maxWidth: .infinity).padding(.vertical, 32).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListHeaderHeight, 0)
            .environment(\.defaultMinListRowHeight, 44)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск приложений")
            .refreshable { if !preview { await catalog.load() } }
            .toolbar { if catalog.isLoading && catalog.repository != nil { ProgressView() } }
        }
        .task { if !preview { await catalog.load() } }
    }
}
