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
	@StateObject private var incoming = IncomingPackageImporter.shared
	@Environment(\.scenePhase) private var scenePhase
	@AppStorage("Feather.userTintColor") private var accentHex = "#7866E8"
	let storage = Storage.shared

	init() {
		UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
	}
	
	var body: some Scene {
		WindowGroup {
			Group {
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
					.transition(.move(edge: .top).combined(with: .opacity))
			}
			.environment(\.locale, Locale(identifier: "ru"))
			.overlay {
				if access.state != .active { FeatherAccessView(access: access) }
			}
			.task { incoming.recoverInbox(); await access.refresh(); incoming.processPending(); downloadManager.processForegroundDownloads() }
			.onChange(of: access.state) { _ in incoming.processPending() }
			.onChange(of: scenePhase) { phase in
				if phase == .active { incoming.recoverInbox(); Task { await access.refresh(); incoming.processPending(); downloadManager.processForegroundDownloads() } }
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
				
				UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#7866E8"))
			}
			}
			}
			.tint(Color(hex: accentHex))
			.accentColor(Color(hex: accentHex))
			.onOpenURL(perform: _handleURL)
			.overlay {
				if let name = incoming.importingName {
					VStack(spacing: 12) {
						ProgressView()
						Text("Импорт IPA").font(.headline)
						Text(name).font(.footnote).lineLimit(2)
					}.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)).padding()
				}
			}
			.alert("Импорт IPA", isPresented: $incoming.showMessage) {
				Button("OK", role: .cancel) {}
			} message: { Text(incoming.message) }
		}
	}

	@ViewBuilder
	private func _previewScreen(_ screen: String) -> some View {
		switch screen {
		case "instructions": InstructionsView(preview: true)
		case "instruction-library": InstructionsView()
		case "instruction-detail": NavigationStack { ScrollView { InstructionVideoCard(instruction: .sample).padding() }.navigationTitle("Инструкция").navigationBarTitleDisplayMode(.inline) }
		case "instruction-check": InstructionPlaybackPreviewView()
		case "about": AboutView()
		case "app-icons": AppIconView()
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
        case "game-detail": GameDetailPreview()
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
		FeatherIncomingURLRouter.open(url)
	}
}

// Own the incoming file before waiting for access or starting asynchronous extraction.
// Some Open In deliveries land in Documents/Inbox before SwiftUI receives its URL.
final class IncomingPackageImporter: ObservableObject {
    static let shared = IncomingPackageImporter()
    @Published var importingName: String?
    @Published var message = ""
    @Published var showMessage = false
    private var receiving = Set<URL>()
    private var pending: [(source: URL, staged: URL)] = []
    private var importing = false

