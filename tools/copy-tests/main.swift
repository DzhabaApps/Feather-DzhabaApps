import Foundation

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ description: String) rethrows {
    checks += 1
    if try !condition() { fatalError(description) }
}
func rejects(_ description: String, _ operation: () throws -> Void) {
    checks += 1
    do { try operation(); fatalError(description) } catch { }
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let file = root.appendingPathComponent("ApplicationSupport/FizerCopies/copies.json")
let store = AppCopyStore(fileURL: file)
let origin = "net.whatsapp.WhatsApp"
try check(store.copies(for: origin).isEmpty, "Fresh installs have no copies")
let first = try store.create(originalIdentifier: origin, name: "  Рабочий WhatsApp  ")
check(first.identifier == origin + ".copy1" && first.name == "Рабочий WhatsApp", "First copy has a stable identifier and trimmed name")
let second = try store.create(originalIdentifier: origin, name: "Личный WhatsApp")
check(second.identifier == origin + ".copy2", "Second copy is distinct")
let restarted = AppCopyStore(fileURL: file)
try check(restarted.copies(for: origin) == [first, second], "Names and identities survive restart and new IPA URLs/versions")
try check(restarted.originalIdentifier(for: first.identifier) == origin, "Clone resolves to its original")
try check(restarted.originalIdentifier(for: "com.example.copy1") == "com.example.copy1", "An unknown real ID ending in copy1 must not be stripped")
rejects("Empty names must fail") { _ = try store.create(originalIdentifier: origin, name: " \n ") }
rejects("Long names must fail") { _ = try store.create(originalIdentifier: origin, name: String(repeating: "я", count: 61)) }
rejects("Duplicate names must fail") { _ = try store.create(originalIdentifier: origin, name: "рабочий whatsapp") }
rejects("Invalid original identifiers must fail") { _ = try store.create(originalIdentifier: "bad..app", name: "Invalid") }
rejects("Overlong identifiers must fail") { _ = try store.create(originalIdentifier: "com." + String(repeating: "a", count: 250), name: "Too long") }
let youtube = try store.create(originalIdentifier: "com.google.ios.youtube", name: "Рабочий WhatsApp")
check(youtube.number == 1, "Numbering and names are independent per original application")
try store.forget(first)
try check(store.copies(for: origin) == [second], "Forget hides only the selected copy")
try check(store.originalIdentifier(for: first.identifier) == origin, "Forgotten copies retain provenance for surviving library files")
let third = try restarted.create(originalIdentifier: origin, name: "Рабочий WhatsApp")
check(third.identifier == origin + ".copy3", "A forgotten identifier is never reused")
let fifth = try store.create(originalIdentifier: origin, name: "Пятая", reservedIdentifiers: [origin + ".copy4"])
check(fifth.number == 5, "Identifiers already used by local apps are skipped")
rejects("Stale forget must fail") { try store.forget(first) }

let documents = root.appendingPathComponent("Documents/Unsigned")
try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
try Data(repeating: 1, count: 1024).write(to: documents.appendingPathComponent("app.dat"))
try LocalAppFiles.clearChildren(in: documents)
try check(AppCopyStore(fileURL: file).copies(for: origin) == [second, third, fifth], "Downloaded-file cleanup must preserve the registry")
let byteCount = try Data(contentsOf: file).count
check(byteCount < 4096, "A handful of copies needs only a few KB")

let valid = try Data(contentsOf: file)
try Data("broken".utf8).write(to: file)
rejects("Corrupt registry must not reset numbering") { _ = try store.create(originalIdentifier: origin, name: "Unsafe") }
let corrupted = try Data(contentsOf: file)
check(corrupted == Data("broken".utf8), "Corruption is preserved for recovery, never overwritten")
try valid.write(to: file)
var json = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
json["version"] = 2
try JSONSerialization.data(withJSONObject: json).write(to: file)
rejects("Unknown schema must not reset numbering") { _ = try store.allCopies() }
json["version"] = 1
var entries = json["copies"] as! [[String: Any]]
entries.append(entries[0]); json["copies"] = entries
try JSONSerialization.data(withJSONObject: json).write(to: file)
rejects("Duplicate registry identifiers must fail") { _ = try store.allCopies() }
try valid.write(to: file)
print("App copy registry: \(checks) checks passed; five records use \(byteCount) bytes")
