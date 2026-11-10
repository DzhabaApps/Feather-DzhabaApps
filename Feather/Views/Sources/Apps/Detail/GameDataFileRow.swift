import AltSourceKit
import SwiftUI
import UIKit

struct GameDataFileRow: View {
    let file: ASRepository.App.AdditionalFile
    @ObservedObject private var download = GameDataDownload.shared
    @State private var saving: Export?
    @State private var confirmDelete = false
    @State private var saveError: String?
    @State private var savedFolder = false

    private struct Export: Identifiable {
        let url: URL
        let isFolder: Bool
        let asCopy: Bool
        var id: URL { url }
    }

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
                        if matches, extractsArchive, let zip = download.exportURL {
                            Button {
                                saveError = nil
                                saving = Export(url: zip, isFolder: false, asCopy: false)
                            } label: {
                                Label("Сохранить исходный ZIP", systemImage: "archivebox")
                            }
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(download.ready ? "Удалить файл" : "Отменить загрузку", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }.accessibilityLabel("Действия с загрузкой").disabled(download.installing || download.pausing)
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
                    Text(download.preparedFolder == nil ? "Файл скачан" : "Папка готова к переносу")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        saveError = nil
                        guard let source = download.exportURL else {
                            saveError = "Не удалось открыть скачанный файл."
                            return
                        }
                        if extractsArchive { prepareAndExport() }
                        else { saving = Export(url: source, isFolder: false, asCopy: true) }
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
                    if download.pausing {
                        ProgressView("Сохраняем паузу…")
                    } else if !download.working {
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
            if matches, let status = download.resumeStatus {
                Text(status).font(.footnote).foregroundStyle(.secondary)
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
        .sheet(item: $saving) { item in
            GameDataExporter(url: item.url, asCopy: item.asCopy) { result in
                saving = nil
                guard let result else { return }
                if item.isFolder && result.lastPathComponent != item.url.lastPathComponent {
                    saveError = "Папка перенесена под другим именем. В «Файлах» назови её \(item.url.lastPathComponent). ZIP сохранён."
                    return
                }
                download.completeExport(of: item.url)
                savedFolder = item.isFolder
            }
        }
    }

    private func prepareAndExport() {
        Task { @MainActor in
            do {
                let folder = try await download.prepareFolder()
                saving = Export(url: folder, isFolder: true, asCopy: false)
            } catch {
                saveError = (error as? GameArchive.Failure)?.localizedDescription
                    ?? "Не удалось сохранить папку. ZIP остался на iPhone. Проверь свободное место и попробуй снова."
            }
        }
    }
}

struct GameDataExporter: UIViewControllerRepresentable {
    let url: URL
    var asCopy = true
    let finished: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: asCopy)
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
