//
//  InstallPreview.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog
import Zip

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss

	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isWebviewPresenting = false
	@State private var progressTask: Task<Void, Never>?
    @State private var relayTask: Task<Void, Never>?
    @State private var relayText: String?
    @State private var relayJob: InstallRelayJob?
    @State private var relayHandedOff = false
    private let relayClient = InstallRelayClient()
    private var usesRelay: Bool { InstallRelayClient.enabled && _installationMethod == 0 && _serverMethod == 2 && !isSharing }
    private var canOpenInstallationPage: Bool {
        if case .ready = viewModel.status {
            return (usesRelay && relayJob != nil) || InstallRelayClient.semiLocalLabEnabled
        }
        return false
    }
	
	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	
	@State var isSharing: Bool
	
	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
        if InstallRelayClient.localTLSLabEnabled {
            // Keep ordinary installation preferences intact for rollback.
            self.__installationMethod = AppStorage(wrappedValue: 0, "DRStore.localTLSLab.installationMethod")
            self.__serverMethod = AppStorage(wrappedValue: 0, "DRStore.localTLSLab.serverMethod")
        }
        if InstallRelayClient.semiLocalLabEnabled {
            self.__installationMethod = AppStorage(wrappedValue: 0, "DRStore.semiLocalLab.installationMethod")
            self.__serverMethod = AppStorage(wrappedValue: 1, "DRStore.semiLocalLab.serverMethod")
        }
        if InstallRelayClient.enabled && !UserDefaults.standard.bool(forKey: "DRStore.relayDefaultV1") {
            UserDefaults.standard.set(2, forKey: "Feather.serverMethod")
            UserDefaults.standard.set(true, forKey: "DRStore.relayDefaultV1")
        }
        let remote = InstallRelayClient.enabled && !isSharing && UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 0 && UserDefaults.standard.integer(forKey: "Feather.serverMethod") == 2
		let viewModel = InstallerStatusViewModel(isIdevice: !InstallRelayClient.localLabEnabled && (remote || UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1))
		self._viewModel = StateObject(wrappedValue: viewModel)
		self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel, startLocal: !remote && !isSharing))
	}
	
	// MARK: Body
	var body: some View {
		let cornerRadius = {
			if #available(iOS 26.0, *) {
				28.0
			} else {
				10.5
			}
		}()
		
		ZStack {
			InstallProgressView(app: app, viewModel: viewModel)
                .offset(y: canOpenInstallationPage ? -20 : 0)
			_status()
			_button()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(cornerRadius)
		.padding()
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: usesRelay ? (relayJob?.page_url ?? installer.pageEndpoint) : installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			if _installationMethod == 0 {
				if case .ready = newStatus {
                    if usesRelay && relayJob != nil {
                        relayHandedOff = true
                        openRelayInstallation()
                    } else if _serverMethod == 0 {
						UIApplication.shared.open(URL(string: installer.iTunesLink)!)
					} else if _serverMethod == 1 {
                        if InstallRelayClient.semiLocalLabEnabled {
                            openSemiLocalInstallation()
                        } else {
                            _isWebviewPresenting = true
                        }
					}
				}
				
				if case .sendingPayload = newStatus, _serverMethod == 1 {
					_isWebviewPresenting = false
				}
				
				if case .installing = newStatus, !usesRelay {
					if progressTask == nil {
						progressTask = startInstallProgressPolling(
							bundleID: app.identifier!,
							viewModel: viewModel
						)
					}
				}
				
				switch newStatus {
				case .completed, .broken(_):
					progressTask?.cancel()
					progressTask = nil
					#if !targetEnvironment(macCatalyst)
					BackgroundAudioManager.shared.stop()
					#endif
				default:
					break
				}
			}
		}
		.onAppear(perform: _install)
		
		#if !targetEnvironment(macCatalyst)
		.onAppear {
			BackgroundAudioManager.shared.start()
		}
		#endif
		
		.onDisappear {
            relayTask?.cancel()
            relayTask = nil
            if usesRelay && !relayHandedOff { Task { await relayClient.cancel() } }
			progressTask?.cancel()
			progressTask = nil
			
			#if !targetEnvironment(macCatalyst)
			BackgroundAudioManager.shared.stop()
			#endif
		}
	}
	
	@ViewBuilder
	private func _status() -> some View {
		Label(relayText ?? viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton(.localized("Open"), systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
            else if canOpenInstallationPage {
                Button {
                    _isWebviewPresenting = true
                } label: {
                    Text("Открыть через Safari").font(.footnote)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal)
                .padding(.top, 60)
            }
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: canOpenInstallationPage ? .center : .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
	
	private func _install() {
		guard FeatherAccessManager.shared.permitsAccess() else { dismiss(); return }
		guard isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
			)
			return
		}

        if usesRelay {
            installThroughRelay()
            return
        }
				
		Task.detached {
			do {
				let handler = await ArchiveHandler(app: app, viewModel: viewModel)
				try await handler.move()
				
				let packageUrl = try await handler.archive()
				
				if await !isSharing {
					try FeatherAccessManager.shared.requireAccess()
					if await _installationMethod == 0 {
                        if InstallRelayClient.localTLSLabEnabled {
                            // Use ordinary iOS trust: never accept a self-signed or revoked leaf.
                            let url = await MainActor.run {
                                URL(string: "https://\(installer.sni()):\(installer.port)/dr-local-tls-check")!
                            }
                            let configuration = URLSessionConfiguration.ephemeral
                            configuration.timeoutIntervalForRequest = 10
                            configuration.timeoutIntervalForResource = 15
                            let session = URLSession(configuration: configuration)
                            defer { session.invalidateAndCancel() }
                            let (data, response) = try await session.data(from: url)
                            guard (response as? HTTPURLResponse)?.statusCode == 200,
                                  String(data: data, encoding: .utf8) == "dr-local-tls-ok" else {
                                throw URLError(.badServerResponse)
                            }
                        }
                        if InstallRelayClient.semiLocalLabEnabled {
                            let expected = await installer.payloadEndpoint.absoluteString
                            let link = await installer.externalServerLink
                            guard let decoded = link.removingPercentEncoding, let url = URL(string: decoded) else {
                                throw InstallRelayError.invalidResponse
                            }
                            let configuration = URLSessionConfiguration.ephemeral
                            configuration.timeoutIntervalForRequest = 10
                            configuration.timeoutIntervalForResource = 15
                            let session = URLSession(configuration: configuration)
                            defer { session.invalidateAndCancel() }
                            let (data, response) = try await session.data(from: url)
                            guard (response as? HTTPURLResponse)?.statusCode == 200,
                                  let manifest = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                                  let items = manifest["items"] as? [[String: Any]], items.count == 1,
                                  let assets = items[0]["assets"] as? [[String: Any]],
                                  assets.first(where: { $0["kind"] as? String == "software-package" })?["url"] as? String == expected else {
                                throw InstallRelayError.invalidResponse
                            }
                        }
						await MainActor.run {
							installer.packageUrl = packageUrl
							viewModel.status = .ready
						}
						
						if case .installing = await viewModel.status {
							let task = await startInstallProgressPolling(
								bundleID: app.identifier!,
								viewModel: viewModel
							)

							await MainActor.run {
								progressTask = task
							}
						}
					} else if await _installationMethod == 1 {
						let handler = await InstallationProxy(viewModel: viewModel)
						try await handler.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
					}
				} else {
					let package = try await handler.moveToArchive(packageUrl, shouldOpen: !_useShareSheet)
					
					if await !_useShareSheet {
						await MainActor.run {
							dismiss()
						}
					} else {
						if let package {
							await MainActor.run {
								dismiss()
								UIActivityViewController.show(activityItems: [package])
							}
						}
					}
				}
			} catch {
				await progressTask?.cancel()
				
				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: .localized("Install"),
						message: String(describing: error),
						action: {
							HeartbeatManager.shared.start(true)
							dismiss()
						}
					)
				}
			}
		}
	}

    private func openRelayInstallation() {
        guard let job = relayJob else { return }
        var components = URLComponents()
        components.scheme = "itms-services"
        components.host = ""
        components.queryItems = [URLQueryItem(name: "action", value: "download-manifest"),
                                 URLQueryItem(name: "url", value: job.manifest_url.absoluteString)]
        guard let url = components.url else { _isWebviewPresenting = true; return }
        UIApplication.shared.open(url, options: [:]) { accepted in
            Task { @MainActor in
                if !accepted { _isWebviewPresenting = true }
            }
        }
    }

    private func openSemiLocalInstallation() {
        guard let url = URL(string: installer.iTunesLinkExternal),
              url.scheme == "itms-services" else {
            _isWebviewPresenting = true
            return
        }
        UIApplication.shared.open(url, options: [:]) { accepted in
            Task { @MainActor in
                if !accepted, case .ready = viewModel.status {
                    _isWebviewPresenting = true
                }
            }
        }
    }

    private func installThroughRelay() {
        guard relayTask == nil else { return }
        relayTask = Task { @MainActor in
            let handler = ArchiveHandler(app: app, viewModel: viewModel)
            defer { handler.cleanupRelayWork() }
            do {
                let authorization = try FeatherAccessManager.shared.relayAuthorization()
                relayText = "Подготавливаем приложение"
                try await handler.move()
                let package = try await handler.archive(compression: .BestSpeed)
                try Task.checkCancellation()
                relayText = "Передаём приложение для установки"
                viewModel.status = .sendingPayload
                let job = try await relayClient.prepare(package: package, bundleID: app.identifier ?? "",
                    version: app.version ?? "1", title: app.name ?? "Приложение", authorization: authorization) { progress in
                    Task { @MainActor in
                        if case .sendingPayload = viewModel.status {
                            viewModel.uploadProgress = progress
                            relayText = "Передаём приложение для установки: \(Int(progress * 100))%"
                        }
                    }
                }
                viewModel.uploadProgress = 1
                handler.cleanupRelayWork()
                try Task.checkCancellation()
                relayJob = job
                relayText = "Подтвердите установку"
                viewModel.status = .ready
                let deadline = Date().addingTimeInterval(1200)
                while !Task.isCancelled && Date() < deadline {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    let state: InstallRelayStatus
                    do { state = try await relayClient.status(job) }
                    catch { continue } // A temporary status timeout must not cancel iOS downloading.
                    if state.state == "consumed" {
                        _isWebviewPresenting = false
                        relayText = "Файл передан iPhone"
                        viewModel.installProgress = 1
                        // This marks file transfer completion, not proof that iOS launched the app.
                        viewModel.status = .completed(.success(()))
                        return
                    }
                    if ["failed", "expired", "cancelled"].contains(state.state) { throw InstallRelayError.expired }
                    if state.downloaded_bytes > 0 {
                        relayText = "iPhone скачивает приложение"
                        viewModel.installProgress = min(1, Double(state.downloaded_bytes) / Double(max(1,state.size)))
                    }
                }
                if !Task.isCancelled { throw InstallRelayError.expired }
            } catch is CancellationError {
                if !relayHandedOff { await relayClient.cancel() }
            } catch {
                relayText = error.localizedDescription
                viewModel.status = .broken(error)
            }
        }
    }
	
	private func startInstallProgressPolling(
		bundleID: String,
		viewModel: InstallerStatusViewModel
	) -> Task<Void, Never> {

		Task.detached(priority: .background) {
			var hasStarted = false

			while !Task.isCancelled {
				let rawProgress = await UIApplication.installProgress(for: bundleID) ?? 0.0

				if rawProgress > 0 {
					hasStarted = true
				}

				let progress = await hasStarted
					? _normalizeInstallProgress(rawProgress)
					: 0.0

				Logger.misc.info("Install progress for \(bundleID): \(progress)")

				await MainActor.run {
					viewModel.installProgress = progress
				}

				if hasStarted && rawProgress == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 1_000_000) // 1 ms
			}
		}
	}

	private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
		min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
	}
}
