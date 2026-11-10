import AltSourceKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GameDataFileRow: View {
    let file: ASRepository.App.AdditionalFile
    @ObservedObject private var download = GameDataDownload.shared
    @State private var saving = false
    @State private var selectingFolder = false
    @State private var confirmDelete = false
    @State private var replaceDestination: GameArchive.Destination?
    @State private var confirmReplace = false
    @State private var saveError: String?
    @State private var savedFolder = false

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
                        if download.working {
                            Button { download.pause() } label: {
                                Label("Пауза", systemImage: "pause")
                            }
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(download.ready ? "Удалить файл" : "Отменить загрузку", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }.accessibilityLabel("Действия с загрузкой").disabled(download.installing)
                } else {
                    Button { savedFolder = false; download.start(share: file.url) } label: {
                        AdditionalFileAction(title: "Скачать", icon: "arrow.down")
                    }.buttonStyle(.plain)
                }
            }
            if matches {
                if download.installing {
                    if let progress = download.extractionProgress {
                        ProgressView(value: progress) {
                            Text("Распаковываем архив · \(progress.formatted(.percent.precision(.fractionLength(0))))")
                        }
                    } else {
                        ProgressView("Готовим распаковку…")
                    }
                } else if download.ready {
                    Text("Файл скачан").font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        saveError = nil
                        guard download.exportURL != nil else {
                            saveError = "Не удалось открыть скачанный файл."
                            return
                        }
                        if extractsArchive { selectingFolder = true }
                        else { saving = true }
                    } label: {
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
                        Button { download.start(share: file.url) } label: {
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
            if savedFolder {
                Label("Папка сохранена", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .confirmationDialog(download.ready ? "Удалить скачанный файл?" : "Отменить загрузку и удалить скачанную часть?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(download.ready ? "Удалить" : "Отменить загрузку", role: .destructive) {
                saveError = nil
                download.discard()
            }
            Button("Назад", role: .cancel) {}
        }
        .alert("Заменить существующую папку?", isPresented: $confirmReplace) {
            Button("Заменить", role: .destructive) {
                if let destination = replaceDestination { saveFolder(at: destination, replacing: true) }
                replaceDestination = nil
            }
            Button("Отмена", role: .cancel) { replaceDestination = nil }
        }
        .fileImporter(isPresented: $selectingFolder, allowedContentTypes: [.folder]) { result in
            do {
                let destination = try GameArchive.Destination(result.get())
                saveFolder(at: destination, replacing: false)
            } catch {
                saveError = "Не удалось выбрать папку. Скачанный ZIP остался на iPhone."
            }
        }
        .sheet(isPresented: $saving) {
            if let url = download.exportURL {
                GameDataExporter(url: url) { result in
                    saving = false
                    if result != nil { download.discard() }
                }
            }
        }
    }

    private func saveFolder(at destination: GameArchive.Destination, replacing: Bool) {
        saveError = nil
        Task { @MainActor in
            do {
                try await download.saveFolder(to: destination, replacing: replacing)
                savedFolder = true
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
    let finished: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
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
