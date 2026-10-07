import Foundation

enum CatalogCategory: String, CaseIterable, Identifiable {
    case all, finance, social, games, utilities, media, education, shopping, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Все"
        case .finance: return "Финансы"
        case .social: return "Соцсети"
        case .games: return "Игры"
        case .utilities: return "Утилиты"
        case .media: return "Фото и видео"
        case .education: return "Обучение"
        case .shopping: return "Покупки"
        case .other: return "Другое"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .finance: return "creditcard"
        case .social: return "bubble.left.and.bubble.right"
        case .games: return "gamecontroller"
        case .utilities: return "wrench.and.screwdriver"
        case .media: return "play.rectangle"
        case .education: return "graduationcap"
        case .shopping: return "bag"
        case .other: return "ellipsis.circle"
        }
    }
    static func resolve(bundleID: String?, metadata: String?) -> CatalogCategory {
        if let value = metadata?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty {
            switch value {
            case "finance", "financial", "финансы", "банки": return .finance
            case "social", "socialnetworking", "social networking", "соцсети", "социальные сети": return .social
            case "games", "game", "игры": return .games
            case "utilities", "utility", "productivity", "navigation", "travel", "утилиты", "навигация": return .utilities
            case "media", "entertainment", "photo & video", "photoandvideo", "photography", "music", "фото и видео", "развлечения": return .media
            case "education", "learning", "обучение", "образование": return .education
            case "shopping", "покупки": return .shopping
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
        "ru.odnoklassniki.iphone": .social, "com.zhiliaoapp.musically": .social,
        "com.google.ios.youtube": .media, "me.keet.hdrezka": .media, "com.vk.vkvideo.prod1235": .media,
        "com.alightcreative.motion": .media, "com.firecore.infuse": .media, "com.picsart.studio": .media,
        "sh.weme.wemesh": .media, "com.kinemaster.kios": .media,
        "com.damtechdesigns.wa.story": .media, "com.tickettothemoon.video.persona": .media,
        "ru.mail.mail": .utilities, "ru.dorogi20260609.passenger": .utilities,
        "com.iteration-mobile.radarbot-free-ww": .utilities, "com.alpinquest.app": .utilities,
        "com.duolingo.duolingomobile": .education,
        "com.allgoritm.youla": .shopping, "org.reactjs.native.prod.aureactnativeapp": .shopping
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
