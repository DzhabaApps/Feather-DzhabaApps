import Foundation

assert(CatalogCategory.resolve(bundleID: "com.flavorvault.savor", metadata: nil) == .finance)
assert(CatalogCategory.resolve(bundleID: "NET.WHATSAPP.WHATSAPP", metadata: nil) == .social)
assert(CatalogCategory.resolve(bundleID: "new.game", metadata: " Игры ") == .games)
assert(CatalogCategory.resolve(bundleID: "new.bank", metadata: "FINANCE") == .finance)
assert(CatalogCategory.resolve(bundleID: "unknown", metadata: nil) == .other)
assert(CatalogCategory.resolve(bundleID: "unknown", metadata: "unrecognized") == .other)
assert(CatalogCategory.resolve(bundleID: "com.flavorvault.savor", metadata: "utilities") == .utilities)
assert(CatalogCategory.resolve(bundleID: "new.social", metadata: "Social Networking") == .social)
assert(!CatalogCategory.storeFilters.contains(.education))
assert(!CatalogCategory.storeFilters.contains(.shopping))
assert(CatalogCategory.storeFilters.contains(.all) && CatalogCategory.storeFilters.contains(.games))
let data = try Data(contentsOf: URL(fileURLWithPath: "Feather/Resources/CatalogPreview.json"))
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let apps = json["apps"] as! [[String: Any]]
let groups = Dictionary(grouping: apps) { CatalogCategory.resolve(bundleID: $0["bundleIdentifier"] as? String, metadata: $0["category"] as? String) }
assert(apps.count == 26)
assert(groups[.finance]?.count == 3)
assert(groups[.social]?.count == 6)
assert(groups[.media]?.count == 10)
assert(groups[.utilities]?.count == 4)
assert(groups[.education]?.count == 1)
assert(groups[.shopping]?.count == 2)
assert(groups[.other] == nil && groups[.games] == nil)
let date = Date(timeIntervalSince1970: 86400)
assert(SubscriptionPresentation.expiry(date).contains(".1970 "))
assert(!SubscriptionPresentation.expiry(date).contains("AM"))
print("Catalog: metadata precedence, current 26-app classification, unknown fallback and Russian subscription date passed")
