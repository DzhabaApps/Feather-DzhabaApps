//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
	case sources
	case library
	case instructions
	case settings
	
	var title: String {
		switch self {
		case .sources:     	return "Каталог"
		case .library: 		return .localized("Library")
		case .instructions: return "Инструкции"
		case .settings: 	return .localized("Settings")
		}
	}
	
	var icon: String {
		switch self {
		case .sources: 		return "bag"
		case .library: 		return "square.grid.2x2"
		case .instructions: return "play.rectangle"
		case .settings: 	return "gearshape.2"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .sources: SourcesView()
		case .library: LibraryView()
		case .instructions: InstructionsView()
		case .settings: SettingsView()
		}
	}
	
	static var defaultTabs: [TabEnum] {
		return [
			.sources,
			.library,
			.instructions,
			.settings
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return []
	}
}
