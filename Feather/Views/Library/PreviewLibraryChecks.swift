import Foundation
import CoreData
import Nuke

// Synthetic fixtures are reachable only under the isolated preview bundle identity.
@MainActor
enum PreviewLibraryChecks {
    static func seedReadyApp() {
        guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview" else { return }
        let source = URL(string: "https://example.invalid/ready-preview")!
        guard RepositoryInstallCoordinator.shared.libraryApp(for: source) == nil else { return }
        let uuid = UUID().uuidString
        let directory = FileManager.default.signed(uuid).appendingPathComponent("Preview.app")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier":"preview.ready","CFBundleName":"Готовое приложение","CFBundleShortVersionString":"1.0"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: directory.appendingPathComponent("Info.plist"))
            Storage.shared.addSigned(uuid: uuid, source: source, appName: "Готовое приложение", appIdentifier: "preview.ready", appVersion: "1.0") { _ in }
        } catch { }
    }
    static func clearAndCheck() async {
        guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview", ProcessInfo.processInfo.environment["FIZER_PREVIEW_SCREEN"] == "cache-check" else { return }
        for _ in 0..<50 {
            if !DownloadManager.shared.isRestoring { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        var result = ["cleared": false, "credentialsPreserved": false, "systemTemporaryPreserved": false, "iconsPreserved": false, "orphansRemoved": false]
        do {
            guard !DownloadManager.shared.isRestoring, DownloadManager.shared.downloads.isEmpty, !RepositoryInstallCoordinator.shared.isBusy else { throw CocoaError(.fileWriteUnknown) }
            let context = Storage.shared.context
            func count(_ entity: String) throws -> Int { try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity)) }
            guard try count("Imported") > 0, try count("Signed") > 0 else { throw CocoaError(.fileReadUnknown) }
            let certificate = CertificatePair(context: context)
            certificate.uuid = UUID().uuidString
            certificate.date = .now
            certificate.expiration = .now.addingTimeInterval(3600)
            certificate.ppQCheck = false
            let signed = try context.fetch(Signed.fetchRequest()).first
            signed?.certificate = certificate
            try context.save()
            let certificateCount = try count("CertificatePair")
            let marker = FileManager.default.certificates.appendingPathComponent("preview-preservation.txt")
            try Data("synthetic-credential-marker".utf8).write(to: marker)
            UserDefaults.standard.set("paid-period-marker", forKey: "Fizer.CacheTest.Subscription")
            let orphan = FileManager.default.signed(UUID().uuidString)
            try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: orphan.appendingPathComponent("orphan.dat"))
            let systemDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NSURLSession-PreservationFixture")
            try FileManager.default.createDirectory(at: systemDirectory, withIntermediateDirectories: true)
            let systemFile = systemDirectory.appendingPathComponent("download.tmp")
            try Data("session-state".utf8).write(to: systemFile)
            let icon = Data("cached-catalog-icon".utf8)
            guard let imageCache = ImagePipeline.shared.configuration.dataCache else { throw CocoaError(.fileReadUnknown) }
            imageCache.storeData(icon, for: "Fizer.CacheTest.Icon")
            try Storage.shared.clearDownloadedApps()
            // Exercise the actual public work-cleaning entry point too.
            ResetView.clearWorkCache()
            result["cleared"] = try count("Imported") == 0 && count("Signed") == 0
            result["orphansRemoved"] = !FileManager.default.fileExists(atPath: orphan.path)
            result["systemTemporaryPreserved"] = (try Data(contentsOf: systemFile)) == Data("session-state".utf8)
            result["iconsPreserved"] = imageCache.cachedData(for: "Fizer.CacheTest.Icon") == icon
            // A subsequent download can still create a file in the same session folder.
            try Data("next-download".utf8).write(to: systemDirectory.appendingPathComponent("next.tmp"))
            try FileManager.default.removeItem(at: systemDirectory)
            imageCache.removeData(for: "Fizer.CacheTest.Icon")
            let data = try Data(contentsOf: marker)
            result["credentialsPreserved"] = try count("CertificatePair") == certificateCount && !certificate.isDeleted && data == Data("synthetic-credential-marker".utf8) && UserDefaults.standard.string(forKey: "Fizer.CacheTest.Subscription") == "paid-period-marker"
            try FileManager.default.removeItem(at: marker)
            context.delete(certificate)
            try context.save()
        } catch { }
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("cache-test-result.json"), options: .atomic)
        }
    }
}
