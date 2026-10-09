//
//  enum.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import Foundation
import Combine
import UIKit
import BackgroundTasks

class Download: Identifiable, @unchecked Sendable {
    let cancellation = DownloadCancellation()
	@Published var progress: Double = 0.0
	@Published var bytesDownloaded: Int64 = 0
	@Published var totalBytes: Int64 = 0
	@Published var unpackageProgress: Double = 0.0
	
	var overallProgress: Double {
		onlyArchiving
		? unpackageProgress
		: (0.3 * unpackageProgress) + (0.7 * progress)
	}
	
	var task: URLSessionDownloadTask?
	var resumeData: Data?
	
	let id: String
	let url: URL
	let source: URL
	let fileName: String
	let displayName: String
	let onlyArchiving: Bool
	
	init(
		id: String,
		url: URL,
		source: URL? = nil,
		displayName: String? = nil,
		onlyArchiving: Bool = false
	) {
		self.id = id
		self.url = url
		self.source = source ?? url
		self.onlyArchiving = onlyArchiving
		self.fileName = url.lastPathComponent
		self.displayName = DownloadPresentation.title(displayName: displayName, url: url)
	}
}

// Delegates and persistence are serialized on the main queue.
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    @Published var downloads: [Download] = []
    @Published private(set) var isRestoring = true
    var manualDownloads: [Download] { downloads.filter { isManualDownload($0.id) } }
    private var _session: URLSession!
    private var legacySessions: [URLSession] = []
    private var audioIsRunning = false
    private let store = BackgroundDownloadStore()
    private var records: [String: BackgroundDownloadRecord] = [:]
    private var processing: Set<String> = []
    private var activeObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var pendingError: String?

    override init() {
        super.init()
        for record in store.records() {
            records[record.id] = record
            let download = Download(id: record.id, url: record.url, source: record.source, displayName: record.displayName)
            if store.isReady(record) { download.progress = 1 }
            downloads.append(download)
        }
        // Match upstream/provider Feather: in-process downloads, kept running by
        // BGContinuedProcessingTask (iOS26) or the existing audio runtime (older iOS).
        // nsurlsessiond file delivery fails for some supplier profile identities.
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        _session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.processReadyDownloads()
        }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            if Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview", ProcessInfo.processInfo.environment["FIZER_PREVIEW_SCREEN"] == "background-transfer" {
                try? Data("background".utf8).write(to: URL.documentsDirectory.appendingPathComponent("background-test-lifecycle.txt"), options: .atomic)
            }
        }
        let restoreTasks = {
          self._session.getAllTasks { tasks in
            DispatchQueue.main.async {
                for case let task as URLSessionDownloadTask in tasks {
                    guard let download = self.restore(task) else { task.cancel(); continue }
                    download.task = task
                    if task.countOfBytesExpectedToReceive > 0 {
                        download.progress = Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive)
                    }
                }
                self.isRestoring = false
                self.processReadyDownloads()
            }
          }
        }
        restoreTasks()
        let migrationKey = "Fizer.DownloadSessionInProcess"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            for version in ["v1", "v2"] {
                let identifier = (Bundle.main.bundleIdentifier ?? "thewonderofyou.Feather") + ".downloads." + version
                let old = URLSession(configuration: .background(withIdentifier: identifier), delegate: self, delegateQueue: .main)
                legacySessions.append(old)
                old.getAllTasks { tasks in
                    for task in tasks { task.cancel() }
                    old.invalidateAndCancel()
                    DispatchQueue.main.async { self.legacySessions.removeAll { $0 === old } }
                }
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    private func updateAudioRuntime() {
        #if !targetEnvironment(macCatalyst)
        let running = downloads.filter { !$0.onlyArchiving && $0.task?.state == .running && $0.progress < 1 }
        let needed: Bool
        if #available(iOS 26.0, *) {
            // Queued/rejected continued work must not silently strand a transfer.
            // Use upstream's existing audio runtime until a continued task takes over.
            needed = running.contains { !BackgroundTaskManager.shared.isRunning(for: $0.id) }
        } else { needed = !running.isEmpty }
        guard needed != audioIsRunning else { return }
        if needed {
            audioIsRunning = BackgroundAudioManager.shared.start()
            previewDiagnostic(audioIsRunning ? "audio-fallback-active" : "audio-runtime-unavailable")
        } else {
            BackgroundAudioManager.shared.stop()
            audioIsRunning = false
            previewDiagnostic("audio-runtime-stopped")
        }
        #endif
    }

    func backgroundRuntimeDidChange(_ status: String) {
        previewDiagnostic(status)
        updateAudioRuntime()
    }

    func suspendForBackgroundExpiration(_ id: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        getDownload(by: id)?.task?.suspend()
        updateAudioRuntime()
        // The journal retains the intent; foreground entry resumes this task.
    }

    func startDownload(from url: URL, id: String = UUID().uuidString, source: URL? = nil, displayName: String? = nil) -> Download {
        let download = Download(id: id, url: url, source: source, displayName: displayName)
        guard FeatherAccessManager.shared.permitsAccess() else { return download }
        return enqueue(download)
    }

    private func enqueue(_ download: Download) -> Download {
        let id = download.id, url = download.url, source = download.source
        if let existing = downloads.first(where: { $0.id == id || ($0.url == url && $0.source == source) }) { return existing }
        let record = BackgroundDownloadRecord(token: UUID(), id: id, url: url, source: source, displayName: download.displayName)
        do {
            try store.save(record)
            records[id] = record
            downloads.append(download)
            startProgress(download)
            beginTask(download, record: record)
        } catch { reportError("Не удалось сохранить загрузку. Освободите место и попробуйте снова.") }
        return download
    }

    func startPreviewTransfer() {
        guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview",
              ProcessInfo.processInfo.environment["FIZER_PREVIEW_SCREEN"] == "background-transfer",
              let value = ProcessInfo.processInfo.environment["FIZER_BACKGROUND_TEST_URL"],
              let url = URL(string: value), url.host == "127.0.0.1", url.scheme == "http" else { return }
        previewDiagnostic("preview appeared; state=\(UIApplication.shared.applicationState.rawValue)")
        Task { @MainActor in
            // A simctl cold launch can render before the application becomes active.
            // Starting a background task in that state lets iOS defer it as discretionary.
            for _ in 0..<120 {
                if UIApplication.shared.applicationState == .active && !isRestoring { break }
                try? await Task.sleep(for: .seconds(1))
            }
            guard UIApplication.shared.applicationState == .active, !isRestoring else {
                previewDiagnostic("preview did not become active")
                return
            }
            previewDiagnostic("preview active; enqueue")
            _ = enqueue(Download(id: "background-integration", url: url, displayName: "Фоновая проверка"))
        }
    }

    private func previewDiagnostic(_ message: String) {
        guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview",
              ProcessInfo.processInfo.environment["FIZER_PREVIEW_SCREEN"] == "background-transfer" else { return }
        let file = URL.documentsDirectory.appendingPathComponent("background-test-diagnostic.txt")
        let previous = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try? Data((previous + message + "\n").utf8).write(to: file, options: .atomic)
    }

    private func beginTask(_ download: Download, record: BackgroundDownloadRecord) {
        var attempt = record
        attempt.attempt = UUID()
        do {
            let description = try JSONEncoder().encode(attempt)
            try store.save(attempt)
            records[download.id] = attempt
            let task = _session.downloadTask(with: attempt.url)
            task.taskDescription = String(data: description, encoding: .utf8)
            download.task = task
            task.resume()
            updateAudioRuntime()
            previewDiagnostic("task resumed; state=\(task.state.rawValue)")
        } catch {
            finish(download)
            reportError("Не удалось сохранить загрузку. Освободите место и попробуйте снова.")
        }
    }

    func startArchive(from url: URL, id: String = UUID().uuidString) -> Download {
        let download = Download(id: id, url: url, onlyArchiving: true)
        downloads.append(download)
        return download
    }

    func resumeDownload(_ download: Download) {
        guard FeatherAccessManager.shared.permitsAccess(), let record = records[download.id], !store.isReady(record) else { return }
        if let task = download.task { task.resume(); updateAudioRuntime() } else { beginTask(download, record: record) }
    }

    func cancelDownload(_ download: Download) {
        download.cancellation.cancel()
        if let record = records[download.id] {
            do { try store.cancel(record) }
            catch { reportError("Не удалось сохранить отмену. Повторите отмену перед закрытием Feather."); return }
        }
        download.task?.cancel()
        finish(download)
    }
    private func finish(_ download: Download, success: Bool = false) {
        guard getDownload(by: download.id) === download else { return }
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) { BackgroundTaskManager.shared.stopTask(for: download.id, success: success) }
        #endif
        if let record = records.removeValue(forKey: download.id) { try? store.remove(record) }
        processing.remove(download.id)
        downloads.removeAll { $0.id == download.id }
        updateAudioRuntime()
    }
    private func startProgress(_ download: Download) {
        guard download.progress < 1 else { return }
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            BackgroundTaskManager.shared.startTask(for: download.id, filename: download.displayName)
            BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.progress)
        }
        #endif
    }
    func isManualDownload(_ id: String) -> Bool { id.contains("FeatherManualDownload") }
    func getDownload(by id: String) -> Download? { downloads.first { $0.id == id } }
    func getDownloadIndex(by id: String) -> Int? { downloads.firstIndex { $0.id == id } }
    func getDownloadTask(by task: URLSessionDownloadTask) -> Download? { restore(task) }

    private func restore(_ task: URLSessionDownloadTask) -> Download? {
        if let existing = downloads.first(where: { $0.task?.taskIdentifier == task.taskIdentifier }) { return existing }
        guard let description = task.taskDescription, let data = description.data(using: .utf8),
              let record = try? JSONDecoder().decode(BackgroundDownloadRecord.self, from: data) else { return nil }
        if let existing = getDownload(by: record.id) {
            guard records[record.id]?.token == record.token, records[record.id]?.attempt == record.attempt else { return nil }
            existing.task = task; return existing
        }
        // Ignore events from a cancelled task whose record has already been deleted.
        guard store.records().contains(where: { $0.token == record.token && $0.attempt == record.attempt }) else { return nil }
        let download = Download(id: record.id, url: record.url, source: record.source, displayName: record.displayName)
        download.task = task
        records[record.id] = record
        downloads.append(download)
        return download
    }

    private func reportError(_ message: String) {
        previewDiagnostic(message)
        if UIApplication.shared.applicationState == .active {
            UIAlertController.showAlertWithOk(title: "Загрузка не завершена", message: message)
        } else { pendingError = message }
    }

    func processForegroundDownloads() { processReadyDownloads() }

    private func processReadyDownloads() {
        guard !isRestoring, UIApplication.shared.applicationState == .active else { return }
        if let message = pendingError { pendingError = nil; reportError(message) }
        for download in downloads {
            guard let record = records[download.id], !processing.contains(download.id) else { continue }
            startProgress(download)
            if download.task?.state == .suspended { download.task?.resume(); updateAudioRuntime() }
            if store.isReady(record) {
                // Isolated simulator fixture retains actual received bytes for verification.
                if Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview",
                   ProcessInfo.processInfo.environment["FIZER_BACKGROUND_TEST_HOLD_IMPORT"] == "1" { continue }
                download.progress = 1
                // Import may have succeeded just before the system terminated the app.
                if RepositoryInstallCoordinator.shared.libraryApp(for: record.source) != nil { finish(download, success: true); continue }
                processing.insert(download.id)
                try? handlePachageFile(url: store.packageURL(record), dl: download)
            } else if download.task == nil, FeatherAccessManager.shared.permitsAccess() {
                // A user force-quit cancels iOS transfers; restarting the app permits a fresh attempt.
                beginTask(download, record: record)
            }
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func handlePachageFile(url: URL, dl: Download, completion: (() -> Void)? = nil) throws {
        FR.handlePackageFile(url, download: dl) { error in
            if let error, !dl.cancellation.isCancelled { self.reportError(error.localizedDescription) }
            if dl.id == "background-integration", Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview" {
                let result = ["imported": error == nil, "source": dl.source.absoluteString] as [String: Any]
                if let data = try? JSONSerialization.data(withJSONObject: result) {
                    try? data.write(to: URL.documentsDirectory.appendingPathComponent("background-test-result.json"), options: .atomic)
                }
            }
            let downloadsRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FeatherDownloads").path + "/"
            if url.path.hasPrefix(downloadsRoot) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            self.finish(dl, success: error == nil)
            completion?()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard session === _session else { return }
        guard let download = restore(downloadTask), let record = records[download.id] else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw NSError(domain: "Fizer.Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Сервер не смог выдать файл. Попробуйте скачать приложение снова."])
            }
            // Move synchronously: URLSession deletes its temporary file after this delegate returns.
            try store.receive(location, for: record)
            download.progress = 1
            #if !targetEnvironment(macCatalyst)
            if #available(iOS 26.0, *) {
                BackgroundTaskManager.shared.updateProgress(for: download.id, progress: 1)
                BackgroundTaskManager.shared.stopTask(for: download.id, success: true)
            }
            #endif
            download.task = nil
            updateAudioRuntime()
            processReadyDownloads()
        } catch { finish(download); reportError(error.localizedDescription) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard session === _session else { return }
        guard let download = restore(downloadTask) else { return }
        download.progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        download.bytesDownloaded = totalBytesWritten
        download.totalBytes = totalBytesExpectedToWrite
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) { BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.progress) }
        #endif
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard session === _session else { return }
        guard let error, let task = task as? URLSessionDownloadTask, let download = restore(task) else { return }
        previewDiagnostic("native error domain=\((error as NSError).domain) code=\((error as NSError).code): \(error.localizedDescription)")
        if (error as NSError).code == NSURLErrorCancelled {
            // Explicit Cancel removed the record already. A surviving record means iOS cancelled
            // the transfer (for example after force-quit); keep the user's intent for relaunch.
            download.task = nil
            processReadyDownloads()
            return
        }
        finish(download)
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain && [NSURLErrorCannotCreateFile, NSURLErrorCannotWriteToFile, NSURLErrorCannotMoveFile].contains(failure.code) {
            reportError("Не удалось сохранить файл приложения. Проверьте свободное место на iPhone и повторите загрузку. Если ошибка повторяется, закройте и откройте Fizer.")
        } else {
            reportError("Не удалось скачать приложение. Проверьте интернет и попробуйте снова. " + error.localizedDescription)
        }
    }
}
