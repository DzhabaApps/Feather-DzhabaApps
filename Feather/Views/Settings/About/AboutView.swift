import SwiftUI
import NimbleViews

struct AboutView: View {
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack(spacing: 8) {
					FRAppIconView(size: 72)
					Text("DR Store").font(.largeTitle.bold())
					Text(verbatim: .localized("Version %@", arguments: Bundle.main.version)).foregroundStyle(.secondary)
				}.frame(maxWidth: .infinity)
			}
			Section {
				NavigationLink("Правовая информация") {
					List {
						Section("Открытый исходный код") {
							Text("DR Store создан на основе Feather и распространяется по лицензии GNU GPL версии 3.")
							Text(sourceURL).font(.footnote).textSelection(.enabled)
						}
						Section("Авторы компонентов") {
							LabeledContent("Feather", value: "Samara / claration, Asami")
							LabeledContent("AltSourceKit", value: "Lakhan Lothiyi")
						}
						Section("Лицензия") { Text(licenseText).font(.caption.monospaced()).textSelection(.enabled) }
					}.navigationTitle("Правовая информация").navigationBarTitleDisplayMode(.inline)
				}
			}
		}
	}
	private var sourceURL: String {
		let commit = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "codex/dr-store-design"
		return "https://github.com/DzhabaApps/Feather-DzhabaApps/tree/\(commit)"
	}
	private var licenseText: String {
		guard let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt") else { return "GPL-3.0" }
		return (try? String(contentsOf: url, encoding: .utf8)) ?? "GPL-3.0"
	}
}
