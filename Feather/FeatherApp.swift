//
//  FeatherApp.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import Nuke
import IDeviceSwift
import OSLog
import CryptoKit

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
	let heartbeat = HeartbeatManager.shared
	
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject private var repositoryInstaller = RepositoryInstallCoordinator.shared
	@StateObject private var access = FeatherAccessManager.shared
	@Environment(\.scenePhase) private var scenePhase
	let storage = Storage.shared

	init() {
		UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
	}
	
	var body: some Scene {
		WindowGroup {
			if let screen = ProcessInfo.processInfo.environment["FIZER_PREVIEW_SCREEN"], Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview" {
				_previewScreen(screen)
					.environment(\.managedObjectContext, storage.context)
					.environment(\.locale, Locale(identifier: "ru"))
			} else {
			VStack {
				DownloadHeaderView(downloadManager: downloadManager)
					.transition(.move(edge: .top).combined(with: .opacity))
				VariedTabbarView()
					.environment(\.managedObjectContext, storage.context)
					.onOpenURL(perform: _handleURL)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
			.environment(\.locale, Locale(identifier: "ru"))
			.overlay {
				if access.state != .active { FeatherAccessView(access: access) }
			}
			.task { await access.refresh(); downloadManager.processForegroundDownloads() }
			.onChange(of: scenePhase) { phase in
				if phase == .active { Task { await access.refresh(); downloadManager.processForegroundDownloads() } }
			}
			.overlay {
				if let name = repositoryInstaller.signingName {
					ZStack {
						Color.black.opacity(0.25).ignoresSafeArea()
						VStack(spacing: 16) {
							ProgressView()
							Text(.localized("Signing" )).font(.headline)
							Text(name).font(.subheadline).lineLimit(2)
						}.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)).padding()
					}
				}
			}
			.sheet(item: $repositoryInstaller.installRequest, onDismiss: repositoryInstaller.finishInstallationChoice) { request in
				AppInstallationChoiceView(request: request, installer: repositoryInstaller)
			}
			.sheet(item: $repositoryInstaller.installApp) { app in
				InstallPreviewView(app: app.base)
					.presentationDetents([.height(220)])
					.presentationDragIndicator(.visible)
			}
			.animation(.smooth, value: downloadManager.downloads.description)
			// dear god help me
			.onAppear {
				if let style = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: "Feather.userInterfaceStyle")) {
					UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
				}
				
				UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9"))
			}
			}
		}
	}

	@ViewBuilder
	private func _previewScreen(_ screen: String) -> some View {
		switch screen {
		case "access-expired": FeatherAccessView(access: access, previewState: .expired, previewExpiry: Date(timeIntervalSince1970: 1799272800))
		case "access-offline": FeatherAccessView(access: access, previewState: .verificationRequired)
        case "access-checking": FeatherAccessView(access: access)
        case "cancellation-check": LibraryView().task { await DownloadManager.shared.runPreviewCancellationChecks() }
		case "library": LibraryView().onAppear { PreviewLibraryChecks.seedReadyApp() }
        case "copies": CopyChoicePreview(creating: false)
        case "new-copy": CopyChoicePreview(creating: true)
        case "cache-check": LibraryView().task { await PreviewLibraryChecks.clearAndCheck() }
        case "background-transfer": LibraryView().onAppear { DownloadManager.shared.startPreviewTransfer() }
        case "store-news": SourcesView(previewCategory: .all, previewNews: true)
        case "app-detail": CatalogDetailPreview()
        case "store": SourcesView(previewCategory: .all)
		case "store-finance": SourcesView(previewCategory: .finance)
		case "store-social": SourcesView(previewCategory: .social)
		case "store-games": SourcesView(previewCategory: .games)
		case "installation": NavigationStack { InstallationPreferencesView() }
        case "storage": NavigationStack { StorageSettingsView() }
		case "advanced": NavigationStack { AdvancedSettingsView() }
		case "help": NavigationStack { FizerHelpView() }
		default: SettingsView(previewState: .active, previewExpiry: Date(timeIntervalSince1970: 1799272800))
		}
	}
	
	private func _handleURL(_ url: URL) {
		guard access.permitsAccess() else { return }
		if url.scheme == "feather" || url.scheme == "fizer-preview" {
			/// feather://install/<url.ipa>
			if
				let fullPath = url.validatedScheme(after: "/install/"),
				let downloadURL = URL(string: fullPath)
			{
				_ = DownloadManager.shared.startDownload(from: downloadURL)
			}
		} else {
			if url.pathExtension == "ipa" || url.pathExtension == "tipa" {
                let isScoped = FileManager.default.isFileFromFileProvider(at: url)
                if isScoped && !url.startAccessingSecurityScopedResource() { return }
                let download = downloadManager.startArchive(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
                try? downloadManager.handlePachageFile(url: url, dl: download) {
                    if isScoped { url.stopAccessingSecurityScopedResource() }
                }

				
				return
			}
		}
	}
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Only retired v1/v2 daemon sessions can send these events now.
        // New transfers run in-process; their files are persisted by the delegate.
        completionHandler()
    }
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		_createPipeline()
		_createDocumentsDirectories()
		_addDefaultCertificates()
		return true
	}
	
	private func _createPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0
		
		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache") // disk cache
			let imageCache = Nuke.ImageCache() // memory cache
			dataCache?.sizeLimit = 500 * 1024 * 1024
			imageCache.costLimit = 100 * 1024 * 1024
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .automatic
			$0.isStoringPreviewsInMemoryCache = false
		}
		
		ImagePipeline.shared = pipeline
	}
	
	private func _createDocumentsDirectories() {
		let fileManager = FileManager.default

		let directories: [URL] = [
			fileManager.archives,
			fileManager.certificates,
			fileManager.signed,
			fileManager.unsigned
		]
		
		for url in directories {
			try? fileManager.createDirectoryIfNeeded(at: url)
		}
	}
	
	private func _addDefaultSource() {
		let sourceURL = "https://raw.githubusercontent.com/DzhabaApps/Dzhaba-Apps/refs/heads/main/DzhabaApps.json"
		let importedKey = "dzhabaapps.didImportDefaultSource"
		let defaults = UserDefaults.standard
		guard !defaults.bool(forKey: importedKey) else { return }

		if Storage.shared.getSources().contains(where: { $0.sourceURL?.absoluteString == sourceURL }) {
			defaults.set(true, forKey: importedKey)
			return
		}

		FR.handleSource(sourceURL) {
			defaults.set(true, forKey: importedKey)
		}
	}

	private func _addDefaultCertificates() {
		guard
			let signingAssetsURL = Bundle.main.url(forResource: "signing-assets", withExtension: nil)
		else {
			return
		}
		
		do {
			let folderContents = try FileManager.default.contentsOfDirectory(
				at: signingAssetsURL,
				includingPropertiesForKeys: nil,
				options: .skipsHiddenFiles
			)
			
			for folderURL in folderContents {
				guard folderURL.hasDirectoryPath else { continue }
				
				let embeddedName = try? String(contentsOf: folderURL.appendingPathComponent("name.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
				let certName = embeddedName?.isEmpty == false ? embeddedName! : (folderURL.lastPathComponent == "one" ? .localized("My Certificate") : folderURL.lastPathComponent)
				
				let p12Url = folderURL.appendingPathComponent("cert.p12")
				let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
				let passwordUrl = folderURL.appendingPathComponent("cert.txt")
				
				guard
					FileManager.default.fileExists(atPath: p12Url.path),
					FileManager.default.fileExists(atPath: provisionUrl.path),
					FileManager.default.fileExists(atPath: passwordUrl.path)
				else {
					Logger.misc.warning("Skipping \(certName): missing required files")
					continue
				}
				
				let password = try String(contentsOf: passwordUrl, encoding: .utf8)
				let digest = SHA256.hash(data: try Data(contentsOf: p12Url) + Data(contentsOf: provisionUrl))
					.map { String(format: "%02x", $0) }.joined()
				let digestKey = "feather.defaultCertificateDigest.\(folderURL.lastPathComponent)"
				if UserDefaults.standard.string(forKey: digestKey) == digest { continue }
				
				FR.handleCertificateFiles(
					p12URL: p12Url,
					provisionURL: provisionUrl,
					p12Password: password,
					certificateName: certName,
					isDefault: true
				) { error in
					if error == nil {
						UserDefaults.standard.set(digest, forKey: digestKey)
						UserDefaults.standard.set(0, forKey: "feather.selectedCert")
					}
				}
			}
			UserDefaults.standard.set(true, forKey: "feather.didImportDefaultCertificates")
		} catch {
			Logger.misc.error("Failed to list signing-assets: \(error)")
		}
	}

}
