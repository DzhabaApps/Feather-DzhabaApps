import Foundation

struct AppCopy: Codable, Identifiable, Equatable {
    let originalIdentifier: String
    let identifier: String
    let number: Int
    let name: String
    var forgotten = false
    var id: String { identifier }
}

// Independent of downloaded files, catalog URLs, versions and signing credentials.
// Forgotten entries reserve their identifiers: the app may still be on the phone.
final class AppCopyStore {
    static let shared = AppCopyStore(fileURL: URL.applicationSupportDirectory
        .appendingPathComponent("FizerCopies/copies.json"))

    private struct Catalog: Codable {
        var version = 1
        var copies: [AppCopy] = []
    }
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func allCopies() throws -> [AppCopy] { try read().copies }

    func originalIdentifier(for identifier: String) throws -> String {
        try allCopies().first { $0.identifier == identifier }?.originalIdentifier ?? identifier
    }

    func copies(for originalIdentifier: String) throws -> [AppCopy] {
        try allCopies().filter { $0.originalIdentifier == originalIdentifier && !$0.forgotten }
            .sorted { $0.number < $1.number }
    }

    func nextNumber(for originalIdentifier: String) throws -> Int {
        let previous = try allCopies().filter { $0.originalIdentifier == originalIdentifier }.map(\.number).max() ?? 0
        guard previous < Int.max else { throw CopyError.invalidIdentifier }
        return previous + 1
    }

    @discardableResult
    func create(originalIdentifier: String, name: String, reservedIdentifiers: Set<String> = []) throws -> AppCopy {
        var catalog = try read()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { throw CopyError.invalidName }
        guard !catalog.copies.contains(where: {
            !$0.forgotten && $0.originalIdentifier == originalIdentifier && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { throw CopyError.duplicateName }
        var number = try nextNumber(for: originalIdentifier)
        let occupied = reservedIdentifiers.union(catalog.copies.map(\.identifier)).union(catalog.copies.map(\.originalIdentifier))
        while occupied.contains("\(originalIdentifier).copy\(number)") {
            guard number < Int.max else { throw CopyError.invalidIdentifier }
            number += 1
        }
        let identifier = "\(originalIdentifier).copy\(number)"
        guard Self.validIdentifier(originalIdentifier), Self.validIdentifier(identifier) else { throw CopyError.invalidIdentifier }
        let copy = AppCopy(originalIdentifier: originalIdentifier, identifier: identifier, number: number, name: name)
        catalog.copies.append(copy)
        try write(catalog)
        return copy
    }

    func forget(_ copy: AppCopy) throws {
        var catalog = try read()
        guard let index = catalog.copies.firstIndex(where: { $0.identifier == copy.identifier && $0 == copy }) else {
            throw CopyError.missingCopy
        }
        catalog.copies[index].forgotten = true
        try write(catalog)
    }

    private static func validIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 255 &&
        identifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }

    private func read() throws -> Catalog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Catalog() }
        // A damaged/unknown registry must never silently reset numbering.
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: fileURL))
        guard catalog.version == 1,
              Set(catalog.copies.map(\.identifier)).count == catalog.copies.count,
              catalog.copies.allSatisfy({
                  $0.number > 0 && Self.validIdentifier($0.originalIdentifier) && Self.validIdentifier($0.identifier) &&
                  $0.identifier == "\($0.originalIdentifier).copy\($0.number)" &&
                  !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 60
              }) else { throw CopyError.invalidRegistry }
        return catalog
    }

    private func write(_ catalog: Catalog) throws {
        let data = try JSONEncoder().encode(catalog)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    enum CopyError: Error, LocalizedError {
        case invalidName, duplicateName, invalidIdentifier, invalidRegistry, missingCopy
        var errorDescription: String? {
            switch self {
            case .invalidName: return "Введите название копии от 1 до 60 символов."
            case .duplicateName: return "Копия с таким названием уже есть. Выберите другое название."
            case .invalidIdentifier: return "Не удалось создать отдельную копию этого приложения."
            case .invalidRegistry: return "Не удалось прочитать список копий. Обратитесь в поддержку."
            case .missingCopy: return "Копия больше не находится в списке. Откройте выбор установки снова."
            }
        }
    }
}
