import SwiftUI
import NimbleViews

struct AboutView: View {
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack(spacing: 8) {
					FRAppIconView(size: 72)
					Text("Физер").font(.largeTitle.bold())
					Text(verbatim: .localized("Version %@", arguments: Bundle.main.version)).foregroundStyle(.secondary)
				}.frame(maxWidth: .infinity)
			}
			NBSection(.localized("Credits")) {
				LabeledContent("Feather", value: "Samara / claration, Asami")
				LabeledContent("AltSourceKit", value: "Lakhan Lothiyi")
				LabeledContent(.localized("Russian interface"), value: "DzhabaApps")
			}
			NBSection(.localized("Licenses")) {
				Text(.localized("Feather license explanation"))
				Link(.localized("Source code and license"), destination: URL(string: "https://github.com/DzhabaApps/Feather-DzhabaApps/tree/codex/fizer-russian-preview")!)
				NavigationLink(.localized("License text")) {
					ScrollView { Text(licenseText).font(.caption.monospaced()).padding().textSelection(.enabled) }
						.navigationTitle(.localized("License text"))
				}
			}
		}
	}
	private var licenseText: String {
		guard let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt") else { return "GPL-3.0" }
		return (try? String(contentsOf: url, encoding: .utf8)) ?? "GPL-3.0"
	}
}
