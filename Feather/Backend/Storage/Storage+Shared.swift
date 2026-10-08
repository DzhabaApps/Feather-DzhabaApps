//
//  Storage+Shared.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import CoreData

// MARK: - Class extension: Apps (Shared)
extension Storage {
    // This deletes local app files/rows only; subscription and installation credentials stay.
    func clearDownloadedApps() throws {
        guard !DownloadManager.shared.isRestoring, DownloadManager.shared.downloads.isEmpty,
              !RepositoryInstallCoordinator.shared.isBusy else { throw CocoaError(.fileWriteUnknown) }
        for entity in ["Imported", "Signed"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            for object in try context.fetch(request) {
                guard let app = object as? AppInfoPresentable else { continue }
                if let directory = getUuidDirectory(for: app), FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
                context.delete(object)
                try context.save()
            }
        }
        // Database rows may already be gone after a failed import or older cleanup.
        try LocalAppFiles.clearChildren(in: FileManager.default.signed)
        try LocalAppFiles.clearChildren(in: FileManager.default.unsigned)
        try LocalAppFiles.clearWork()
    }

	func getUuidDirectory(for app: AppInfoPresentable) -> URL? {
		guard let uuid = app.uuid else { return nil }
		return app.isSigned
			? FileManager.default.signed(uuid)
			: FileManager.default.unsigned(uuid)
	}
	
	func getAppDirectory(for app: AppInfoPresentable) -> URL? {
		guard let url = getUuidDirectory(for: app) else { return nil }
		return FileManager.default.getPath(in: url, for: "app")
	}
	
	func deleteApp(for app: AppInfoPresentable) {
		do {
			if let url = getUuidDirectory(for: app) {
				try? FileManager.default.removeItem(at: url)
			}
			if let object = app as? NSManagedObject {
				context.delete(object)
			}
			saveContext()
		}
	}
	
	func getCertificate(from app: AppInfoPresentable) -> CertificatePair? {
		if let signed = app as? Signed {
			return signed.certificate
		}
		return nil
	}
}

// MARK: - Helpers
struct AnyApp: Identifiable {
	let base: AppInfoPresentable
	var archive: Bool = false
	
	var id: String {
		base.uuid ?? UUID().uuidString
	}
}

protocol AppInfoPresentable {
	var source: URL? { get }
	var name: String? { get }
	var version: String? { get }
	var identifier: String? { get }
	var date: Date? { get }
	var icon: String? { get }
	var uuid: String? { get }
	var isSigned: Bool { get }
	
}

extension Signed: AppInfoPresentable {
	var isSigned: Bool { true }
}

extension Imported: AppInfoPresentable {
	var isSigned: Bool { false }
}
