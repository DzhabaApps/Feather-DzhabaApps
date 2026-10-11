import Foundation
import AVFoundation
import CoreVideo
import SwiftUI

@MainActor
enum InstructionPreviewChecks {
    static func run(playback: InstructionPlayback) async {
        guard Bundle.main.bundleIdentifier == "ru.dzhabaapps.fizer.preview" else { return }
        var checks: [String: Bool] = [:]
        var detail = ""
        var transport: [String: Int] = [:]
        var timings: [String: Double] = [:]
        do {
            let encoded = try JSONEncoder().encode(InstructionIndex(schema_version: 1, instructions: [.sample]))
            let decoded = try InstructionIndex.decode(encoded)
            checks["metadata_roundtrip"] = decoded.instructions == [.sample]
            let duplicate = try JSONEncoder().encode(InstructionIndex(schema_version: 1, instructions: [.sample, .sample]))
            checks["duplicate_rejected"] = (try? InstructionIndex.decode(duplicate)) == nil
            checks["http_rejected"] = !StoreInstruction.isTrusted(URL(string: "http://json.dzhabaapps.ru/instruction-media/test.mp4")!)
            checks["foreign_host_rejected"] = !StoreInstruction.isTrusted(URL(string: "https://example.com/test.mp4")!)
            checks["no_video_before_play"] = playback.player == nil
            let started = Date()
            playback.start(StoreInstruction.sample.video_url)
            guard let player = playback.player, let item = player.currentItem else { throw URLError(.cannotOpenFile) }
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            item.add(output)
            let firstFrame = await waitForFrame(player, item, output, after: 0.1)
            timings["firstFrameSeconds"] = Date().timeIntervalSince(started)
            checks["github_native_first_frame"] = firstFrame
            checks["github_native_ready"] = item.status == .readyToPlay
            transport = playback.transportDiagnostics
            if !firstFrame { detail = "First frame: status=\(item.status.rawValue), error=\(item.error.map { String(describing: $0) } ?? "none")" }
            let second = InstructionPlayback()
            second.start(StoreInstruction.sample.video_url)
            checks["only_one_active_player"] = playback.player == nil && player.currentItem == nil
            second.stop()
            playback.start(StoreInstruction.sample.video_url)
            guard let seekPlayer = playback.player, let seekItem = seekPlayer.currentItem else { throw URLError(.cannotOpenFile) }
            let seekOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            seekItem.add(seekOutput)
            _ = await waitForFrame(seekPlayer, seekItem, seekOutput, after: 0.1)
            let seekStarted = Date()
            let seekDone = await withCheckedContinuation { continuation in
                seekPlayer.seek(to: CMTime(seconds: 30, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) {
                    continuation.resume(returning: $0)
                }
            }
            let seekFrame = await waitForFrame(seekPlayer, seekItem, seekOutput, after: 30)
            timings["seekFrameSeconds"] = Date().timeIntervalSince(seekStarted)
            checks["github_native_seek_frame"] = seekDone && seekFrame
            if !seekFrame { detail += "; seek error=\(seekItem.error.map { String(describing: $0) } ?? "none")" }
            playback.pause()
            playback.seek(30, resume: true)
            checks["seek_resumes_requested_playback"] = await waitForFrame(seekPlayer, seekItem, seekOutput, after: 30.1) && playback.wantsPlayback && seekPlayer.rate > 0
            playback.fullScreen = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            checks["fullscreen_presented"] = playback.fullScreenVisible
            checks["fullscreen_keeps_same_item"] = playback.player === seekPlayer && seekPlayer.currentItem === seekItem
            checks["fullscreen_has_video_frame"] = await waitForFrame(seekPlayer, seekItem, seekOutput, after: 30.5)
            let signal = URL.documentsDirectory.appendingPathComponent("instruction-fullscreen-ready.json")
            try? Data("{\"ready\":true}".utf8).write(to: signal, options: .atomic)
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            playback.fullScreen = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            checks["fullscreen_returns_to_inline"] = !playback.fullScreenVisible && playback.player === seekPlayer && seekPlayer.currentItem === seekItem
            playback.pause()
            checks["pause_stops_playback"] = seekPlayer.rate == 0
            playback.stop()
            checks["leaving_releases_item"] = playback.player == nil && seekPlayer.currentItem == nil
            playback.start(URL(string: "https://example.com/video.mp4")!)
            checks["invalid_source_has_retry_error"] = playback.player == nil && playback.error != nil
        } catch { detail = String(describing: error) }
        playback.stop()
        let result: [String: Any] = ["checks": checks, "error": detail,
            "passed": detail.isEmpty && checks.count == 17 && checks.values.allSatisfy { $0 },
            "timings": timings,
            "transport": transport,
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

@MainActor
struct InstructionPlaybackPreviewView: View {
    @StateObject private var playback = InstructionPlayback()
    @State private var started = false
    var body: some View {
        NavigationStack {
            ScrollView { InstructionVideoCard(instruction: .sample, playback: playback).padding() }
                .navigationTitle("Проверка видео").navigationBarTitleDisplayMode(.inline)
        }.onAppear {
            guard !started else { return }
            started = true
            Task { await InstructionPreviewChecks.run(playback: playback) }
        }
    }
}
