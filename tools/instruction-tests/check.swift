import Foundation
import AVFoundation

@main
struct InstructionTransportCheck {
    static func main() async {
        let url = URL(string: "https://github.com/DzhabaApps/Dzhaba-Apps/releases/download/dr-store-video-instructions/technical-playback-test.mp4")!
        let loader = InstructionResourceLoader(url: url)
        let asset = loader.makeAsset()
        do {
            let duration = try await asset.load(.duration)
            let playable = try await asset.load(.isPlayable)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let replay = loader.makeAsset()
            let replayDuration = try await replay.load(.duration)
            let generator = AVAssetImageGenerator(asset: replay)
            let tail = try await generator.image(at: CMTime(seconds: 44, preferredTimescale: 600))
            let metrics = loader.diagnostics
            guard abs(duration.seconds - 45) < 1, playable, !tracks.isEmpty,
                  (metrics["partialResponses"] ?? 0) > 0,
                  (metrics["cacheHits"] ?? 0) > 0, abs(replayDuration.seconds - 45) < 1,
                  (metrics["cacheBytes"] ?? 0) <= 16 * 1024 * 1024, tail.image.width > 0 else {
                throw URLError(.cannotDecodeContentData)
            }
            print("Native MP4 range transport passed: \(metrics)")
            asset.cancelLoading()
            replay.cancelLoading()
            loader.invalidate()
        } catch {
            let failure = error as NSError
            print("Native MP4 range transport failed: \(failure.domain) \(failure.code); \(loader.diagnostics)")
            asset.cancelLoading()
            loader.invalidate()
            exit(1)
        }
    }
}
