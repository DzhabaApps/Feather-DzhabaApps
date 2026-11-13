//
//  ContentView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - View
struct LibraryView: View {
	@StateObject var downloadManager = DownloadManager.shared
	
	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false
	@State private var _alertDownloadString: String = "" // for _isDownloadingPresenting
	
	// MARK: Selection State
	@State private var _selectedAppUUIDs: Set<String> = []
	@State private var _editMode: EditMode = .inactive
	
	@State private var _cacheBytes: Int64 = 0
    @State private var _showCacheConfirmation = false
    @State private var _cacheError: String?
    @State private var _showCacheError = false
    @ObservedObject private var installer = RepositoryInstallCoordinator.shared
    private var canClearCache: Bool { !downloadManager.isRestoring && downloadManager.downloads.isEmpty && !installer.isBusy }
    @State private var _searchText = ""
	
	
	@Namespace private var _namespace
	
    private struct LibraryEntry: Identifiable {
        let id: LibraryAppIdentity
        let apps: [AppInfoPresentable]
        var app: AppInfoPresentable { apps[0] }
    }

    private var libraryEntries: [LibraryEntry] {
        let apps: [AppInfoPresentable] = _signedApps.map { $0 as AppInfoPresentable } + _importedApps.map { $0 as AppInfoPresentable }
        let groups = Dictionary(grouping: apps) { app in
            LibraryAppIdentity(identifier: app.identifier, version: app.version,
                               source: app.source, uuid: app.uuid ?? (app as! NSManagedObject).objectID.uriRepresentation().absoluteString)
        }
        return groups.map { identity, members in
            LibraryEntry(id: identity, apps: members.sorted {
                if $0.isSigned != $1.isSigned { return $0.isSigned }
                return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            })
        }.filter { entry in
            _searchText.isEmpty || entry.apps.contains { ($0.name ?? "").localizedCaseInsensitiveContains(_searchText) }
        }.sorted {
            let left = $0.apps.compactMap(\.date).max() ?? .distantPast
            let right = $1.apps.compactMap(\.date).max() ?? .distantPast
            return left == right ? ($0.app.uuid ?? "") < ($1.app.uuid ?? "") : left > right
        }
    }

    private func deleteEntry(_ entry: LibraryEntry) {
        for app in entry.apps { Storage.shared.deleteApp(for: app) }
    }

	// MARK: Fetch
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>
	
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Library")) {
			NBListAdaptable {
                if libraryEntries.isEmpty {
                    Text(_searchText.isEmpty ? "Скачайте приложение из каталога — оно появится здесь." : "Ничего не найдено")
                        .foregroundStyle(.secondary)
                }
                if !libraryEntries.isEmpty {
                    NBSection("Приложения") {
                        ForEach(libraryEntries) { entry in
                            LibraryCellView(
                                app: entry.app,
                                selectedInfoAppPresenting: $_selectedInfoAppPresenting,
                                selectedInstallAppPresenting: $_selectedInstallAppPresenting,
                                selectedAppUUIDs: $_selectedAppUUIDs,
                                deleteApp: { deleteEntry(entry) }
                            )
                            .compatMatchedTransitionSource(id: entry.app.uuid ?? "", ns: _namespace)
                        }
                    }
                }
                if _cacheBytes > 0 {
                Section {
                    Button { _showCacheConfirmation = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "internaldrive").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Освободить место").font(.subheadline.weight(.medium))
                                Text(_cacheBytes > 0 ? "\(ByteCountFormatter.string(fromByteCount: _cacheBytes, countStyle: .file)) · скачанные файлы" : "Нет скачанных файлов")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canClearCache || _cacheBytes == 0)
                }
                }
			}
            .task { await updateCacheSize() }
            .onChange(of: _signedApps.count + _importedApps.count) { _ in Task { await updateCacheSize() } }
			.searchable(text: $_searchText, placement: .platform())
			.scrollDismissesKeyboard(.interactively)

			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
				}
				
				if _editMode.isEditing {
					NBToolbarButton(
						.localized("Delete"),
						systemImage: "trash",
						isDisabled: _selectedAppUUIDs.isEmpty
					) {
						_bulkDeleteSelectedApps()
					}
				} else {
					NBToolbarMenu(
						systemImage: "plus",
						style: .icon,
						placement: .topBarTrailing
					) {
						_importActions()
					}
				}
			}
			.environment(\.editMode, $_editMode)
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(app: app.base)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}

			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes:  [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						guard !urls.isEmpty else { return }
						
						for url in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = downloadManager.startArchive(from: url, id: id)
							try? downloadManager.handlePachageFile(url: url, dl: dl)
						}
					}
				)
				.ignoresSafeArea()
			}
            .confirmationDialog("Удалить скачанные файлы?", isPresented: $_showCacheConfirmation, titleVisibility: .visible) {
                Button("Удалить скачанные файлы", role: .destructive) {
                    guard canClearCache else { return }
                    do {
                        try Storage.shared.clearDownloadedApps()
                        _cacheError = "Скачанные файлы удалены. Приложения на iPhone остались на месте."
                        _showCacheError = true
                        Task { await updateCacheSize() }
                    }
                    catch { _cacheError = "Не удалось удалить все файлы. Попробуйте снова."; _showCacheError = true }
                }
            } message: { Text("Файлы в библиотеке DR Store будут удалены. Для повторной установки их потребуется скачать заново. Приложения на iPhone и подписка сохранятся.") }
            .alert("Хранилище", isPresented: $_showCacheError) { Button("OK", role: .cancel) {} } message: { Text(_cacheError ?? "") }
			.alert(.localized("Import from URL"), isPresented: $_isDownloadingPresenting) {
				TextField(.localized("URL"), text: $_alertDownloadString)
					.textInputAutocapitalization(.never)
				Button(.localized("Cancel"), role: .cancel) {
					_alertDownloadString = ""
				}
				Button(.localized("OK")) {
					if let url = URL(string: _alertDownloadString) {
						_ = downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
					}
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("Feather.installApp"))) { notification in
				if let signedApp = notification.object as? Signed {
					_selectedInstallAppPresenting = AnyApp(base: signedApp)
				}
			}
			.onChange(of: _editMode) { mode in
				if mode == .inactive {
					_selectedAppUUIDs.removeAll()
				}
			}
		}
	}
}

extension LibraryView {
    private func updateCacheSize() async {
        let snapshot = await Task.detached(priority: .utility) { LocalAppFiles.snapshot() }.value
        _cacheBytes = snapshot.apps + snapshot.work
    }
}

// MARK: - Extension: View
extension LibraryView {
	@ViewBuilder
	private func _importActions() -> some View {
		Button(.localized("Import from Files"), systemImage: "folder") {
			_isImportingPresenting = true
		}
		Button(.localized("Import from URL"), systemImage: "globe") {
			_isDownloadingPresenting = true
		}
	}
}

// MARK: - Extension: Bulk Delete
extension LibraryView {
    private func _bulkDeleteSelectedApps() {
        let selected = libraryEntries.filter { entry in
            entry.app.uuid.map { _selectedAppUUIDs.contains($0) } ?? false
        }
        for entry in selected { deleteEntry(entry) }
        _selectedAppUUIDs.removeAll()
    }
}
