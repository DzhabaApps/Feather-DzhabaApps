"""Exercise the actual incoming-file coordinator with isolated access/library stubs."""
import pathlib
import plistlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root/'Feather/FeatherApp.swift').read_text()
coordinator = source.split('final class IncomingPackageImporter: ObservableObject {', 1)[1].split('\nclass AppDelegate:', 1)[0]
coordinator = 'final class IncomingPackageImporter: ObservableObject {' + coordinator
info = plistlib.loads((root/'Feather/Resources/Info.plist').read_bytes())
assert 'com.apple.itunes.ipa' in info['CFBundleDocumentTypes'][0]['LSItemContentTypes']
assert info['LSSupportsOpeningDocumentsInPlace'] is False
assert info['UISupportsDocumentBrowser'] is False
assert info['CFBundleDocumentTypes'][0]['CFBundleTypeExtensions'] == ['ipa']
assert 'application/octet-stream' not in info['UTExportedTypeDeclarations'][0]['UTTypeTagSpecification'].get('public.mime-type', [])
scene_adapter = 'final class IncomingFileSceneDelegate:' + source.split('final class IncomingFileSceneDelegate:', 1)[1]
harness = r'''
import Foundation
import Combine
enum TabEnum: String { case library }
final class FeatherAccessManager {
    static let shared = FeatherAccessManager()
    var active = true
    func permitsAccess() -> Bool { active }
    func refresh() async {}
}
final class Download {}
final class DownloadManager {
    static let shared = DownloadManager()
    func startArchive(from url: URL, id: String) -> Download { Download() }
    func cancelDownload(_ download: Download) {}
    var startedDownloads: [URL] = []
    func startDownload(from url: URL) -> Download { startedDownloads.append(url); return Download() }
}
// The adapters below run the actual scene-delegate methods on macOS. The iPhone
// build separately checks their conformance against UIKit's real declarations.
protocol UIWindowSceneDelegate {}
class UIScene: NSObject {
    struct ConnectionOptions { var urlContexts: Set<UIOpenURLContext> }
}
class UISceneSession: NSObject {}
final class UIOpenURLContext: NSObject {
    let url: URL
    init(_ url: URL) { self.url = url }
}
extension URL {
    func validatedScheme(after marker: String) -> String? {
        guard let range = absoluteString.range(of: marker) else { return nil }
        return String(absoluteString[range.upperBound...])
    }
}
enum FR {
    static var imported: [Data] = []
    static func handlePackageFile(_ url: URL, download: Download, completion: @escaping (Error?) -> Void) {
        do {
            precondition(url.pathExtension == "ipa")
            imported.append(try Data(contentsOf: url))
            completion(nil)
        } catch { completion(error) }
    }
}
'''
tests = r'''
@main struct Checks {
    @MainActor static func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        fatalError("Incoming import timed out")
    }
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Telegram.IPA")
        let bytes = Data("incoming fixture".utf8)
        try bytes.write(to: url)
        let importer = IncomingPackageImporter.shared
        importer.receive(url)
        importer.receive(url) // Duplicate Open In callbacks must not import twice.
        try await waitFor { FR.imported.count == 1 }
        precondition(FR.imported == [bytes])
        precondition(FileManager.default.fileExists(atPath: url.path)) // External original retained.
        FeatherAccessManager.shared.active = false
        let second = folder.appendingPathComponent("pending.ipa")
        try bytes.write(to: second)
        importer.showMessage = false
        importer.receive(second)
        try await waitFor { importer.showMessage }
        precondition(FR.imported.count == 1)
        try FileManager.default.removeItem(at: second) // Staged copy must survive source removal.
        FeatherAccessManager.shared.active = true
        importer.processPending()
        try await waitFor { FR.imported.count == 2 }
        importer.receive(folder.appendingPathComponent("missing.ipa"))
        try await waitFor { importer.message.contains("IPA:") }
        precondition(FR.imported.count == 2)
        let delegate = IncomingFileSceneDelegate()
        let scene = UIScene()
        let cold = folder.appendingPathComponent("cold.ipa")
        try bytes.write(to: cold)
        delegate.scene(scene, willConnectTo: UISceneSession(),
                       options: UIScene.ConnectionOptions(urlContexts: [UIOpenURLContext(cold)]))
        try await waitFor { FR.imported.count == 3 }
        let warm = folder.appendingPathComponent("warm.ipa")
        try bytes.write(to: warm)
        let contexts: Set<UIOpenURLContext> = [UIOpenURLContext(warm)]
        delegate.scene(scene, openURLContexts: contexts)
        delegate.scene(scene, openURLContexts: contexts)
        try await waitFor { FR.imported.count == 4 }
        let install = URL(string: "feather://install/https://example.test/app.ipa")!
        precondition(FeatherIncomingURLRouter.open(install))
        precondition(FeatherIncomingURLRouter.open(install))
        precondition(DownloadManager.shared.startedDownloads == [URL(string: "https://example.test/app.ipa")!])
        FeatherAccessManager.shared.active = false
        precondition(!FeatherIncomingURLRouter.open(URL(string: "feather://install/https://example.test/blocked.ipa")!))
        precondition(DownloadManager.shared.startedDownloads.count == 1)
        precondition(!FeatherIncomingURLRouter.open(URL(string: "https://example.test/not-a-local-file")!))
        precondition(importer.message.contains("ссылку вместо файла"))
        print("Incoming IPA: uppercase extension, local file access, duplicate delivery, staging, access retry and missing-file error passed")
        print("Incoming scenes: cold start, warm delivery, duplicate events and install links passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='dr-incoming-check-') as folder:
    path = pathlib.Path(folder)
    (path/'check.swift').write_text(harness + coordinator + scene_adapter + tests)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', str(path/'check.swift'), '-o', str(path/'check')], check=True)
    subprocess.run([str(path/'check')], check=True, timeout=30)
