import Foundation
import ZIPFoundation

enum GameArchive {
    enum Failure: LocalizedError {
        case invalid, noSpace, destinationExists, destinationUnavailable, rollbackFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalid: return "Архив повреждён или не содержит одну готовую папку."
            case .noSpace: return "Не хватает свободного места для распаковки. Скачанный ZIP сохранён."
            case .destinationExists: return "Такая папка уже есть в выбранном месте."
            case .destinationUnavailable: return "Не удалось открыть выбранную папку для записи. Скачанный ZIP сохранён."
            case .rollbackFailed(let path): return "Не удалось вернуть прежнюю папку на место. Её копия сохранена в \(path)."
            }
        }
    }

    final class Destination: @unchecked Sendable {
        let url: URL

        init(_ url: URL) throws {
            self.url = url
            guard url.startAccessingSecurityScopedResource() else { throw Failure.destinationUnavailable }
        }

        deinit { url.stopAccessingSecurityScopedResource() }
    }

    static func save(_ zip: URL, in destination: Destination, replacing: Bool, transferID: UUID,
                     progress: @escaping (Double) -> Void) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: destination.url, options: [], error: &coordinationError) { folder in
            result = Result { try install(zip, in: folder, replacing: replacing, transferID: transferID, progress: progress) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw Failure.destinationUnavailable }
        try result.get()
    }

    static func install(_ zip: URL, in folder: URL, replacing: Bool, transferID: UUID,
                        progress: (Double) -> Void = { _ in }) throws {
        let archive = try Archive(url: zip, accessMode: .read)
        let expectedCount = try entryCount(in: zip)
        guard expectedCount > 0, expectedCount <= 100_000 else { throw Failure.invalid }
        var entries: [(Entry, [String])] = []
        var paths = Set<String>()
        var total: UInt64 = 0
        var seen = 0
        for entry in archive {
            seen += 1
            guard seen <= expectedCount else { throw Failure.invalid }
            let path = try components(of: entry)
            if path.first == "__MACOSX" { continue }
            let key = path.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
            let (size, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            guard paths.insert(key).inserted, !overflow else { throw Failure.invalid }
            total = size
            entries.append((entry, path))
        }
        guard seen == expectedCount, let root = entries.first?.1.first,
              entries.allSatisfy({ $0.1.first == root }),
              entries.contains(where: { $0.0.type == .file && $0.1.count > 1 }) else { throw Failure.invalid }

        let fm = FileManager.default
        let target = folder.appendingPathComponent(root, isDirectory: true)
        let staging = folder.appendingPathComponent(".DRStore-\(transferID.uuidString)", isDirectory: true)
        let backup = staging.appendingPathComponent("previous", isDirectory: true)
        let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
        if fm.fileExists(atPath: backup.path) {
            guard !fm.fileExists(atPath: target.path) else { throw Failure.rollbackFailed(backup.path) }
            try fm.moveItem(at: backup, to: target)
        }
        let hasTarget = fm.fileExists(atPath: target.path)
        if hasTarget && !replacing { throw Failure.destinationExists }
        if let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           free >= 0, UInt64(free) < total { throw Failure.noSpace }
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        var keepBackup = false
        defer { if !keepBackup { try? fm.removeItem(at: staging) } }

        var written: UInt64 = 0
        var lastUpdate = -Double.infinity
        for (entry, path) in entries {
            let output = path.reduce(extracted) { $0.appendingPathComponent($1) }
            try extract(entry, from: archive, to: output) { count in
                written += count
                let now = ProcessInfo.processInfo.systemUptime
                if total > 0, now - lastUpdate >= 0.25 {
                    lastUpdate = now
                    progress(min(0.99, Double(written) / Double(total)))
                }
            }
        }
        let ready = extracted.appendingPathComponent(root, isDirectory: true)
        if hasTarget { try fm.moveItem(at: target, to: backup) }
        do {
            try fm.moveItem(at: ready, to: target)
        } catch {
            if hasTarget {
                do { try fm.moveItem(at: backup, to: target) }
                catch {
                    keepBackup = true
                    throw Failure.rollbackFailed(backup.path)
                }
            }
            throw error
        }
        progress(1)
    }

    private static func components(of entry: Entry) throws -> [String] {
        let name = entry.type == .directory && entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
        let parts = name.components(separatedBy: "/")
        guard entry.type == .file || entry.type == .directory,
              entry.type != .file || parts.count > 1,
              parts.allSatisfy({ part in
                  !part.isEmpty && part != "." && part != ".." && !part.contains("\\") && !part.contains(":")
                      && !part.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
              }),
              parts.first?.hasPrefix(".") == false else { throw Failure.invalid }
        return parts
    }

    private static func extract(_ entry: Entry, from archive: Archive, to output: URL,
                                didWrite: (UInt64) -> Void) throws {
        let fm = FileManager.default
        if entry.type == .directory {
            try fm.createDirectory(at: output, withIntermediateDirectories: true)
            return
        }
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: output.path), fm.createFile(atPath: output.path, contents: nil) else {
            throw Failure.invalid
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        var written: UInt64 = 0
        let crc = try archive.extract(entry, bufferSize: 1024 * 1024) { bytes in
            guard UInt64(bytes.count) <= entry.uncompressedSize - written else { throw Failure.invalid }
            try handle.write(contentsOf: bytes)
            written += UInt64(bytes.count)
            didWrite(UInt64(bytes.count))
        }
        guard written == entry.uncompressedSize, crc == entry.checksum else { throw Failure.invalid }
        try handle.synchronize()
    }

    // The archive iterator stops at a malformed entry. Check its count against the ZIP footer.
    private static func entryCount(in url: URL) throws -> Int {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let length = try file.seekToEnd()
        let tailSize = Int(min(length, 65_557))
        guard tailSize >= 22 else { throw Failure.invalid }
        let start = length - UInt64(tailSize)
        try file.seek(toOffset: start)
        guard let data = try file.read(upToCount: tailSize), data.count == tailSize else { throw Failure.invalid }
        func value(_ bytes: Data, _ index: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(0) { $0 | UInt64(bytes[index + $1]) << (8 * $1) }
        }
        for offset in stride(from: tailSize - 22, through: 0, by: -1)
        where value(data, offset, 4) == 0x06054b50 && offset + 22 + Int(value(data, offset + 20, 2)) == tailSize {
            guard value(data, offset + 4, 4) == 0 else { throw Failure.invalid }
            let count = value(data, offset + 10, 2)
            guard count == value(data, offset + 8, 2) else { throw Failure.invalid }
            if count != 0xffff { return Int(count) }
            let end = start + UInt64(offset)
            guard end >= 20 else { throw Failure.invalid }
            try file.seek(toOffset: end - 20)
            guard let locator = try file.read(upToCount: 20), locator.count == 20,
                  value(locator, 0, 4) == 0x07064b50, value(locator, 4, 4) == 0,
                  value(locator, 16, 4) == 1 else { throw Failure.invalid }
            let zip64 = value(locator, 8, 8)
            guard zip64 < end else { throw Failure.invalid }
            try file.seek(toOffset: zip64)
            guard let record = try file.read(upToCount: 56), record.count == 56,
                  value(record, 0, 4) == 0x06064b50, value(record, 16, 8) == 0,
                  value(record, 24, 8) == value(record, 32, 8),
                  let entries = Int(exactly: value(record, 32, 8)) else { throw Failure.invalid }
            return entries
        }
        throw Failure.invalid
    }
}
