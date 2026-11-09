import AltSourceKit
import SwiftUI
import UIKit

struct GameDataFileRow: View {
    let file: ASRepository.App.AdditionalFile
    @ObservedObject private var download = GameDataDownload.shared
    @State private var saving = false
    @State private var confirmDelete = false

    private var matches: Bool {
        download.transfer?.share == file.url && download.transfer?.size == file.size
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
                    }.accessibilityLabel("Действия с загрузкой")
                } else {
                    Button { download.start(share: file.url, size: file.size) } label: {
                        AdditionalFileAction(title: "Скачать", icon: "arrow.down")
                    }.buttonStyle(.plain)
                }
            }
            if matches {
                if download.ready {
                    Text("Файл скачан").font(.subheadline).foregroundStyle(.secondary)
                    Button { saving = download.exportURL != nil } label: {
                        AdditionalFileAction(title: "Сохранить в Файлы", icon: "folder")
                    }.buttonStyle(.plain)
                } else {
                    let fraction = min(1, Double(download.received) / Double(file.size))
                    ProgressView(value: fraction) {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    }
                    if !download.working {
                        Button { download.start(share: file.url, size: file.size) } label: {
                            AdditionalFileAction(title: "Продолжить", icon: "arrow.down")
                        }.buttonStyle(.plain)
                    }
                }
            } else if download.transfer != nil {
                Text("Удалите прежнюю загрузку, чтобы скачать этот файл.").font(.footnote).foregroundStyle(.secondary)
            } else if download.working {
                ProgressView("Получаем ссылку…")
            }
            if let error = download.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .confirmationDialog("Удалить скачанную часть с iPhone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { download.discard() }
        }
        .sheet(isPresented: $saving) {
            if let url = download.exportURL {
                GameDataExporter(url: url) { saved in
                    saving = false
                    if saved { download.discard() }
                }
            }
        }
    }
}

private struct GameDataExporter: UIViewControllerRepresentable {
    let url: URL
    let finished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (Bool) -> Void

        init(finished: @escaping (Bool) -> Void) { self.finished = finished }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finished(!urls.isEmpty)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finished(false)
        }
    }
}
