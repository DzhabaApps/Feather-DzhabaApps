import Foundation
import Combine
import UIKit

/// One GTA data download. The background session writes each range to disk.
/// The assembled file and its identity survive a relaunch. State and delegate callbacks run on the main queue.
final class GameDataDownload: NSObject, ObservableObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = GameDataDownload()
    static let sessionID = (Bundle.main.bundleIdentifier ?? "Feather") + ".game-data"

    struct Transfer: Codable {
        let id: UUID
        let share: URL
        let size: Int64
        let name: String
        var etag: String?
    }

    private struct Block: Codable {
        let id: UUID
        let range: ClosedRange<Int64>
    }

    @Published private(set) var transfer: Transfer?
    @Published private(set) var received: Int64 = 0
    @Published private(set) var working = false
    @Published private(set) var installing = false
    @Published private(set) var error: String?

    private let files = FileManager.default
    private let root = URL.applicationSupportDirectory.appendingPathComponent("DRStoreGameData", isDirectory: true)
    private var recordURL: URL { root.appendingPathComponent("transfer.json") }
    private var task: URLSessionDownloadTask?
    private var resolution: Task<Void, Never>?
    private var directURL: URL?
    private var refreshedExpiredLink = false
    private var systemCompletion: (() -> Void)?
    private var eventsFinished = false
    private let progressID = "dr-store-game-data"
    private let diagnosticsURL = URL.cachesDirectory.appendingPathComponent("DRStoreGameDataDiagnostics.txt")
    private var diagnosticLines: [String] = []
    private var lastProgressLog = -Double.infinity

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
        if let savedLog = try? String(contentsOf: diagnosticsURL, encoding: .utf8) {
            diagnosticLines = Array(savedLog.split(separator: "\n").suffix(100).map(String.init))
        }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(recordLifecycle(_:)), name: name, object: nil)
        }
        guard let data = try? Data(contentsOf: recordURL),
              let saved = try? JSONDecoder().decode(Transfer.self, from: data),
              GameDataSource.safeName(saved.name), GameDataSource.accepts(saved.share) else { return }
        transfer = saved
        received = length(of: payload(saved))
        log("restored checkpoint=\(received)/\(saved.size)")
        guard received < saved.size else { return }
        working = true
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self, self.working, self.transfer?.id == saved.id, self.task == nil,
                      self.resolution == nil else { return }
                self.task = tasks.compactMap { $0 as? URLSessionDownloadTask }.first {
                    ($0.state == .running || $0.state == .suspended) && self.block($0)?.id == saved.id
                }
                self.working = self.task != nil
                if let task = self.task, let block = self.block(task) {
                    self.received = block.range.lowerBound + min(task.countOfBytesReceived,
                        block.range.upperBound - block.range.lowerBound + 1)
                    self.beginProgress(title: saved.name)
                    self.showProgress()
                }
            }
        }
    }

    var ready: Bool {
        guard let transfer else { return false }
        return !working && received == transfer.size && transfer.etag != nil
    }

    var exportURL: URL? {
        guard ready, let transfer, length(of: payload(transfer)) == transfer.size else { return nil }
        return payload(transfer)
    }

    func start(share: URL, title: String) {
        guard !working, !ready, GameDataSource.accepts(share) else { return }
        if let transfer, transfer.share != share {
            error = "Сначала удали прежнюю загрузку."
            return
        }
        directURL = nil
        refreshedExpiredLink = false
        lastProgressLog = -Double.infinity
        log("start checkpoint=\(received)")
        beginProgress(title: title)
        showProgress()
        resolve(share: share)
    }

    private func beginProgress(title: String) {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            BackgroundTaskManager.shared.startTask(for: progressID, filename: title) { [weak self] in
                self?.log("system-task expiration callback")
                self?.pause()
            }
        }
        #endif
    }

    func discard() {
        guard !installing else { return }
        pause()
        do {
            if files.fileExists(atPath: root.path) { try files.removeItem(at: root) }
            transfer = nil
            received = 0
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func pause() {
        log("pause checkpoint=\(transfer.map { length(of: payload($0)) } ?? 0)")
        resolution?.cancel()
        resolution = nil
        task?.cancel()
        task = nil
        directURL = nil
        working = false
        if let transfer { received = length(of: payload(transfer)) }
        finishProgress(success: false)
        completeSystemEvents()
    }

    private func showProgress() {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let size = transfer?.size, size > 0 {
            BackgroundTaskManager.shared.updateProgress(for: progressID, progress: Double(received) / Double(size),
                stage: GameDataSource.progressText(received: received, total: size))
        }
        #endif
    }

    private func finishProgress(success: Bool) {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            BackgroundTaskManager.shared.stopTask(for: progressID, success: success)
        }
        #endif
    }

    @MainActor
    func saveFolder(to destination: URL, replacing: Bool) async throws {
        guard !installing, let source = exportURL, let id = transfer?.id else {
            throw GameArchive.Failure.destinationUnavailable
        }
        installing = true
        defer { installing = false }
        try await Task.detached(priority: .userInitiated) {
            try GameArchive.save(source, in: destination, replacing: replacing, transferID: id)
        }.value
        installing = false
        discard()
    }

    func handleSystemEvents(_ completion: @escaping () -> Void) {
        log("background URLSession wake")
        systemCompletion = completion
        _ = session
        completeSystemEvents()
    }

    private func resolve(share: URL) {
        working = true
        error = nil
        resolution = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    resolution = nil
                    completeSystemEvents()
                }
            }
            do {
                let (metadata, url) = try await GameDataSource.resolve(share)
                try Task.checkCancellation()
                guard let size = metadata.size else { throw GameDataSource.Failure.changed }
                if let transfer {
                    guard transfer.name == metadata.name, transfer.size == size else { throw GameDataSource.Failure.changed }
                } else {
                    var directory = root
                    try files.createDirectory(at: directory, withIntermediateDirectories: true)
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try directory.setResourceValues(values)
                    try persist(Transfer(id: UUID(), share: share, size: size, name: metadata.name))
                }
                directURL = url
                showProgress()
                try enqueueBlock()
            } catch {
                if !Task.isCancelled { stop(error, source: "resolve") }
            }
        }
    }

    private func enqueueBlock() throws {
        guard let transfer, let directURL,
              let range = GameDataSource.range(from: length(of: payload(transfer)), size: transfer.size) else {
            throw URLError(.badServerResponse)
        }
        var request = URLRequest(url: directURL)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        request.setValue(transfer.etag, forHTTPHeaderField: "If-Match")
        let description = try JSONEncoder().encode(Block(id: transfer.id, range: range))
        let next = session.downloadTask(with: request)
        next.taskDescription = String(decoding: description, as: UTF8.self)
        task = next
        log("range requested task=\(next.taskIdentifier) offset=\(range.lowerBound) end=\(range.upperBound)")
        next.resume()
    }

    private func persist(_ record: Transfer) throws {
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        transfer = record
    }

    private func payload(_ record: Transfer) -> URL {
        root.appendingPathComponent(record.id.uuidString, isDirectory: true).appendingPathComponent(record.name)
    }

    private func length(of url: URL) -> Int64 {
        (try? files.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func block(_ task: URLSessionTask) -> Block? {
        guard let description = task.taskDescription else { return nil }
        return try? JSONDecoder().decode(Block.self, from: Data(description.utf8))
    }

    private func append(_ block: URL, to destination: URL) throws {
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !files.fileExists(atPath: destination.path) {
            try files.moveItem(at: block, to: destination)
            return
        }
        let input = try FileHandle(forReadingFrom: block)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.seekToEnd()
        while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            try output.write(contentsOf: bytes)
        }
        try output.synchronize()
    }

    private func stop(_ failure: Error, source: String) {
        let details = failure as NSError
        log("\(source) failed domain=\(details.domain) code=\(details.code)")
        task = nil
        working = false
        if let transfer { received = length(of: payload(transfer)) }
        finishProgress(success: false)
        error = (failure as? GameDataSource.Failure)?.localizedDescription
            ?? "Загрузка прервалась. Проверь интернет и свободное место, затем нажми «Продолжить»."
    }

    private func completeSystemEvents() {
        guard eventsFinished, resolution == nil, let completion = systemCompletion else { return }
        eventsFinished = false
        systemCompletion = nil
        completion()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        eventsFinished = true
        completeSystemEvents()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let range = block(downloadTask), range.id == transfer?.id, working else { return }
        received = range.range.lowerBound + min(totalBytesWritten, range.range.upperBound - range.range.lowerBound + 1)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastProgressLog >= 20 {
            lastProgressLog = now
            log("bytes received=\(received) task=\(downloadTask.taskIdentifier)")
        }
        showProgress()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard working, var record = transfer, let block = block(downloadTask), block.id == record.id,
              task?.taskIdentifier == downloadTask.taskIdentifier || (task == nil && resolution == nil) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        log("range response task=\(downloadTask.taskIdentifier) HTTP=\(status)")
        do {
            let destination = payload(record)
            guard length(of: destination) == block.range.lowerBound,
                  let response = downloadTask.response as? HTTPURLResponse,
                  GameDataSource.acceptsDownload(response.url) else { throw URLError(.badServerResponse) }
            task = nil
            if [401, 403, 410].contains(response.statusCode), !refreshedExpiredLink {
                refreshedExpiredLink = true
                received = length(of: destination)
                resolve(share: record.share)
                return
            }
            let tag = try GameDataSource.checkedETag(response, range: block.range, size: record.size, previous: record.etag)
            guard length(of: location) == block.range.upperBound - block.range.lowerBound + 1 else {
                throw URLError(.badServerResponse)
            }
            if record.etag == nil {
                record.etag = tag
                try persist(record)
            }
            try append(location, to: destination)
            received = length(of: destination)
            log("checkpoint saved=\(received)/\(record.size)")
            refreshedExpiredLink = false
            if received == record.size {
                working = false
                directURL = nil
                finishProgress(success: true)
            } else if directURL == nil {
                resolve(share: record.share)
            } else {
                try enqueueBlock()
            }
        } catch {
            stop(error, source: "range validation or write")
        }
    }

    func urlSession(_ session: URLSession, task completed: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let block = block(completed), block.id == transfer?.id else { return }
        let details = error as NSError
        log("URLSession completion task=\(completed.taskIdentifier) domain=\(details.domain) code=\(details.code)")
        guard working,
              task?.taskIdentifier == completed.taskIdentifier || (task == nil && resolution == nil) else { return }
        stop(error, source: "URLSession")
    }

    var diagnosticsReport: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return (["DR Store \(version) / iOS \(UIDevice.current.systemVersion)"] + diagnosticLines).joined(separator: "\n")
    }

    @objc private func recordLifecycle(_ notification: Notification) {
        guard working || transfer != nil else { return }
        log(notification.name == UIApplication.didEnterBackgroundNotification ? "app background" : "app active")
    }

    private func log(_ event: String) {
        let time = String(format: "%.3f", Date().timeIntervalSince1970)
        diagnosticLines.append("\(time) \(event)")
        if diagnosticLines.count > 100 { diagnosticLines.removeFirst(diagnosticLines.count - 100) }
        try? diagnosticLines.joined(separator: "\n").write(to: diagnosticsURL, atomically: true, encoding: .utf8)
    }
}
