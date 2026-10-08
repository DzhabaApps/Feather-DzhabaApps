import Foundation

assert(CatalogCategory.resolve(bundleID: "com.flavorvault.savor", metadata: nil) == .finance)
assert(CatalogCategory.resolve(bundleID: "NET.WHATSAPP.WHATSAPP", metadata: nil) == .social)
assert(CatalogCategory.resolve(bundleID: "new.game", metadata: " Игры ") == .games)
assert(CatalogCategory.resolve(bundleID: "new.bank", metadata: "FINANCE") == .finance)
assert(CatalogCategory.resolve(bundleID: "unknown", metadata: nil) == .other)
assert(CatalogCategory.resolve(bundleID: "unknown", metadata: "unrecognized") == .other)
assert(CatalogCategory.resolve(bundleID: "com.flavorvault.savor", metadata: "utilities") == .other)
assert(CatalogCategory.resolve(bundleID: "new.social", metadata: "Social Networking") == .social)
assert(CatalogCategory.storeFilters == [.all, .finance, .social, .games, .other])
for category in ["utilities", "media", "education", "shopping", "Фото и видео", "Обучение"] {
    assert(CatalogCategory.resolve(bundleID: "net.whatsapp.whatsapp", metadata: category) == .other)
}
let data = try Data(contentsOf: URL(fileURLWithPath: "Feather/Resources/CatalogPreview.json"))
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let apps = json["apps"] as! [[String: Any]]
let groups = Dictionary(grouping: apps) { CatalogCategory.resolve(bundleID: $0["bundleIdentifier"] as? String, metadata: $0["category"] as? String) }
assert(apps.count == 26)
assert(groups[.finance]?.count == 3)
assert(groups[.social]?.count == 6)
assert(groups[.other]?.count == 17)
assert(groups[.games] == nil)
assert(groups.keys.allSatisfy { CatalogCategory.storeFilters.contains($0) })
let date = Date(timeIntervalSince1970: 86400)
assert(SubscriptionPresentation.expiry(date).contains(".1970 "))
assert(!SubscriptionPresentation.expiry(date).contains("AM"))
print("Catalog: metadata precedence, current 26-app classification, unknown fallback and Russian subscription date passed")
