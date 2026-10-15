import Foundation
import Vapor
import SwiftUI

final class ServerInstaller: ObservableObject {
    let id = UUID()
    private(set) var port = Int.random(in: 4000...8000)
    var app: AppInfoPresentable
    @ObservedObject var viewModel: InstallerStatusViewModel
    private var server: Application?
    private var packageURL: URL?
    private let lock = NSLock()
    private var readers = 0
    private var cleanupRequested = false
    private var cleanup: (() -> Void)?
    init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) {
        self.app = app; self.viewModel = viewModel
    }
    deinit { stop() }
    func start() throws {
        guard server == nil else { return }
        var lastError: Error = InstallManifestError.unavailable
        for _ in 0..<3 {
            port = Int.random(in: 4000...8000)
            let candidate = try setupApp(port: port)
            configure(candidate)
            do {
                try candidate.server.start()
                server = candidate
                return
            } catch { lastError = error; candidate.shutdown() }
        }
        throw lastError
    }
    func setPackage(_ url: URL, cleanup: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        packageURL = url; self.cleanup = cleanup
    }
    func stop() {
        if let server {
            self.server = nil
            server.server.shutdown()
            server.shutdown()
        }
        lock.lock()
        cleanupRequested = true
        let action = readers == 0 ? cleanup : nil
        if readers == 0 { cleanup = nil; packageURL = nil }
        lock.unlock()
        action?()
    }
    private func finishRead() {
        lock.lock()
        readers = max(0, readers - 1)
        let action = readers == 0 && cleanupRequested ? cleanup : nil
        if action != nil { cleanup = nil; packageURL = nil }
        lock.unlock()
        action?()
    }
    private func status(_ value: InstallerStatusViewModel.InstallerStatus) {
        DispatchQueue.main.async { self.viewModel.status = value }
    }
    private func configure(_ candidate: Application) {
        candidate.get("*") { [weak self] req -> Response in
            guard let self, FeatherAccessManager.shared.permitsAccess() else { return Response(status: .forbidden) }
            switch req.url.path {
            case self.payloadEndpoint.path:
                self.lock.lock()
                guard !self.cleanupRequested, let url = self.packageURL else {
                    self.lock.unlock(); return Response(status: .notFound)
                }
                if req.method == .HEAD {
                    self.lock.unlock()
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return Response(status: .ok, headers: ["Content-Length": String(size), "Content-Type": "application/octet-stream"])
                }
                self.readers += 1; self.lock.unlock()
                self.status(.sendingPayload)
                return req.fileio.streamFile(at: url.path) { result in
                    self.finishRead()
                    switch result {
                    case .success: self.status(.installing)
                    case .failure(let error): self.status(.broken(error))
                    }
                }
            case self.displayImageSmallEndpoint.path:
                return Response(status: .ok, headers: ["Content-Type": "image/png"], body: .init(data: self.displayImageSmallData))
            case self.displayImageLargeEndpoint.path:
                return Response(status: .ok, headers: ["Content-Type": "image/png"], body: .init(data: self.displayImageLargeData))
            default: return Response(status: .notFound)
            }
        }
    }
}
