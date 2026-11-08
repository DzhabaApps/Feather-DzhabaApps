import SwiftUI
import AltSourceKit

/// External files and their installation video live together in the app card.
struct AppAdditionalFilesView: View {
    let files: [ASRepository.App.AdditionalFile]
    @ObservedObject private var catalog = InstructionCatalog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                Link(destination: file.url) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(file.name).font(.headline).foregroundStyle(.primary)
                            Text(CatalogFileSize.string(file.size))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Label("Скачать", systemImage: "arrow.down")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                            .padding(.horizontal, 13).padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                            .fixedSize()
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                if let id = file.instructionID,
                   !files.prefix(index).contains(where: { $0.instructionID == id }) {
                    if let instruction = catalog.instructions.first(where: { $0.id == id }) {
                        InstructionVideoCard(instruction: instruction, compact: true)
                    } else if catalog.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Button { Task { await catalog.load(force: true) } } label: {
                            Label("Обновить видеоинструкцию", systemImage: "arrow.clockwise")
                                .font(.footnote)
                        }
                    }
                }
            }
        }.padding(.vertical, 8)
    }
}
