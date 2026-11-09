import AltSourceKit
import SwiftUI

/// Small catalog documents are saved independently of the large game-data transfer.
struct AdditionalDocumentRow: View {
    let file: ASRepository.App.AdditionalFile
    @StateObject private var download = AdditionalDocumentDownload()
    @State private var saving = false

    static func supports(_ file: ASRepository.App.AdditionalFile) -> Bool {
        file.extractArchive != true && (1...10_485_760).contains(file.size)
            && file.url.scheme == "https" && file.url.host == "github.com"
            && file.url.user == nil && file.url.password == nil && file.url.port == nil
            && file.url.path.hasPrefix("/DzhabaApps/Dzhaba-Apps/releases/download/")
            && file.url.pathExtension.lowercased() == "json"
            && GameDataSource.safeName(file.url.lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AdditionalFileTitle(file: file)
                if download.working {
                    ProgressView().accessibilityLabel("Скачиваем файл")
                } else if download.savedURL == nil {
                    Button {
                        Task { await download.fetch(file) }
                    } label: {
                        AdditionalFileAction(title: "Скачать", icon: "arrow.down")
                    }.buttonStyle(.plain)
                }
            }
            if download.savedURL != nil {
                Button { saving = true } label: {
                    AdditionalFileAction(title: "Сохранить в Файлы", icon: "folder")
                }.buttonStyle(.plain)
            }
            if let error = download.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $saving) {
            if let url = download.savedURL {
                GameDataExporter(url: url, chooseFolder: false) { destination in
                    saving = false
                    if destination != nil { download.clear() }
                }
            }
        }
    }
}

@MainActor
private final class AdditionalDocumentDownload: ObservableObject {
    @Published private(set) var savedURL: URL?
    @Published private(set) var working = false
    @Published private(set) var error: String?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    deinit { try? FileManager.default.removeItem(at: directory) }

    func fetch(_ file: ASRepository.App.AdditionalFile) async {
        guard !working, savedURL == nil, AdditionalDocumentRow.supports(file) else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            let (temporary, response) = try await URLSession.shared.download(from: file.url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let fm = FileManager.default
            let allowed = ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"]
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let finalURL = http.url, finalURL.scheme == "https", finalURL.port == nil,
                  allowed.contains(finalURL.host ?? ""),
                  (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value == file.size else {
                throw URLError(.badServerResponse)
            }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(file.url.lastPathComponent)
            try fm.moveItem(at: temporary, to: target)
            savedURL = target
        } catch {
            self.error = "Не удалось скачать файл. Проверь интернет и попробуй снова."
        }
    }

    func clear() {
        do {
            try FileManager.default.removeItem(at: directory)
            savedURL = nil
        } catch {
            self.error = "Файл сохранён. Не удалось удалить временную копию."
        }
    }
}
