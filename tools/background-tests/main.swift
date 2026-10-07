import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let store = BackgroundDownloadStore(root: root.appendingPathComponent("persistent"))
let url = URL(string: "https://example.org/app.ipa?token=fixture")!
let first = BackgroundDownloadRecord(token: UUID(), id: "source/version?not-a-path", url: url, source: url, displayName: "Приложение")
let second = BackgroundDownloadRecord(token: UUID(), id: "second", url: url, source: url, displayName: "Другое")
try store.save(first); try store.save(second)
assert(store.records().count == 2)
assert(!store.isReady(first))
let systemTemp = root.appendingPathComponent("system-temp.ipa")
try Data([1,2,3,4]).write(to: systemTemp)
try store.receive(systemTemp, for: first)
assert(!FileManager.default.fileExists(atPath: systemTemp.path))
let restarted = BackgroundDownloadStore(root: store.root)
assert(restarted.records().contains { $0.token == first.token && $0.id == first.id })
assert(restarted.isReady(first))
let received = try Data(contentsOf: restarted.packageURL(first))
assert(received == Data([1,2,3,4]))
// A broken metadata file cannot hide other downloads, and record IDs never become paths.
try Data("not JSON".utf8).write(to: store.root.appendingPathComponent("broken.json"))
assert(restarted.records().count == 2)
assert(restarted.packageURL(first).path.hasPrefix(store.root.path + "/"))
try restarted.remove(second)
assert(restarted.isReady(first) && restarted.records().count == 1)
try restarted.remove(first)
assert(!restarted.isReady(first) && restarted.records().isEmpty)
print("Background download persistence: receive, relaunch, corrupt metadata isolation and cancellation passed")
