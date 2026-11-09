import SwiftUI
import AltSourceKit
import NukeUI

struct InstructionDetailScreen: View {
    let instruction: StoreInstruction
    var body: some View {
        ScrollView { InstructionVideoCard(instruction: instruction).padding() }
            .navigationTitle("Инструкция").navigationBarTitleDisplayMode(.inline)
    }
}

struct InstructionAppIcon: View {
    let url: URL?
    var fallbackSymbol = "play.rectangle"
    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image { image.resizable().scaledToFill() }
            else {
                Image(systemName: fallbackSymbol)
                    .font(.title3).foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.1))
            }
        }.frame(width: 48, height: 48).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InstructionCollectionCard: View {
    let collection: InstructionCollection
    var body: some View {
        HStack(spacing: 13) {
            InstructionAppIcon(
                url: collection.iconURL,
                fallbackSymbol: collection.id == InstructionCollections.generalID ? "book" : "play.rectangle"
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(collection.title).font(.headline).foregroundStyle(.primary)
                Text(InstructionCollections.countLabel(collection.instructions.count))
                    .font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(14).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct InstructionVideoRow: View {
    let instruction: StoreInstruction
    var body: some View {
        HStack(spacing: 14) {
            LazyImage(url: instruction.cover_url) { state in
                if let image = state.image { image.resizable().scaledToFill() }
                else { Color.secondary.opacity(0.1) }
            }.frame(width: 96, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { Image(systemName: "play.circle.fill").foregroundStyle(.white).shadow(radius: 3) }
            Text(instruction.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(10).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct InstructionCollectionScreen: View {
    let collectionID: String
    let apps: [InstructionAppSummary]
    @ObservedObject var catalog: InstructionCatalog
    @State private var search = ""
    private var collection: InstructionCollection? {
        InstructionCollections.build(catalog.instructions, apps: apps).first { $0.id == collectionID }
    }
    var body: some View {
        let collection = self.collection
        ScrollView {
            if let collection {
                let videos = collection.instructions.filter { InstructionCollections.matches($0, query: search) }
                LazyVStack(alignment: .leading, spacing: 10) {
                    if videos.isEmpty {
                        Text("Ничего не найдено").foregroundStyle(.secondary)
                    }
                    ForEach(videos) { item in
                        NavigationLink { InstructionDetailScreen(instruction: item) } label: {
                            InstructionVideoRow(instruction: item)
                        }.buttonStyle(.plain).accessibilityIdentifier("instruction-video-" + item.id)
                    }
                }.padding()
            } else {
                Text("В этой подборке пока нет опубликованных видео.")
                    .foregroundStyle(.secondary).padding()
            }
        }
        .navigationTitle(collection?.title ?? "Инструкции").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Найти видео")
        .refreshable { await catalog.load(force: true) }
        .task { await catalog.load() }
    }
}

struct InstructionLibraryContent: View {
    @ObservedObject var catalog: InstructionCatalog
    let apps: [InstructionAppSummary]
    let search: String
    private var collections: [InstructionCollection] {
        InstructionCollections.build(catalog.instructions, apps: apps).filter { collection in
            search.isEmpty || collection.title.localizedCaseInsensitiveContains(search)
                || collection.instructions.contains { InstructionCollections.matches($0, query: search) }
        }
    }
    var body: some View {
        let collections = self.collections
        LazyVStack(alignment: .leading, spacing: 10) {
            if let error = catalog.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Обновить") { Task { await catalog.load(force: true) } }
            }
            if catalog.isLoading && catalog.instructions.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            ForEach(collections) { collection in
                NavigationLink {
                    InstructionCollectionScreen(collectionID: collection.id, apps: apps, catalog: catalog)
                } label: { InstructionCollectionCard(collection: collection) }
                .buttonStyle(.plain).accessibilityIdentifier("instruction-collection-" + collection.id)
            }
            if collections.isEmpty && !catalog.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                    Text(search.isEmpty ? "Здесь появятся инструкции" : "Ничего не найдено").font(.headline)
                }.frame(maxWidth: .infinity).padding(.vertical, 45)
            }
        }.padding()
    }
}
