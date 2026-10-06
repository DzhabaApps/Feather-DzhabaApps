import Foundation

enum DownloadPresentation {
	static func title(displayName: String?, url: URL) -> String {
		let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
	}
}
