import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let share = URL(string: "https://disk.yandex.ru/d/example")!
let host = URL(string: "https://mds.storage.yandex.net/file")!
precondition(GameDataSource.accepts(share))
precondition(!GameDataSource.accepts(URL(string: "https://disk.yandex.ru.other.test/d/example")!))
precondition(!GameDataSource.accepts(URL(string: "https://disk.yandex.ru/d/example/nested")!))
precondition(GameDataSource.acceptsDownload(host))
precondition(!GameDataSource.acceptsDownload(URL(string: "https://other.test/?url=storage.yandex.net")!))
precondition(GameDataSource.safeName("GTAV"))
precondition(GameDataSource.safeName("GTAV.zip"))
precondition(!GameDataSource.safeName("../GTAV"))
precondition(!GameDataSource.safeName("folder\\GTAV"))

let block = GameDataSource.blockSize
let size: Int64 = 21_066_305_489
precondition(GameDataSource.range(from: 0, size: size) == 0...(block - 1))
precondition(GameDataSource.range(from: block, size: size) == block...(2 * block - 1))
precondition(GameDataSource.range(from: size - 4, size: size) == (size - 4)...(size - 1))
precondition(GameDataSource.range(from: size, size: size) == nil)

func response(_ status: Int, _ contentRange: String, _ tag: String) -> HTTPURLResponse {
    HTTPURLResponse(url: host, statusCode: status, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Range": contentRange, "ETag": tag])!
}

let etag = "\"archive-v1\""
let last = (size - 4)...(size - 1)
let header = "bytes \(last.lowerBound)-\(last.upperBound)/\(size)"
let accepted = try GameDataSource.checkedETag(response(206, header, etag), range: last, size: size, previous: etag)
precondition(accepted == etag)
let yandexTag = "5f6118941202525a4e6c14e13069b26e"
let yandexAccepted = try GameDataSource.checkedETag(response(206, header, yandexTag), range: last, size: size, previous: "\"" + yandexTag + "\"")
precondition(yandexAccepted == yandexTag)
for invalid in [response(200, header, etag), response(206, "bytes 0-3/4", etag),
                response(206, header, "\"archive-v2\""), response(206, header, "W/" + etag),
                response(412, header, etag)] {
    precondition((try? GameDataSource.checkedETag(invalid, range: last, size: size, previous: etag)) == nil)
}
print("Game data: share recognition, safe filename, 64-bit checkpoints, exact range and unchanged file identity passed.")
