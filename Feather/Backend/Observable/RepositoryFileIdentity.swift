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

// The unsigned source and its prepared file are one library item. A different
// version, source archive or copy bundle identifier remains a separate item.
struct LibraryAppIdentity: Hashable {
    let identifier: String
    let version: String
    let source: URL?

    init(identifier: String?, version: String?, source: URL?, uuid: String) {
        self.identifier = identifier?.isEmpty == false ? identifier! : "local:" + uuid
        self.version = version ?? ""
        self.source = source
    }
}
