import Foundation

enum CatalogCategory: String, CaseIterable, Identifiable {
    case all, finance, social, games, other
    static var storeFilters: [CatalogCategory] { [.all, .finance, .social, .games, .other] }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Все"
        case .finance: return "Финансы"
        case .social: return "Соцсети"
        case .games: return "Игры"
        case .other: return "Другое"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .finance: return "creditcard"
        case .social: return "bubble.left.and.bubble.right"
        case .games: return "gamecontroller"
        case .other: return "ellipsis.circle"
        }
    }
    static func resolve(bundleID: String?, metadata: String?) -> CatalogCategory {
        if let value = metadata?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty {
            switch value {
            case "finance", "financial", "финансы", "банки": return .finance
            case "social", "socialnetworking", "social networking", "соцсети", "социальные сети": return .social
            case "games", "game", "игры": return .games
            default: return .other
            }
        }
        return knownApps[bundleID?.lowercased() ?? ""] ?? .other
    }
    // Exact IDs classify the current feed, whose entries lack category metadata.
    private static let knownApps: [String: CatalogCategory] = [
        "ru.bychokcabernet.winescanner": .finance, "com.flavorvault.savor": .finance, "com.inv.gen": .finance,
        "net.whatsapp.whatsapp": .social, "net.whatsapp.whatsappsmb": .social,
        "com.burbn.instagram": .social, "ru.oneme.app": .social,
        "ru.odnoklassniki.iphone": .social, "com.zhiliaoapp.musically": .social

    ]
}

enum SubscriptionPresentation {
    static func expiry(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }
}
