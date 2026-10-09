//
//  BackgroundTaskManager.swift
//  Feather
//
//  Created by Nagata Asami on 4/1/26.
//

#if !targetEnvironment(macCatalyst)

import Foundation
import BackgroundTasks
import CryptoKit
import UIKit

@available(iOS 26.0, *)
class BackgroundTaskManager: ObservableObject {
	static let shared = BackgroundTaskManager()
	
	private let baseId = "\(Bundle.main.bundleIdentifier!).userTask"
	
	private var activeTasks: [String: BGContinuedProcessingTask] = [:]
	private var registeredTasks: Set<String> = []
    private var requested: [String: Double] = [:]
	
	func startTask(for downloadId: String, filename: String) {
		guard UIApplication.shared.applicationState == .active else { return }
        let taskIdentifier = "\(baseId).\(downloadId.md5)"
        guard requested[taskIdentifier] == nil else { return }
		if !registeredTasks.contains(taskIdentifier) {
			let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
				guard let task = task as? BGContinuedProcessingTask else { return }
				guard let progress = self.requested[task.identifier] else { task.setTaskCompleted(success: false); return }
                self.activeTasks[task.identifier] = task
                task.progress.totalUnitCount = 1000
                task.progress.completedUnitCount = Int64(progress * 1000)
				
                task.expirationHandler = {
                    DispatchQueue.main.async {
                        guard self.activeTasks[task.identifier] === task else { return }
                        // The system uses the same handler for its Stop button and
                        // runtime expiration. Neither may silently restart the job.
                        if let download = DownloadManager.shared.getDownload(by: downloadId) {
                            DownloadManager.shared.cancelDownload(download)
                        } else {
                            self.stopTask(for: downloadId, success: false)
                        }
                        DownloadManager.shared.backgroundRuntimeDidChange("continued-stopped")
                    }
                }
                DownloadManager.shared.backgroundRuntimeDidChange("continued-active")
			}
            guard registered else {
                DownloadManager.shared.backgroundRuntimeDidChange("continued-registration-rejected")
                return
            }
			self.registeredTasks.insert(taskIdentifier)
		}
		
		requested[taskIdentifier] = 0
        let request = BGContinuedProcessingTaskRequest(identifier: taskIdentifier, title: filename, subtitle: .localized("Downloading"))
		request.strategy = .queue
		do {
			try BGTaskScheduler.shared.submit(request)
            DownloadManager.shared.backgroundRuntimeDidChange("continued-queued")
		} catch {
			requested.removeValue(forKey: taskIdentifier)
            let failure = error as NSError
            DownloadManager.shared.backgroundRuntimeDidChange("continued-rejected \(failure.domain) \(failure.code)")
		}
	}
	
    func isRunning(for downloadId: String) -> Bool {
        activeTasks["\(baseId).\(downloadId.md5)"] != nil
    }

	func updateProgress(for downloadId: String, progress: Double) {
		let taskIdentifier = "\(baseId).\(downloadId.md5)"
		
        guard requested[taskIdentifier] != nil, progress.isFinite else { return }
        let value = min(1, max(0, progress))
        requested[taskIdentifier] = value
        guard let task = activeTasks[taskIdentifier] else { return }
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = Int64(value * 1000)
        task.updateTitle(task.title, subtitle: "\(Int(value * 100))%")
	}
	
	func stopTask(for downloadId: String, success: Bool) {
		let taskIdentifier = "\(baseId).\(downloadId.md5)"
		requested.removeValue(forKey: taskIdentifier)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        guard let task = activeTasks[taskIdentifier] else { return }
		task.setTaskCompleted(success: success)
		activeTasks.removeValue(forKey: taskIdentifier)
	}
}

extension String {
	var md5: String {
		Insecure.MD5.hash(data: Data(self.utf8)).map { String(format: "%02hhx", $0) }.joined()
	}
}

#endif
