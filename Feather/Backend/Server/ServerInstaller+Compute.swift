import Foundation
import UIKit.UIGraphicsImageRenderer

extension ServerInstaller {
    var payloadEndpoint: URL { URL(string: "http://127.0.0.1:\(port)/\(id.uuidString).ipa")! }
    var displayImageSmallEndpoint: URL { URL(string: "http://127.0.0.1:\(port)/app57x57.png")! }
    var displayImageLargeEndpoint: URL { URL(string: "http://127.0.0.1:\(port)/app512x512.png")! }
    var displayImageSmallData: Data { icon(57) }
    var displayImageLargeData: Data { icon(512) }
    private func icon(_ size: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: .init(width: size, height: size))
        return renderer.image { ctx in
            UIColor.tintColor.setFill(); ctx.fill(.init(x: 0, y: 0, width: size, height: size))
        }.pngData() ?? Data()
    }
}
