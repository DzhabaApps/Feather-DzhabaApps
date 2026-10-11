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
        var received: Int64 = 0
        var retried = false
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
    private final class Segment {
        let offset: Int64
        var data: Data
        init(offset: Int64, data: Data) { self.offset = offset; self.data = data }
    }
    private var cache: [Segment] = []
    private var cacheBytes = 0
    private var cacheHits = 0
    private var totalLength: Int64?
    private var resolvedURL: URL?
    private var resolvedAt = Date.distantPast
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
        queue.sync { ["requests": requests, "partialResponses": partialResponses, "redirects": redirects, "lastStatus": lastStatus, "cacheBytes": cacheBytes, "cacheHits": cacheHits] }
    }

    func invalidate() {
        queue.async {
            self.invalidated = true
            for job in self.jobs.values { job.loading.finishLoading(with: URLError(.cancelled)) }
            self.jobs.removeAll()
            self.cache.removeAll(); self.cacheBytes = 0
            self.session.invalidateAndCancel()
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loading: AVAssetResourceLoadingRequest) -> Bool {
        guard loading.request.url?.scheme == "dr-instruction" else { return false }
        guard !invalidated else { loading.finishLoading(with: URLError(.cancelled)); return true }
        let data = loading.dataRequest
        var offset = data.map { max($0.requestedOffset, $0.currentOffset) } ?? 0
        var length: Int64? = data.map { $0.requestsAllDataToEndOfResource ? nil : max(0, Int64($0.requestedLength) - (offset - $0.requestedOffset)) } ?? 2
        guard offset >= 0, length == nil || length! >= 0 else {
            loading.finishLoading(with: URLError(.badServerResponse)); return true
        }
        if let totalLength {
            fillInformation(loading, total: totalLength)
            if data == nil { cacheHits += 1; loading.finishLoading(); return true }
            length = min(length ?? totalLength, max(0, totalLength - offset))
            while let segment = cache.last(where: { $0.offset <= offset && $0.offset + Int64($0.data.count) > offset }) {
                let start = Int(offset - segment.offset)
                let count = min(segment.data.count - start, Int(length ?? 0))
                guard count > 0 else { break }
                data?.respond(with: segment.data.subdata(in: start..<(start + count)))
                cacheHits += 1; offset += Int64(count); length = (length ?? 0) - Int64(count)
                if length == 0 { loading.finishLoading(); return true }
            }
        }
        if length == 0 {
            if totalLength == nil && loading.contentInformationRequest != nil { length = 2 }
            else { loading.finishLoading(); return true }
        }
        let job = Job(loading, offset: offset, length: length)
        start(job)
        return true
    }

    private func start(_ job: Job) {
        let url = Date().timeIntervalSince(resolvedAt) < 600 ? (resolvedURL ?? original) : original
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let offset = job.offset, length = job.length
        let addition = offset.addingReportingOverflow(max(0, (length ?? 1) - 1))
        let end = length != nil && !addition.overflow ? String(addition.partialValue) : ""
        request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("video/mp4,application/octet-stream", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        jobs[task.taskIdentifier] = job
        requests += 1
        task.resume()
    }

    private func fillInformation(_ loading: AVAssetResourceLoadingRequest, total: Int64) {
        if let info = loading.contentInformationRequest {
            info.contentType = UTType.mpeg4Movie.identifier
            info.contentLength = total
            info.isByteRangeAccessSupported = true
        }
    }

    private func remember(_ data: Data, offset: Int64) {
        // Bounded RAM cache, discarded with the player; never adds files to IPA or disk.
        let blockLimit = 1024 * 1024, limit = 16 * 1024 * 1024
        var position = 0
        while position < data.count {
            let current = offset + Int64(position)
            let last = cache.last
            let append = last != nil && last!.offset + Int64(last!.data.count) == current && last!.data.count < blockLimit
            let count = min(data.count - position, append ? blockLimit - last!.data.count : blockLimit)
            let bytes = data.subdata(in: position..<(position + count))
            if append { last!.data.append(bytes) } else { cache.append(Segment(offset: current, data: bytes)) }
            cacheBytes += count; position += count
            while cacheBytes > limit, !cache.isEmpty { cacheBytes -= cache.removeFirst().data.count }
        }
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
        if [401, 403].contains(http.statusCode), !job.retried, response.url != original {
            jobs.removeValue(forKey: dataTask.taskIdentifier)
            resolvedURL = nil; job.retried = true
            completionHandler(.cancel); start(job); return
        }
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
        totalLength = total
        resolvedURL = response.url; resolvedAt = Date()
        fillInformation(job.loading, total: total)
        job.remaining = min(job.length ?? (total - start), total - start)
        if job.loading.dataRequest == nil || job.loading.dataRequest?.requestedLength == 0 || job.remaining == 0 {
            jobs.removeValue(forKey: dataTask.taskIdentifier)
            job.loading.finishLoading()
            completionHandler(.cancel)
        } else { completionHandler(.allow) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let job = jobs[dataTask.taskIdentifier] else { return }
        let count = min(data.count, Int(job.remaining))
        if count > 0 {
            remember(Data(data.prefix(count)), offset: job.offset + job.received)
            job.received += Int64(count)
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
