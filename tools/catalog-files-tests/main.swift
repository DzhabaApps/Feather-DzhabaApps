import Foundation
import AltSourceKit

func app(_ fields: [String: Any]) throws -> ASRepository.App {
    var base: [String: Any] = ["name": "Game", "bundleIdentifier": "com.demo.game", "iconURL": "https://example.com/icon.png"]
    base.merge(fields) { _, new in new }
    return try JSONDecoder().decode(ASRepository.App.self, from: JSONSerialization.data(withJSONObject: base))
}
let legacy = try app(["version":"1", "size":1048576])
precondition(legacy.additionalFiles == nil && legacy.currentSize == 1048576)
let version = try app(["size":1, "versions":[["version":"2", "size":52428800, "downloadURL":"https://example.com/game.ipa"]]])
precondition(version.currentSize == 52428800)
let zero = try app(["size":0])
precondition(zero.currentSize == nil)
let files = [["name":"Game data", "url":"https://example.com/data.zip", "size":23622320128, "instructionID":"game-video"]]
let game = try app(["additionalFiles": files])
precondition(game.additionalFiles?.first?.size == 23622320128)
precondition(game.additionalFiles?.first?.instructionID == "game-video")
let unsafe = try app(["additionalFiles":[["name":"bad", "url":"javascript:alert(1)", "size":1]]])
precondition(unsafe.additionalFiles?.isEmpty == true)
let malformed = try app(["additionalFiles":"old invalid metadata"])
precondition(malformed.additionalFiles == nil)
precondition(CatalogFileSize.string(52428800) == "50 МБ")
precondition(CatalogFileSize.string(23622320128) == "22 ГБ")
print("Catalog files: legacy decoding, current version size, >20GB metadata, unsafe URL isolation and display formatting passed")
