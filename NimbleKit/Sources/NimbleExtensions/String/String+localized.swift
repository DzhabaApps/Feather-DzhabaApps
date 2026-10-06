//
//  String+localized.swift
//  NimbleKit
//
//  Created by samara on 20.03.2025.
//

import Foundation.NSString
import SwiftUI

extension String {
	private static var russianBundle: Bundle {
		guard let path = Bundle.main.path(forResource: "ru", ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
		return bundle
	}
	// from: https://github.com/NSAntoine/Antoine/blob/main/Antoine/Backend/Extensions/Foundation.swift#L43-L55
	// was given permission to use any code from antoine as I like - thank you Serena!~
	
	static public func localized(_ name: String) -> String {
		NSLocalizedString(name, bundle: russianBundle, comment: "")
	}
	
	static public func localized(_ name: String, arguments: CVarArg...) -> String {
		String(format: NSLocalizedString(name, bundle: russianBundle, comment: ""), locale: Locale(identifier: "ru"), arguments: arguments)
	}
	/// Localizes the current string using the main bundle.
	///
	/// - Returns: The localized string.
	public func localized() -> String {
		String.localized(self)
	}
}

extension LocalizedStringKey {
	static public func localized(_ key: String) -> LocalizedStringKey {
		LocalizedStringKey(String.localized(key))
	}
}
