//
//  AppIconView.swift
//  Feather
//
//  Created by samara on 19.06.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View extension: Model
extension AppIconView {
	@MainActor
	struct AltIcon: Identifiable {
		var displayName: String
		var author: String
		var key: String?
		var image: UIImage
		var id: String { key ?? displayName }
		
		init(displayName: String, author: String, key: String? = nil) {
			self.displayName = displayName
			self.author = author
			self.key = key
			self.image = altImage(key)
		}
	}
	
	static func altImage(_ name: String?) -> UIImage {
		let path = Bundle.main.bundleURL.appendingPathComponent((name ?? "AppIcon60x60") + "@2x.png")
		return UIImage(contentsOfFile: path.path) ?? UIImage()
	}
}

// MARK: - View
@MainActor
struct AppIconView: View {
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var selection = AppIconSelection(
		readIcon: { UIApplication.shared.alternateIconName },
		changeIcon: { key, completion in UIApplication.shared.setAlternateIconName(key, completionHandler: completion) }
	)
	
	// dont translate
	var sections: [String: [AltIcon]] = [
		"Основные": [
			AltIcon(displayName: "DR Store", author: "Основной значок", key: nil),
			AltIcon(displayName: "DR Store · тёмный", author: "Тёмный значок", key: "V2Mac"),
			AltIcon(displayName: "DR Store · светлый", author: "Светлый значок", key: "V1"),
		]
	]
	
	// MARK: Body
	var body: some View {
		NBList(.localized("App Icon")) {
			ForEach(sections.keys.sorted(), id: \.self) { section in
				if let icons = sections[section] {
					NBSection(section) {
						ForEach(icons) { icon in
							_icon(icon: icon)
						}
					}
				}
			}
		}
		.onAppear {
			selection.refresh()
		}
		.onChange(of: scenePhase) { phase in
			if phase == .active { selection.refresh() }
		}
		.alert("Не удалось изменить значок", isPresented: $selection.showError) {
			Button("Понятно", role: .cancel) {}
		} message: {
			Text("Попробуйте ещё раз. Если проблема повторится, обратитесь в поддержку.")
		}
	}
}

// MARK: - View extension
extension AppIconView {
	@ViewBuilder
	private func _icon(
		icon: AppIconView.AltIcon
	) -> some View {
		Button {
			selection.select(icon.key)
		} label: {
			HStack(spacing: 18) {
				Image(uiImage: icon.image)
					.appIconStyle()
				
				NBTitleWithSubtitleView(
					title: icon.displayName,
					subtitle: icon.author,
					linelimit: 0
				)
				
				if selection.currentIcon == icon.key {
					Image(systemName: "checkmark").bold()
						.accessibilityHidden(true)
				}
			}
		}
		.disabled(selection.isChanging)
		.accessibilityIdentifier("app-icon-" + (icon.key ?? "primary"))
		.accessibilityValue(selection.currentIcon == icon.key ? "Выбран" : "Не выбран")
	}
}
