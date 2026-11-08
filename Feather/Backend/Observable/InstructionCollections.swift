import Foundation

struct InstructionAppSummary: Equatable {
    let id: String
    let name: String
    let iconURL: URL?
}

struct InstructionCollection: Identifiable, Equatable {
    let id: String
    let title: String
    let iconURL: URL?
    let instructions: [StoreInstruction]
}

enum InstructionCollections {
    static func key(for bundleID: String) -> String {
        let id = bundleID.lowercased()
        if id.hasPrefix("net.whatsapp.") { return "family:whatsapp" }
        if id.hasPrefix("com.burbn.instagram") { return "family:instagram" }
        return "app:" + id
    }

    static func title(for bundleID: String, fallback: String) -> String {
        switch key(for: bundleID) {
        case "family:whatsapp": return "WhatsApp"
        case "family:instagram": return "Instagram"
        case "app:com.macport.gtav": return "GTA V"
        default: return fallback
        }
    }

    static func isGeneral(_ item: StoreInstruction) -> Bool {
        item.bundle_ids.isEmpty || item.section == "general"
    }

    static func build(_ instructions: [StoreInstruction], apps: [InstructionAppSummary]) -> [InstructionCollection] {
        var summaries: [String: InstructionAppSummary] = [:]
        for app in apps where summaries[app.id.lowercased()] == nil { summaries[app.id.lowercased()] = app }
        var items: [String: [StoreInstruction]] = [:]
        var labels: [String: String] = [:]
        var icons: [String: URL] = [:]
        for item in instructions where !isGeneral(item) {
            var seen: Set<String> = []
            for bundleID in item.bundle_ids {
                let id = key(for: bundleID)
                guard seen.insert(id).inserted else { continue }
                items[id, default: []].append(item)
                let summary = summaries[bundleID.lowercased()]
                if labels[id] == nil || summary != nil {
                    labels[id] = title(for: bundleID, fallback: summary?.name ?? "Инструкции приложения")
                }
                if icons[id] == nil, let url = summary?.iconURL { icons[id] = url }
            }
        }
        return items.map { id, videos in
            InstructionCollection(id: id, title: labels[id] ?? "Инструкции приложения", iconURL: icons[id], instructions: videos)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func countLabel(_ count: Int) -> String { "\(count) видео" }

    static func matches(_ item: StoreInstruction, query: String) -> Bool {
        query.isEmpty || (item.title + " " + item.description).localizedCaseInsensitiveContains(query)
    }
}
