// DzhabaApps: compact settings; advanced signing tools remain available.
import SwiftUI
import NimbleViews

struct SettingsView: View {
	@AppStorage("feather.selectedCert") private var selectedCert: Int = 0
	@FetchRequest(entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy) private var certificates: FetchedResults<CertificatePair>

	var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
				NBSection(.localized("Certificate")) {
					if certificates.indices.contains(selectedCert) {
						CertificatesCellView(cert: certificates[selectedCert])
					} else {
						Text(.localized("No Certificate")).foregroundStyle(.secondary)
					}
					NavigationLink(destination: CertificatesView()) {
						Label(.localized("Certificates"), systemImage: "checkmark.seal")
					}
				} footer: {
					Text(.localized("Add and manage certificates used for signing applications."))
				}
				Section {
					NavigationLink(destination: InstallationPreferencesView()) {
						Label(.localized("Installation"), systemImage: "arrow.down.circle")
					}
					NavigationLink(destination: StorageSettingsView()) {
						Label(.localized("Storage"), systemImage: "internaldrive")
					}
					NavigationLink(destination: FizerHelpView()) {
						Label(.localized("Help"), systemImage: "questionmark.circle")
					}
				}
				Section {
					NavigationLink(destination: AdvancedSettingsView()) {
						Label(.localized("Advanced"), systemImage: "slider.horizontal.3")
					}
					NavigationLink(destination: AboutView()) {
						Label(.localized("About"), systemImage: "info.circle")
					}
				}
			}
		}
	}
}

struct InstallationPreferencesView: View {
	@StateObject private var manager = OptionsManager.shared
	var body: some View {
		NBList(.localized("Installation")) {
			Section {
				Toggle(.localized("Install After Signing"), isOn: $manager.options.post_installAppAfterSigned)
				Toggle(.localized("Delete After Signing"), isOn: $manager.options.post_deleteAppAfterSigned)
			} footer: { Text(.localized("Signing cleanup explanation")) }
			SSLUpdateSection()
			Section {
				NavigationLink(destination: InstallationView()) {
					Label(.localized("Advanced installation settings"), systemImage: "slider.horizontal.3")
				}
			}
		}
		.onChange(of: manager.options) { _ in manager.saveOptions() }
	}
}

struct AdvancedSettingsView: View {
	@State private var currentIcon: String? = UIApplication.shared.alternateIconName
	var body: some View {
		NBList(.localized("Advanced")) {
			Section {
				NavigationLink(destination: ConfigurationView()) { Label(.localized("Signing Options"), systemImage: "signature") }
				NavigationLink(destination: InstallationView()) { Label(.localized("Advanced installation settings"), systemImage: "network") }
				NavigationLink(destination: ArchiveView()) { Label(.localized("Archive & Compression"), systemImage: "archivebox") }
			} footer: { Text(.localized("Advanced settings explanation")) }
			Section {
				NavigationLink(destination: AppearanceView()) { Label(.localized("Appearance"), systemImage: "paintbrush") }
				NavigationLink(destination: AppIconView(currentIcon: $currentIcon)) { Label(.localized("App Icon"), systemImage: "app.badge") }
			}
			Section {
				Button(.localized("Open Documents"), systemImage: "folder") { UIApplication.open(URL.documentsDirectory.toSharedDocumentsURL()!) }
				Button(.localized("Open Archives"), systemImage: "folder") { UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!) }
				Button(.localized("Open Certificates"), systemImage: "folder") { UIApplication.open(FileManager.default.certificates.toSharedDocumentsURL()!) }
				NavigationLink(destination: ResetView()) { Label(.localized("Reset"), systemImage: "trash") }
			}
		}
	}
}

struct StorageSettingsView: View {
	@State private var bytes: Int64 = 0
	@State private var showClearConfirmation = false
	@ObservedObject private var downloads = DownloadManager.shared
	@ObservedObject private var repositoryInstaller = RepositoryInstallCoordinator.shared
	private var canClear: Bool { downloads.downloads.isEmpty && repositoryInstaller.signingName == nil && repositoryInstaller.installApp == nil }
	var body: some View {
		NBList(.localized("Storage")) {
			Section {
				LabeledContent(.localized("Local app files"), value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
			} footer: { Text(.localized("Storage explanation")) }
			Section {
				Button(.localized("Clear temporary files"), systemImage: "trash") { showClearConfirmation = true }
					.disabled(!canClear)
			} footer: { Text(.localized("Cache cleanup explanation")) }
		}
		.task { await updateSize() }
		.alert(.localized("Clear temporary files"), isPresented: $showClearConfirmation) {
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Delete"), role: .destructive) {
				guard canClear else { return }
				ResetView.clearWorkCache()
				ResetView.clearNetworkCache()
				Task { await updateSize() }
			}
		} message: { Text(.localized("Cache cleanup explanation")) }
	}
	private func updateSize() async {
		let size = await Task.detached(priority: .utility) { () -> Int64 in
			let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
			guard let files = FileManager.default.enumerator(at: URL.documentsDirectory, includingPropertiesForKeys: keys) else { return 0 }
			var total: Int64 = 0
			for case let url as URL in files {
				if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
			}
			return total
		}.value
		bytes = size
	}
}

struct FizerHelpView: View {
	var body: some View {
		NBList(.localized("Help")) {
			Section {
				Button(.localized("Contact support"), systemImage: "message") { UIApplication.open("https://t.me/dzhabaraduev") }
			}
			NBSection(.localized("Installation is stuck")) { Text(.localized("Installation troubleshooting")) }
			NBSection(.localized("Certificate")) { Text(.localized("Certificate troubleshooting")) }
			NBSection(.localized("Install from repository")) { Text(.localized("Repository installation explanation")) }
		}
	}
}
