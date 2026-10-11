import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Supplies public MP4 byte ranges to AVFoundation independently of CDN MIME headers.
/// No media file or complete response is buffered or stored by this loader.
final class InstructionResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private final class Job {
        let loading: AVAssetResourceLoadingRequest
        let offset: Int64
        let length: Int64?
        var remaining: Int64 = 0
        init(_ loading: AVAssetResourceLoadingRequest, offset: Int64, length: Int64?) {
            self.loading = loading; self.offset = offset; self.length = length
        }
    }
    private let original: URL
    private let queue = DispatchQueue(label: "dr-store.instruction-stream")
    private var jobs: [Int: Job] = [:]
    private var invalidated = false
    private var requests = 0
    private var partialResponses = 0
    private var redirects = 0
    private var lastStatus = 0
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 120
        let callbacks = OperationQueue()
        callbacks.maxConcurrentOperationCount = 1
        callbacks.underlyingQueue = queue
        return URLSession(configuration: config, delegate: self, delegateQueue: callbacks)
    }()

    init(url: URL) { original = url; super.init() }

    func makeAsset() -> AVURLAsset {
        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)!
        components.scheme = "dr-instruction"
        let asset = AVURLAsset(url: components.url!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    var diagnostics: [String: Int] {
        queue.sync { ["requests": requests, "partialResponses": partialResponses, "redirects": redirects, "lastStatus": lastStatus] }
    }

    func invalidate() {
        queue.async {
            self.invalidated = true
            for job in self.jobs.values { job.loading.finishLoading(with: URLError(.cancelled)) }
            self.jobs.removeAll()
            self.session.invalidateAndCancel()
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loading: AVAssetResourceLoadingRequest) -> Bool {
        guard loading.request.url?.scheme == "dr-instruction" else { return false }
        guard !invalidated else { loading.finishLoading(with: URLError(.cancelled)); return true }
        let data = loading.dataRequest
        let offset = data.map { max($0.requestedOffset, $0.currentOffset) } ?? 0
        let length: Int64? = data.map { $0.requestsAllDataToEndOfResource ? nil : Int64($0.requestedLength) } ?? 2
        guard offset >= 0, length == nil || length! >= 0 else {
            loading.finishLoading(with: URLError(.badServerResponse)); return true
        }
        var request = URLRequest(url: original, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let addition = offset.addingReportingOverflow(max(0, (length ?? 1) - 1))
        let end = length != nil && !addition.overflow ? String(addition.partialValue) : ""
        request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("video/mp4,application/octet-stream", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        jobs[task.taskIdentifier] = Job(loading, offset: offset, length: length)
        requests += 1
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loading: AVAssetResourceLoadingRequest) {
        let ids = jobs.filter { $0.value.loading === loading }.map(\.key)
        for id in ids { jobs.removeValue(forKey: id) }
        session.getAllTasks { tasks in
            for task in tasks where ids.contains(task.taskIdentifier) { task.cancel() }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "json.dzhabaapps.ru", "dzhabaapps.ru"]
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, allowed.contains(url.host ?? "") else {
            completionHandler(nil); return
        }
        redirects += 1
        var forwarded = request
        forwarded.setValue(task.originalRequest?.value(forHTTPHeaderField: "Range"), forHTTPHeaderField: "Range")
        forwarded.setValue("video/mp4,application/octet-stream", forHTTPHeaderField: "Accept")
        completionHandler(forwarded)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let job = jobs[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); return
        }
        lastStatus = http.statusCode
        let header = http.value(forHTTPHeaderField: "Content-Range") ?? ""
        let parts = header.replacingOccurrences(of: "bytes ", with: "").split(separator: "/")
        let bounds = parts.first?.split(separator: "-") ?? []
        guard http.statusCode == 206, parts.count == 2, bounds.count == 2,
              let start = Int64(bounds[0]), let end = Int64(bounds[1]), let total = Int64(parts[1]),
              start == job.offset, end >= start, end < total, total <= 256 * 1024 * 1024,
              job.length == nil || end - start + 1 == min(job.length!, total - start) else {
            jobs.removeValue(forKey: dataTask.taskIdentifier)
            job.loading.finishLoading(with: NSError(domain: "DRInstructionHTTP", code: http.statusCode))
            completionHandler(.cancel); return
        }
        partialResponses += 1
        if let info = job.loading.contentInformationRequest {
            info.contentType = UTType.mpeg4Movie.identifier
            info.contentLength = total
            info.isByteRangeAccessSupported = true
        }
        job.remaining = min(job.length ?? (total - start), total - start)
        if job.loading.dataRequest == nil || job.remaining == 0 {
            jobs.removeValue(forKey: dataTask.taskIdentifier)
            job.loading.finishLoading()
            completionHandler(.cancel)
        } else { completionHandler(.allow) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let job = jobs[dataTask.taskIdentifier] else { return }
        let count = min(data.count, Int(job.remaining))
        if count > 0 {
            job.loading.dataRequest?.respond(with: data.prefix(count))
            job.remaining -= Int64(count)
        }
        if job.remaining == 0 {
            jobs.removeValue(forKey: dataTask.taskIdentifier)
            job.loading.finishLoading()
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let job = jobs.removeValue(forKey: task.taskIdentifier) else { return }
        if let error { job.loading.finishLoading(with: error) }
        else if job.remaining != 0 { job.loading.finishLoading(with: URLError(.badServerResponse)) }
        else { job.loading.finishLoading() }
    }
}
