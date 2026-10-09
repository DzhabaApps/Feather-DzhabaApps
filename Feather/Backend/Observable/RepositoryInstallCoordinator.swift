import SwiftUI
import CoreData
import Combine

struct AppInstallRequest: Identifiable {
    let id = UUID()
    let app: AppInfoPresentable
    let originalIdentifier: String
    let originalName: String
}

// A single presenter at the app root also works for repository cells hosted by UIKit.
final class RepositoryInstallCoordinator: ObservableObject {
    static let shared = RepositoryInstallCoordinator()
    @Published var installApp: AnyApp?
    @Published var installRequest: AppInstallRequest?
    @Published private(set) var signingName: String?
    @Published private(set) var libraryRevision = 0
    private var observer: AnyCancellable?
    let copies: AppCopyStore
    private var pendingInstall: (app: AppInfoPresentable, copy: AppCopy?)?

    init(copies: AppCopyStore = .shared) {
        self.copies = copies
        observer = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: Storage.shared.context)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.libraryRevision += 1 }
    }

    var isBusy: Bool { signingName != nil || installApp != nil || installRequest != nil || pendingInstall != nil }

    func libraryApp(for source: URL) -> AppInfoPresentable? {
        guard let knownCopies = try? copies.allCopies() else { return nil }
        // Prefer the common original; a clone is never the catalog's ordinary app.
        for entity in ["Imported", "Signed"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "source == %@", source as NSURL)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            if let results = try? Storage.shared.context.fetch(request) {
                for case let app as AppInfoPresentable in results {
                    if knownCopies.contains(where: { $0.identifier == app.identifier }) { continue }
                    if let directory = Storage.shared.getAppDirectory(for: app), FileManager.default.fileExists(atPath: directory.path) { return app }
                }
            }
        }
        return nil
    }

    func chooseInstallation(_ app: AppInfoPresentable) {
        guard FeatherAccessManager.shared.permitsAccess(), !isBusy else { return }
        do {
            guard let identifier = app.identifier else { throw AppCopyStore.CopyError.invalidIdentifier }
            let original = try copies.originalIdentifier(for: identifier)
            let sourceApp = app.source.flatMap { libraryApp(for: $0) }
            installRequest = AppInstallRequest(app: app, originalIdentifier: original,
                originalName: sourceApp?.name ?? app.name ?? .localized("Unknown"))
        } catch { showError("Не удалось прочитать список копий. Обратитесь в поддержку.") }
    }

    func selectInstallation(_ request: AppInstallRequest, copy: AppCopy? = nil) {
        guard installRequest?.id == request.id, pendingInstall == nil else { return }
        pendingInstall = (request.app, copy)
        installRequest = nil
    }

    // Start after the choice sheet dismisses, so installation has its own presenter.
    func finishInstallationChoice() {
        guard let pending = pendingInstall else { return }
        pendingInstall = nil
        install(pending.app, copy: pending.copy)
    }

    func createCopy(_ request: AppInstallRequest, name: String) throws -> AppCopy {
        guard installRequest?.id == request.id, FeatherAccessManager.shared.permitsAccess() else {
            throw AppCopyStore.CopyError.missingCopy
        }
        var reserved = Set<String>()
        for entity in ["Imported", "Signed"] {
            for case let app as AppInfoPresentable in try Storage.shared.context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)) {
                if let identifier = app.identifier { reserved.insert(identifier) }
            }
        }
        return try copies.create(originalIdentifier: request.originalIdentifier, name: name, reservedIdentifiers: reserved)
    }

    func install(_ requestedApp: AppInfoPresentable, copy: AppCopy? = nil) {
        guard FeatherAccessManager.shared.permitsAccess(), !isBusy else { return }
        var app = requestedApp
        let originalIdentifier: String
        do {
            guard let identifier = app.identifier else { throw AppCopyStore.CopyError.invalidIdentifier }
            originalIdentifier = try copies.originalIdentifier(for: identifier)
            if let copy {
                guard copy.originalIdentifier == originalIdentifier,
                      try copies.copies(for: originalIdentifier).contains(copy) else { throw AppCopyStore.CopyError.missingCopy }
            }
            if identifier != originalIdentifier && identifier != copy?.identifier {
                guard let source = app.source, let original = libraryApp(for: source), original.identifier == originalIdentifier else {
                    showError("Для обычной установки или новой копии скачайте исходное приложение из магазина ещё раз.")
                    return
                }
                app = original
            }
        } catch { showError("Не удалось прочитать список копий. Обратитесь в поддержку."); return }
        if app.isSigned, let cert = Storage.shared.getCertificate(from: app), !cert.revoked, (cert.expiration ?? .distantPast) > .now {
            if copy == nil || app.identifier == copy?.identifier {
                installApp = AnyApp(base: app)
                return
            }
        }
        let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
        guard let cert = Storage.shared.getCertificate(for: index), !cert.revoked, (cert.expiration ?? .distantPast) > .now else {
            showError(.localized("Certificate unavailable explanation"))
            return
        }
        var options = OptionsManager.shared.options
        guard options.signingOption == .default else {
            showError(.localized("Repository signing type explanation"))
            return
        }
        if options.ppqProtection, let identifier = app.identifier, cert.ppQCheck {
            options.appIdentifier = "\(identifier).\(options.ppqString)"
        }
        if let identifier = app.identifier, let replacement = options.identifiers[identifier] { options.appIdentifier = replacement }
        if let name = app.name, let replacement = options.displayNames[name] { options.appName = replacement }
        if let copy {
            // Saved copy identity wins over PPQ and global replacement settings.
            options.appIdentifier = copy.identifier
            options.appName = copy.name
        }
        signingName = copy?.name ?? app.name ?? .localized("Unknown")
        FR.signPackageFile(app, using: options, icon: nil, certificate: cert) { [weak self] error, signedApp in
            guard let self else { return }
            self.signingName = nil
            if error != nil { self.showError("Не удалось подготовить приложение. Попробуйте снова или обратитесь в поддержку через настройки."); return }
            guard let signedApp else { self.showError(.localized("Signed file not found")); return }
            if let copy, signedApp.identifier != copy.identifier {
                Storage.shared.deleteApp(for: signedApp)
                self.showError("Не удалось сохранить идентификатор копии. Установка отменена.")
                return
            }
            guard FeatherAccessManager.shared.permitsAccess() else { return }
            // Keep a common original for other copies instead of redownloading it.
            let hasCopies = ((try? self.copies.copies(for: originalIdentifier)) ?? []).isEmpty == false
            if options.post_deleteAppAfterSigned && !app.isSigned && !hasCopies { Storage.shared.deleteApp(for: app) }
            if let copy, options.post_deleteAppAfterSigned {
                // Discard superseded prepared files for this copy and version only.
                let request = NSFetchRequest<NSManagedObject>(entityName: "Signed")
                request.predicate = NSPredicate(format: "identifier == %@", copy.identifier)
                if let results = try? Storage.shared.context.fetch(request) {
                    for case let old as AppInfoPresentable in results where old.uuid != signedApp.uuid && old.source == signedApp.source {
                        Storage.shared.deleteApp(for: old)
                    }
                }
            }
            self.installApp = AnyApp(base: signedApp)
        }
    }

    private func showError(_ message: String) {
        UIAlertController.showAlertWithOk(title: .localized("Install"), message: message)
    }
}
