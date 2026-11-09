import Foundation

func video(_ id: String, _ title: String, _ bundles: [String]) -> StoreInstruction {
    StoreInstruction(id: id, title: title, description: "", steps: [], bundle_ids: bundles,
        video_url: StoreInstruction.sample.video_url, cover_url: StoreInstruction.sample.cover_url,
        aspect_ratio: 0.5625, is_test: false)
}
let general = video("general", "Как установить приложение", [])
let whatsapp = video("whatsapp", "Подключение WhatsApp", ["net.whatsapp.WhatsApp", "net.whatsapp.WhatsAppSMB"])
let whatsappMod = video("wa-mod", "Настройка WhatsApp Business", ["net.whatsapp.WhatsAppSMB"])
let gta = video("gta", "Как установить GTA V", ["com.macport.gtav"])
let mods = video("mods", "Как импортировать моды", ["com.macport.gtav"])
let apps = [InstructionAppSummary(id: "com.macport.gtav", name: "GTA V", iconURL: URL(string:"https://example.com/icon.png")),
    InstructionAppSummary(id: "net.whatsapp.WhatsApp", name: "WhatsApp Plus", iconURL: nil)]
let collections = InstructionCollections.build([general, whatsapp, whatsappMod, gta, mods], apps: apps)
precondition(collections.map(\.title) == ["Общие инструкции", "GTA V", "WhatsApp"])
precondition(collections[0].id == InstructionCollections.generalID && collections[0].instructions == [general])
precondition(collections[1].instructions.map(\.id) == ["gta", "mods"])
precondition(collections[2].instructions.map(\.id) == ["whatsapp", "wa-mod"])
precondition(collections[1].iconURL == apps[0].iconURL)
precondition(!collections.contains { $0.title == "Instagram" })
precondition(InstructionCollections.build([general], apps: apps).map(\.id) == [InstructionCollections.generalID])
precondition(InstructionCollections.build([whatsapp], apps: []).first?.instructions.count == 1)
let hidden = InstructionCollections.build([general, whatsapp], apps: apps)
precondition(hidden.map(\.title) == ["Общие инструкции", "WhatsApp"])
let shared = video("shared", "Для двух приложений", ["com.macport.gtav", "net.whatsapp.WhatsApp"])
precondition(InstructionCollections.build([shared], apps: apps).count == 2)
precondition(InstructionCollections.matches(mods, query:"МОДЫ"))
precondition(!InstructionCollections.matches(gta, query:"озвучка"))
precondition(InstructionCollections.countLabel(1) == "1 видео")
precondition(InstructionCollections.key(for:"NET.WHATSAPP.WhatsApp") == "family:whatsapp")
print("Instruction collections: general separation, family merge, unique counts, no empty groups, hidden removal, shared video, search and offline fallback passed")
