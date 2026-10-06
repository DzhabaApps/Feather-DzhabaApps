import Foundation

enum RepositoryFileIdentity {
	// A repository may reuse the same download URL for a newer version.
	// Store URL + catalog version without changing the actual HTTP request.
	static func sourceURL(downloadURL: URL, version: String?) -> URL {
		var components = URLComponents()
		components.scheme = "fizer-source"
		components.host = "download"
		components.queryItems = [
			URLQueryItem(name: "url", value: downloadURL.absoluteString),
			URLQueryItem(name: "version", value: version ?? "")
		]
		return components.url!
	}
}
