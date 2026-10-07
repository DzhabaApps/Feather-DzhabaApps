import Foundation

// Only download metadata and received packages live here, outside temporary/cache cleanup.
struct BackgroundDownloadRecord: Codable {
    let token: UUID
    let id: String
    let url: URL
    let source: URL
    let displayName: String
}

final class BackgroundDownloadStore {
    let root: URL
    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("FizerDownloads", isDirectory: true)) {
        self.root = root
    }
    func save(_ record: BackgroundDownloadRecord) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(record).write(to: metadataURL(record), options: .atomic)
    }
    func records() -> [BackgroundDownloadRecord] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let record = try? JSONDecoder().decode(BackgroundDownloadRecord.self, from: data),
                      url.lastPathComponent == record.token.uuidString + ".json" else { return nil }
                return record
            }
    }
    func packageURL(_ record: BackgroundDownloadRecord) -> URL {
        root.appendingPathComponent(record.token.uuidString, isDirectory: true).appendingPathComponent("package.ipa")
    }
    func receive(_ location: URL, for record: BackgroundDownloadRecord) throws {
        try save(record)
        let destination = packageURL(record)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: location, to: destination)
    }
    func isReady(_ record: BackgroundDownloadRecord) -> Bool {
        FileManager.default.fileExists(atPath: packageURL(record).path)
    }
    func remove(_ record: BackgroundDownloadRecord) throws {
        let directory = packageURL(record).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        if FileManager.default.fileExists(atPath: metadataURL(record).path) { try FileManager.default.removeItem(at: metadataURL(record)) }
    }
    private func metadataURL(_ record: BackgroundDownloadRecord) -> URL {
        root.appendingPathComponent(record.token.uuidString + ".json")
    }
}
