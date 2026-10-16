import SwiftUI
import NimbleViews
import IDeviceSwift

struct InstallPreviewView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("Feather.useShareSheetForArchiving") private var useShareSheet = false
    @State private var showingSafari = false
    @State private var installationTask: Task<Void, Never>?
    @State private var progressTask: Task<Void, Never>?
    @State private var deadlineTask: Task<Void, Never>?
    @State private var manifest: InstallManifest?
    @State private var shownError = false
    @State private var visible = false
    @State private var foregroundRequired = false
    @State private var payloadDelivered = false
    @State private var waitingForConfirmation = false
    @State private var requestedAt = Date()
    @State private var retryTask: Task<Void, Never>?
    private let client = InstallManifestClient()
    var app: AppInfoPresentable
    @StateObject var viewModel: InstallerStatusViewModel
    @StateObject var installer: ServerInstaller
    @State var isSharing: Bool

    init(app: AppInfoPresentable, isSharing: Bool = false) {
        self.app = app; self.isSharing = isSharing
        let model = InstallerStatusViewModel(isIdevice: false)
        self._viewModel = StateObject(wrappedValue: model)
        self._installer = StateObject(wrappedValue: ServerInstaller(app: app, viewModel: model))
    }
    private var canOpenPage: Bool {
        if case .ready = viewModel.status { return manifest != nil }
        return false
    }
    var body: some View {
        let radius: CGFloat = { if #available(iOS 26.0, *) { return 28 }; return 10.5 }()
        ZStack {
            InstallProgressView(app: app, viewModel: viewModel).offset(y: canOpenPage ? -20 : 0)
            Label(waitingForConfirmation ? "Ожидаем подтверждение iOS" : (foregroundRequired ? "Оставьте DR Store открытым до окончания установки" : viewModel.statusLabel), systemImage: viewModel.statusImage)
                .padding().labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .animation(.smooth, value: viewModel.statusImage)
            buttons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.secondarySystemBackground)).cornerRadius(radius).padding()
        .sheet(isPresented: $showingSafari) {
            if let manifest { SafariRepresentableView(url: manifest.page_url).ignoresSafeArea() }
        }
        .onReceive(viewModel.$status) { status in
            switch status {
            case .ready:
                requestedAt = Date(); waitingForConfirmation = false
                openInstallation()
                if progressTask == nil { startProgressPolling() }
                deadlineTask?.cancel()
                deadlineTask = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 1_200_000_000_000) }
                    catch { return }
                    fail(InstallManifestError.timeout)
                }
            case .sendingPayload:
                waitingForConfirmation = false; showingSafari = false
            case .installing: payloadDelivered = true
            case .completed, .broken:
                progressTask?.cancel(); progressTask = nil
                deadlineTask?.cancel(); deadlineTask = nil
                retryTask?.cancel(); retryTask = nil
                installer.stop()
                if case .broken(let error) = status { presentError(error) }
                #if !targetEnvironment(macCatalyst)
                BackgroundAudioManager.shared.stop()
                #endif
            default: break
            }
        }
        .onAppear { visible = true; install() }
        .onDisappear {
            visible = false
            installationTask?.cancel(); installationTask = nil
            progressTask?.cancel(); progressTask = nil
            deadlineTask?.cancel(); deadlineTask = nil
            retryTask?.cancel(); retryTask = nil
            installer.stop()
            #if !targetEnvironment(macCatalyst)
            BackgroundAudioManager.shared.stop()
            #endif
        }
    }
    private var buttons: some View {
        ZStack {
            if viewModel.isCompleted {
                Button { UIApplication.openApp(with: app.identifier ?? "") } label: {
                    NBButton(.localized("Open"), systemImage: "", style: .text)
                }.padding().compatTransition()
            } else if canOpenPage {
                VStack(spacing: 0) {
                    if waitingForConfirmation {
                        Button("Повторить установку") { retryInstallation() }
                            .disabled(retryTask != nil).frame(minHeight: 44)
                        Button("Как продолжить?") {
                            UIAlertController.showAlertWithOk(title: "Установка ожидает подтверждения",
                                message: "Разрешите загрузку в системном окне iOS. Если окно закрыли и значок приложения остался в ожидании, зажмите его на экране «Домой», приостановите загрузку, затем вернитесь в DR Store и нажмите «Повторить установку». Скачивать приложение из каталога заново не нужно.")
                        }.font(.footnote).frame(minHeight: 44)
                    }
                    Button { showingSafari = true } label: {
                        Text("Открыть через Safari").font(.footnote).frame(minHeight: 44)
                    }
                }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .padding(.horizontal).padding(.top, 60)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: canOpenPage ? .center : .bottomTrailing)
    }
    private func install() {
        guard installationTask == nil, FeatherAccessManager.shared.permitsAccess() else { return }
        guard isSharing || app.identifier != Bundle.main.bundleIdentifier else {
            UIAlertController.showAlertWithOk(title: .localized("Install"),
                message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name))
            return
        }
        installationTask = Task { @MainActor in
            let handler = ArchiveHandler(app: app, viewModel: viewModel)
            var adopted = false
            defer { if !adopted { handler.cleanupWork() } }
            do {
                if !isSharing {
                    try installer.start()
                    #if !targetEnvironment(macCatalyst)
                    foregroundRequired = !BackgroundAudioManager.shared.start()
                    #endif
                }
                try Task.checkCancellation()
                try await handler.move()
                let package = try await handler.archive()
                try Task.checkCancellation()
                if isSharing {
                    let result = try await handler.moveToArchive(package, shouldOpen: !useShareSheet)
                    dismiss()
                    if useShareSheet, let result { UIActivityViewController.show(activityItems: [result]) }
                } else {
                    let authorization = try FeatherAccessManager.shared.installAuthorization()
                    installer.setPackage(package, cleanup: { handler.cleanupWork() })
                    adopted = true
                    let result = try await client.prepare(id: installer.id, port: installer.port,
                        bundleID: app.identifier ?? "", version: app.version ?? "1", title: app.name ?? "Приложение",
                        authorization: authorization)
                    try Task.checkCancellation()
                    manifest = result
                    viewModel.status = .ready
                }
            } catch is CancellationError { installer.stop() }
            catch { fail(error) }
        }
    }
    private func fail(_ error: Error) {
        viewModel.status = .broken(error)
        showingSafari = false
        installer.stop()
        presentError(error)
    }
    private func presentError(_ error: Error) {
        guard visible, !shownError else { return }
        shownError = true
        UIAlertController.showAlertWithOk(title: .localized("Install"), message: error.localizedDescription,
            action: { HeartbeatManager.shared.start(true); dismiss() })
    }
    private func openInstallation() {
        guard let url = manifest?.installationURL else { showingSafari = true; return }
        UIApplication.shared.open(url, options: [:]) { accepted in
            Task { @MainActor in
                if !accepted, case .ready = viewModel.status { showingSafari = true }
            }
        }
    }
    private func retryInstallation() {
        guard canOpenPage, retryTask == nil else { return }
        retryTask = Task { @MainActor in
            defer { retryTask = nil }
            do {
                let authorization = try FeatherAccessManager.shared.installAuthorization()
                let result = try await client.prepare(id: installer.id, port: installer.port,
                    bundleID: app.identifier ?? "", version: app.version ?? "1", title: app.name ?? "Приложение",
                    authorization: authorization)
                try Task.checkCancellation()
                guard canOpenPage else { return }
                manifest = result
                viewModel.status = .ready
            } catch is CancellationError { }
            catch {
                guard visible else { return }
                // A temporary request failure must not tear down the waiting IPA.
                UIAlertController.showAlertWithOk(title: "Повторить установку", message: error.localizedDescription)
            }
        }
    }
    private func startProgressPolling() {
        let identifier = app.identifier ?? ""
        progressTask = Task { @MainActor in
            var observation = InstallationObservation()
            while !Task.isCancelled {
                let raw = UIApplication.installProgress(for: identifier, makeSynchronous: false)
                if let raw, raw.isFinite, raw > 0 {
                    viewModel.installProgress = min(1, max(0, (raw - 0.6) / 0.3))
                }
                if observation.completed(raw: raw, payloadDelivered: payloadDelivered) {
                        viewModel.installProgress = 1
                        viewModel.status = .completed(.success(()))
                        return
                }
                if canOpenPage && Date().timeIntervalSince(requestedAt) >= 25 { waitingForConfirmation = true }
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return }
            }
        }
    }
}
