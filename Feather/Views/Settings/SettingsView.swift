// Fizer: subscription and ordinary user settings; installation credentials stay internal.
import SwiftUI
import NimbleViews
import Nuke

struct SettingsView: View {
	@ObservedObject private var access = FeatherAccessManager.shared
	var previewState: FeatherAccessState? = nil
	var previewExpiry: Date? = nil
	private var subscriptionStatus: String {
		switch previewState ?? access.state {
		case .active: return "Активна"
		case .expired: return "Закончилась"
		case .disabled: return "Требуется восстановление"
		case .verificationRequired: return "Нужна проверка через интернет"
		}
	}

	var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
				NBSection("Подписка") {
					LabeledContent("Статус", value: subscriptionStatus)
					if let expiry = previewExpiry ?? access.expiresAt {
						LabeledContent("Действует до", value: SubscriptionPresentation.expiry(expiry))
					}
					Link("Продлить подписку", destination: URL(string: "https://t.me/DzhabaApps_bot?start=renew")!)
					Link("Поддержка", destination: URL(string: "https://t.me/dzhabaraduev")!)
				} footer: {
					Text("Восстановление входит в оплаченный срок подписки.")
				}
				SSLUpdateSection()
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
						Label("Оформление", systemImage: "paintbrush")
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
        NBList("Установка") {
            Section {
                Toggle("Удалять лишние файлы автоматически", isOn: $manager.options.post_deleteAppAfterSigned)
            } footer: { Text("После подготовки лишние файлы удаляются. Для приложений с копиями сохраняется общий исходник, чтобы создавать другие копии без повторной загрузки. Все скачанные файлы можно удалить кнопкой «Освободить место» в библиотеке; список копий сохранится.") }
        }
        .onChange(of: manager.options) { _ in manager.saveOptions() }
    }
}

struct AdvancedSettingsView: View {
    @State private var currentIcon: String? = UIApplication.shared.alternateIconName
    var body: some View {
        NBList("Оформление") {
            Section {
                NavigationLink(destination: AppearanceView()) { Label(.localized("Appearance"), systemImage: "paintbrush") }
                NavigationLink(destination: AppIconView(currentIcon: $currentIcon)) { Label(.localized("App Icon"), systemImage: "app.badge") }
            }
        }
    }
}

struct StorageSettingsView: View {
    @State private var files = LocalStorageSnapshot()
    @State private var iconBytes: Int64 = 0
    @State private var action: CleanupAction?
    @State private var message = ""
    @State private var showMessage = false
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var repositoryInstaller = RepositoryInstallCoordinator.shared
    private var canClear: Bool { !downloads.isRestoring && downloads.downloads.isEmpty && !repositoryInstaller.isBusy }
    private enum CleanupAction: String, Identifiable {
        case apps = "Удалить скачанные файлы", work = "Удалить временные файлы", archives = "Удалить сохранённые архивы"
        var id: String { rawValue }
        var explanation: String {
            switch self {
            case .apps: return "Копии приложений в библиотеке будут удалены. Для повторной установки их нужно скачать заново. Приложения на iPhone, иконки магазина и подписка сохранятся."
            case .work: return "Будут удалены остатки подготовки и установки. Скачанные приложения, иконки магазина и подписка сохранятся."
            case .archives: return "Будут удалены архивы, сохранённые при экспорте из Feather. Приложения на iPhone и файлы библиотеки сохранятся."
            }
        }
    }
    private func formatted(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    var body: some View {
        NBList(.localized("Storage")) {
            Section {
                LabeledContent("Локальные файлы", value: formatted(files.total + iconBytes))
            } footer: { Text("Это файлы внутри Feather. Установленные на iPhone приложения занимают место отдельно.") }
            Section {
                LabeledContent("Скачанные приложения", value: formatted(files.apps))
                LabeledContent("Сохранённые архивы", value: formatted(files.archives))
                LabeledContent("Временные файлы", value: formatted(files.work))
                LabeledContent("Загрузки в процессе", value: formatted(files.transfers))
                LabeledContent("Иконки магазина", value: formatted(iconBytes))
                LabeledContent("Другие файлы", value: formatted(files.other))
            } footer: { Text("Скачанные приложения включают копии для повторной установки и остатки прежних загрузок. Размер файлов после распаковки может быть больше размера загрузки.") }
            Section {
                Button("Удалить скачанные файлы", systemImage: "trash") { action = .apps }
                    .disabled(!canClear || files.apps + files.work == 0)
                Button("Удалить временные файлы", systemImage: "sparkles") { action = .work }
                    .disabled(!canClear || files.work == 0)
                if files.archives > 0 {
                    Button("Удалить сохранённые архивы", systemImage: "archivebox") { action = .archives }.disabled(!canClear)
                }
            } footer: { Text(canClear ? "Иконки магазина и подписка сохраняются при очистке." : "Очистка будет доступна после окончания загрузки и установки.") }
        }
        .task { await updateSize() }
        .onChange(of: downloads.downloads.count) { _ in Task { await updateSize() } }
        .confirmationDialog(action?.rawValue ?? "Очистка", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
            if let selected = action {
                Button(selected.rawValue, role: .destructive) { clear(selected) }
            }
        } message: { Text(action?.explanation ?? "") }
        .alert("Хранилище", isPresented: $showMessage) { Button("OK", role: .cancel) {} } message: { Text(message) }
    }
    private func clear(_ selected: CleanupAction) {
        guard canClear else { return }
        do {
            switch selected {
            case .apps: try Storage.shared.clearDownloadedApps()
            case .work: try LocalAppFiles.clearWork()
            case .archives: try LocalAppFiles.clearChildren(in: FileManager.default.archives)
            }
            message = "Файлы удалены. Приложения на iPhone остались на месте."
        } catch { message = "Не удалось удалить все файлы. Попробуйте снова." }
        showMessage = true
        Task { await updateSize() }
    }
    private func updateSize() async {
        files = await Task.detached(priority: .utility) { LocalAppFiles.snapshot() }.value
        iconBytes = Int64((ImagePipeline.shared.configuration.dataCache as? DataCache)?.totalSize ?? 0)
    }
}

struct FizerHelpView: View {
	var body: some View {
		NBList(.localized("Help")) {
			Section {
				Button(.localized("Contact support"), systemImage: "message") { UIApplication.open("https://t.me/dzhabaraduev") }
			}
			NBSection(.localized("Installation is stuck")) { Text(.localized("Installation troubleshooting")) }
			NBSection("Подписка и восстановление") { Text(.localized("Certificate troubleshooting")) }
			NBSection(.localized("Install from repository")) { Text(.localized("Repository installation explanation")) }
		}
	}
}
