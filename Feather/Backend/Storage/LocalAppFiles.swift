import Foundation

// Only directories created by our handlers belong to work cleanup. NSURLSession,
// CFNetwork, image caches and third-party temporary files must be left alone.
enum LocalAppFiles {
    static func workDirectories(in root: URL = FileManager.default.temporaryDirectory) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).filter { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return false }
            let name = url.lastPathComponent
            if name == "FeatherDownloads" { return true }
            for prefix in ["FeatherImport_", "FeatherSigning_", "FeatherInstall_", "FeatherTweak_"] {
                if name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil { return true }
            }
            return false
        }
    }

    static func clearWork(in root: URL = FileManager.default.temporaryDirectory) throws {
        for directory in try workDirectories(in: root) { try FileManager.default.removeItem(at: directory) }
    }

    // Keep container roots, including orphaned app folders left after interrupted imports.
    static func clearChildren(in root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: child)
        }
    }

    static func size(of root: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var bytes: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { files.skipDescendants(); continue }
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        return bytes
    }

    static func snapshot(documents: URL = URL.documentsDirectory, temporary: URL = FileManager.default.temporaryDirectory, transfers: URL = URL.applicationSupportDirectory.appendingPathComponent("FizerDownloads")) -> LocalStorageSnapshot {
        let apps = size(of: documents.appendingPathComponent("Signed")) + size(of: documents.appendingPathComponent("Unsigned"))
        let archives = size(of: documents.appendingPathComponent("Archives"))
        let work = ((try? workDirectories(in: temporary)) ?? []).reduce(Int64(0)) { $0 + size(of: $1) }
        return LocalStorageSnapshot(apps: apps, archives: archives, work: work, transfers: size(of: transfers), other: max(0, size(of: documents) - apps - archives))
    }
}

struct LocalStorageSnapshot: Sendable {
    var apps: Int64 = 0
    var archives: Int64 = 0
    var work: Int64 = 0
    var transfers: Int64 = 0
    var other: Int64 = 0
    var total: Int64 { apps + archives + work + transfers + other }
}
