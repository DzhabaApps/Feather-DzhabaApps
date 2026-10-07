import SwiftUI
import CoreData
import Combine

// A single presenter at the app root also works for repository cells hosted by UIKit.
// The source URL survives relaunches in the existing Core Data model.
final class RepositoryInstallCoordinator: ObservableObject {
	static let shared = RepositoryInstallCoordinator()
	@Published var installApp: AnyApp?
	@Published private(set) var signingName: String?
	@Published private(set) var libraryRevision = 0
	private var observer: AnyCancellable?

	private init() {
		observer = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: Storage.shared.context)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in self?.libraryRevision += 1 }
	}

	var isBusy: Bool { signingName != nil || installApp != nil }

	func libraryApp(for source: URL) -> AppInfoPresentable? {
		// Prefer the unsigned original so changed signing settings are applied on retry.
		for entity in ["Imported", "Signed"] {
			let request = NSFetchRequest<NSManagedObject>(entityName: entity)
			request.predicate = NSPredicate(format: "source == %@", source as NSURL)
			request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
			if let results = try? Storage.shared.context.fetch(request) {
				for case let app as AppInfoPresentable in results {
					if let directory = Storage.shared.getAppDirectory(for: app), FileManager.default.fileExists(atPath: directory.path) { return app }
				}
			}
		}
		return nil
	}

	func install(_ app: AppInfoPresentable) {
		guard FeatherAccessManager.shared.permitsAccess() else { return }
		guard !isBusy else { return }
		if app.isSigned, let cert = Storage.shared.getCertificate(from: app), !cert.revoked, (cert.expiration ?? .distantPast) > .now {
			installApp = AnyApp(base: app)
			return
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
		signingName = app.name ?? .localized("Unknown")
		FR.signPackageFile(app, using: options, icon: nil, certificate: cert) { [weak self] error, signedApp in
			guard let self else { return }
			self.signingName = nil
			if let error { self.showError(error.localizedDescription); return }
			guard let signedApp else { self.showError(.localized("Signed file not found")); return }
			guard FeatherAccessManager.shared.permitsAccess() else { return }
			// Keep the signed copy for install retries even when the imported copy is removed.
			if options.post_deleteAppAfterSigned && !app.isSigned { Storage.shared.deleteApp(for: app) }
			self.installApp = AnyApp(base: signedApp)
		}
	}

	private func showError(_ message: String) {
		UIAlertController.showAlertWithOk(title: .localized("Install"), message: message)
	}
}
