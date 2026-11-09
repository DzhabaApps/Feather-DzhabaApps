import AltSourceKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GameDataFileRow: View {
    let file: ASRepository.App.AdditionalFile
    @ObservedObject private var download = GameDataDownload.shared
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var replaceDestination: URL?
    @State private var confirmReplace = false
    @State private var saveError: String?

    private var extractsArchive: Bool { file.extractArchive == true }

    private var matches: Bool {
        download.transfer?.share == file.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AdditionalFileTitle(file: file)
                if download.transfer != nil || download.working {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Удалить загрузку", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }.accessibilityLabel("Действия с загрузкой").disabled(download.installing)
                } else {
                    Button { download.start(share: file.url, title: file.name) } label: {
                        AdditionalFileAction(title: "Скачать", icon: "arrow.down")
                    }.buttonStyle(.plain)
                }
            }
            if matches {
                if download.installing {
                    ProgressView("Распаковываем архив…")
                } else if download.ready {
                    Text("Файл скачан").font(.subheadline).foregroundStyle(.secondary)
                    Button { saving = download.exportURL != nil } label: {
                        AdditionalFileAction(title: extractsArchive ? "Сохранить" : "Сохранить в Файлы", icon: "folder")
                    }.buttonStyle(.plain)
                } else {
                    let fraction = min(1, Double(download.received) / Double(download.transfer?.size ?? file.size))
                    ProgressView(value: fraction) {
                        HStack {
                            Text(GameDataSource.progressText(received: download.received, total: download.transfer?.size ?? file.size))
                            Spacer()
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        }.font(.footnote).monospacedDigit()
                    }
                    if !download.working {
                        Button { download.start(share: file.url, title: file.name) } label: {
                            AdditionalFileAction(title: "Продолжить", icon: "arrow.down")
                        }.buttonStyle(.plain)
                    }
                }
            } else if download.transfer != nil {
                Text("Удалите прежнюю загрузку, чтобы скачать этот файл.").font(.footnote).foregroundStyle(.secondary)
            } else if download.working {
                ProgressView("Получаем ссылку…")
            }
            if let error = saveError ?? download.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .confirmationDialog("Удалить скачанную часть с iPhone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { saveError = nil; download.discard() }
        }
        .confirmationDialog("Заменить существующую папку?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Заменить", role: .destructive) {
                if let destination = replaceDestination { saveFolder(at: destination, replacing: true) }
                replaceDestination = nil
            }
            Button("Отмена", role: .cancel) { replaceDestination = nil }
        }
        .sheet(isPresented: $saving) {
            if let url = download.exportURL {
                GameDataExporter(url: url, chooseFolder: extractsArchive) { result in
                    saving = false
                    guard let result else { return }
                    if extractsArchive { saveFolder(at: result, replacing: false) }
                    else { download.discard() }
                }
            }
        }
    }

    private func saveFolder(at destination: URL, replacing: Bool) {
        saveError = nil
        Task { @MainActor in
            do {
                try await download.saveFolder(to: destination, replacing: replacing)
            } catch GameArchive.Failure.destinationExists {
                replaceDestination = destination
                confirmReplace = true
            } catch {
                saveError = (error as? GameArchive.Failure)?.localizedDescription
                    ?? "Не удалось сохранить папку. ZIP остался на iPhone. Проверь свободное место и попробуй снова."
            }
        }
    }
}

struct GameDataExporter: UIViewControllerRepresentable {
    let url: URL
    let chooseFolder: Bool
    let finished: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = chooseFolder
            ? UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            : UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (URL?) -> Void

        init(finished: @escaping (URL?) -> Void) { self.finished = finished }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finished(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finished(nil)
        }
    }
}