    func receive(_ url: URL) {
        guard url.isFileURL, !receiving.contains(url) else { return }
        let ext = url.pathExtension.lowercased()
        guard ["ipa", "tipa"].contains(ext) else {
            notify("Не удалось принять файл «\(url.lastPathComponent)». Отправьте файл с расширением .ipa или .tipa.")
            return
        }
        receiving.insert(url)
        importingName = url.lastPathComponent
        // A false result can also mean a local Inbox file needs no security scope.
        let scoped = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let folder = FileManager.default.temporaryDirectory
                        .appendingPathComponent("FeatherIncoming/\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let target = folder.appendingPathComponent("package.\(ext)")
                    do {
                        var copyError: Error?
                        var coordinationError: NSError?
                        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                            do { try FileManager.default.copyItem(at: readable, to: target) }
                            catch { copyError = error }
                        }
                        if let error = coordinationError { throw error }
                        if let error = copyError { throw error }
                        return target
                    } catch {
                        try? FileManager.default.removeItem(at: folder)
                        throw error
                    }
                }.value
                pending.append((url, staged))
                if !FeatherAccessManager.shared.permitsAccess() {
                    await FeatherAccessManager.shared.refresh()
                }
                processPending()
                if !FeatherAccessManager.shared.permitsAccess() {
                    importingName = nil
                    notify("Файл принят. Для добавления в библиотеку дождитесь проверки доступа к DR Store.")
                }
            } catch {
                receiving.remove(url)
                importingName = nil
                notify("Не удалось прочитать IPA: \(error.localizedDescription)")
            }
        }
    }

    func recoverInbox() {
        let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        for file in files where ["ipa", "tipa"].contains(file.pathExtension.lowercased()) { receive(file) }
    }

    func processPending() {
        guard !importing, !pending.isEmpty, FeatherAccessManager.shared.permitsAccess() else { return }
        importing = true
        let item = pending.removeFirst()
        importingName = item.source.lastPathComponent
        let download = DownloadManager.shared.startArchive(from: item.staged, id: "FeatherManualDownload_\(UUID().uuidString)")
        FR.handlePackageFile(item.staged, download: download) { error in
            DownloadManager.shared.cancelDownload(download)
            try? FileManager.default.removeItem(at: item.staged.deletingLastPathComponent())
            self.receiving.remove(item.source)
            self.importing = false
            self.importingName = nil
            if let error {
                self.notify("Не удалось добавить IPA: \(error.localizedDescription)")
            } else {
                let inbox = URL.documentsDirectory.appendingPathComponent("Inbox").standardizedFileURL.path + "/"
                if item.source.standardizedFileURL.path.hasPrefix(inbox) {
                    try? FileManager.default.removeItem(at: item.source)
                }
                UserDefaults.standard.set(TabEnum.library.rawValue, forKey: "DRStore.selectedTab")
            }
            self.processPending()
        }
    }

    private func notify(_ text: String) {
        message = text
        showMessage = true
    }

    func receiveUnsupportedLink() {
        notify("Приложение получило ссылку вместо файла IPA. Передайте скачанный файл через «Поделиться».")
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // UIKit delivers the first Open In URL here, before a SwiftUI view exists.
        for context in options.urlContexts { FeatherIncomingURLRouter.open(context.url) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication {
            configuration.delegateClass = IncomingFileSceneDelegate.self
        }
        return configuration
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        FeatherIncomingURLRouter.open(url)
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if identifier == GameDataDownload.sessionID {
            GameDataDownload.shared.handleSystemEvents(completionHandler)
        } else {
            completionHandler()
        }
    }
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		_createPipeline()
		_createDocumentsDirectories()
		_addDefaultCertificates()
		if let url = launchOptions?[.url] as? URL { FeatherIncomingURLRouter.open(url) }
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

// Public SwiftUI delegate-adaptor integration: handle both a newly connected
// window and file delivery to an already running window, not only onOpenURL.
final class IncomingFileSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        for context in connectionOptions.urlContexts { FeatherIncomingURLRouter.open(context.url) }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        for context in contexts { FeatherIncomingURLRouter.open(context.url) }
    }
}

enum FeatherIncomingURLRouter {
    private static var lastInstallURL: URL?
    private static var lastInstallTime = Date.distantPast

    @discardableResult static func open(_ url: URL) -> Bool {
        if url.isFileURL {
            IncomingPackageImporter.shared.receive(url)
            return true
        }
        guard url.scheme == "feather" || url.scheme == "fizer-preview",
              let path = url.validatedScheme(after: "/install/"),
              let download = URL(string: path) else {
            IncomingPackageImporter.shared.receiveUnsupportedLink()
            return false
        }
        guard FeatherAccessManager.shared.permitsAccess() else { return false }
        // UIKit and SwiftUI can report the same delivery. Keep the existing
        // installation URL route without starting two downloads for one event.
        if lastInstallURL == url && Date().timeIntervalSince(lastInstallTime) < 1 { return true }
        lastInstallURL = url
        lastInstallTime = Date()
        _ = DownloadManager.shared.startDownload(from: download)
        return true
    }
}
