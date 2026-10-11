import Foundation
import AVFoundation
import CoreVideo

@MainActor
enum InstructionPreviewChecks {
    static func run() async {
        guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview" else { return }
        var checks: [String: Bool] = [:]
        var detail = ""
        let playback = InstructionPlayback()
        do {
            let encoded = try JSONEncoder().encode(InstructionIndex(schema_version: 1, instructions: [.sample]))
            let decoded = try InstructionIndex.decode(encoded)
            checks["metadata_roundtrip"] = decoded.instructions == [.sample]
            let duplicate = try JSONEncoder().encode(InstructionIndex(schema_version: 1, instructions: [.sample, .sample]))
            checks["duplicate_rejected"] = (try? InstructionIndex.decode(duplicate)) == nil
            checks["http_rejected"] = !StoreInstruction.isTrusted(URL(string: "http://json.dzhabaapps.ru/instruction-media/test.mp4")!)
            checks["foreign_host_rejected"] = !StoreInstruction.isTrusted(URL(string: "https://example.com/test.mp4")!)
            checks["no_video_before_play"] = playback.player == nil
            playback.start(StoreInstruction.sample.video_url)
            guard let player = playback.player, let item = player.currentItem else { throw URLError(.cannotOpenFile) }
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            item.add(output)
            let firstFrame = await waitForFrame(player, item, output, after: 0.1)
            checks["github_native_first_frame"] = firstFrame
            checks["github_native_ready"] = item.status == .readyToPlay
            let second = InstructionPlayback()
            second.start(StoreInstruction.sample.video_url)
            checks["only_one_active_player"] = playback.player == nil && player.currentItem == nil
            second.stop()
            playback.start(StoreInstruction.sample.video_url)
            guard let seekPlayer = playback.player, let seekItem = seekPlayer.currentItem else { throw URLError(.cannotOpenFile) }
            let seekOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            seekItem.add(seekOutput)
            _ = await waitForFrame(seekPlayer, seekItem, seekOutput, after: 0.1)
            let seekDone = await withCheckedContinuation { continuation in
                seekPlayer.seek(to: CMTime(seconds: 30, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) {
                    continuation.resume(returning: $0)
                }
            }
            let seekFrame = await waitForFrame(seekPlayer, seekItem, seekOutput, after: 30)
            checks["github_native_seek_frame"] = seekDone && seekFrame
            playback.pause()
            checks["pause_stops_playback"] = seekPlayer.rate == 0
            playback.stop()
            checks["leaving_releases_item"] = playback.player == nil && seekPlayer.currentItem == nil
            playback.start(URL(string: "https://example.com/video.mp4")!)
            checks["invalid_source_has_retry_error"] = playback.player == nil && playback.error != nil
        } catch { detail = String(describing: error) }
        playback.stop()
        let result: [String: Any] = ["checks": checks, "error": detail,
            "passed": detail.isEmpty && checks.count == 12 && checks.values.allSatisfy { $0 },
            "commit": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""]
        let url = URL.documentsDirectory.appendingPathComponent("instruction-validation.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func waitForFrame(_ player: AVPlayer, _ item: AVPlayerItem, _ output: AVPlayerItemVideoOutput, after seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(35)
        while Date() < deadline {
            if item.status == .failed { return false }
            let time = player.currentTime()
            if time.seconds >= seconds, output.hasNewPixelBuffer(forItemTime: time),
               output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) != nil { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }
}
