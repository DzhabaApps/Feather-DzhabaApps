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
    var size: CGFloat = 48
    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image { image.resizable().scaledToFill() }
            else {
                Image(systemName: "play.rectangle")
                    .font(.title3).foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.1))
            }
        }.frame(width: size, height: size).clipped()
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

struct InstructionCollectionCard: View {
    let collection: InstructionCollection
    var body: some View {
        HStack(spacing: 13) {
            InstructionAppIcon(url: collection.iconURL)
            VStack(alignment: .leading, spacing: 5) {
                Text(collection.title).font(.headline).foregroundStyle(.primary)
                Text(InstructionCollections.countLabel(collection.instructions.count))
                    .font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(14).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct GeneralInstructionCard: View {
    let instruction: StoreInstruction
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: instruction.id == "create-copy" ? "doc.on.doc" : "arrow.down.to.line")
                .font(.title3).foregroundStyle(.tint)
            Text(instruction.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 75, alignment: .topLeading)
            .padding(15).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct InstructionVideoRow: View {
    let instruction: StoreInstruction
    var body: some View {
        HStack(spacing: 14) {
            LazyImage(url: instruction.cover_url) { state in
                if let image = state.image { image.resizable().scaledToFill() }
                else { Color.secondary.opacity(0.1) }
            }.frame(width: 73, height: 91).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { Image(systemName: "play.circle.fill").foregroundStyle(.white).shadow(radius: 3) }
            VStack(alignment: .leading, spacing: 6) {
                Text(instruction.title).font(.headline).foregroundStyle(.primary)
                if !instruction.description.isEmpty {
                    Text(instruction.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
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
        ScrollView {
            if let collection {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        InstructionAppIcon(url: collection.iconURL, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(collection.title).font(.title.weight(.bold))
                            Text(InstructionCollections.countLabel(collection.instructions.count))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.bottom, 10)
                    ForEach(collection.instructions.filter { InstructionCollections.matches($0, query: search) }) { item in
                        NavigationLink { InstructionDetailScreen(instruction: item) } label: {
                            InstructionVideoRow(instruction: item)
                        }.buttonStyle(.plain).accessibilityIdentifier("instruction-video-" + item.id)
                        Divider()
                    }
                }.padding()
            } else {
                Text("В этой подборке пока нет опубликованных видео.")
                    .foregroundStyle(.secondary).padding()
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Найти видео")
        .refreshable { await catalog.load(force: true) }
        .task { await catalog.load() }
    }
}

struct InstructionLibraryContent: View {
    @ObservedObject var catalog: InstructionCatalog
    let apps: [InstructionAppSummary]
    let search: String
    private var general: [StoreInstruction] {
        catalog.instructions.filter { InstructionCollections.isGeneral($0) && InstructionCollections.matches($0, query: search) }
    }
    private var collections: [InstructionCollection] {
        InstructionCollections.build(catalog.instructions, apps: apps).filter { collection in
            search.isEmpty || collection.title.localizedCaseInsensitiveContains(search)
                || collection.instructions.contains { InstructionCollections.matches($0, query: search) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = catalog.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Обновить") { Task { await catalog.load(force: true) } }
            }
            if catalog.isLoading && catalog.instructions.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            if !general.isEmpty {
                Text("Общие").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .top)], alignment: .leading, spacing: 10) {
                    ForEach(general) { item in
                        NavigationLink { InstructionDetailScreen(instruction: item) } label: {
                            GeneralInstructionCard(instruction: item)
                        }.buttonStyle(.plain).accessibilityIdentifier("instruction-general-" + item.id)
                    }
                }
            }
            if !collections.isEmpty {
                Text("По приложениям").font(.title3.weight(.semibold)).padding(.top, 8)
                ForEach(collections) { collection in
                    NavigationLink {
                        InstructionCollectionScreen(collectionID: collection.id, apps: apps, catalog: catalog)
                    } label: { InstructionCollectionCard(collection: collection) }
                    .buttonStyle(.plain).accessibilityIdentifier("instruction-collection-" + collection.id)
                }
            }
            if general.isEmpty && collections.isEmpty && !catalog.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                    Text(search.isEmpty ? "Здесь появятся инструкции" : "Ничего не найдено").font(.headline)
                }.frame(maxWidth: .infinity).padding(.vertical, 45)
            }
        }.padding()
    }
}
