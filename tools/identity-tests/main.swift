import Foundation

func check(_ condition: @autoclosure () -> Bool, _ description: String) {
	guard condition() else { fatalError(description) }
}

let url = URL(string: "https://example.com/app.ipa?token=a%26b#download")!
let first = RepositoryFileIdentity.sourceURL(downloadURL: url, version: "1.0")
let second = RepositoryFileIdentity.sourceURL(downloadURL: url, version: "2.0")
check(first != second, "A new catalog version must not reuse an old downloaded file")
check(first == RepositoryFileIdentity.sourceURL(downloadURL: url, version: "1.0"), "Identity must survive restart")
let components = URLComponents(url: first, resolvingAgainstBaseURL: false)!
check(components.queryItems!.first { $0.name == "url" }!.value == url.absoluteString, "URL queries and fragments must not be lost")
check(first != RepositoryFileIdentity.sourceURL(downloadURL: URL(string: "https://other.example/app.ipa")!, version: "1.0"), "Different source files must not collide")
check(RepositoryFileIdentity.sourceURL(downloadURL: url, version: nil).scheme == "fizer-source", "Missing versions must produce a valid persistent URI")
let ipaURL = URL(string: "https://example.com/com.hidden.youtube-20.1.ipa")!
check(DownloadPresentation.title(displayName: "YouTube Plus", url: ipaURL) == "YouTube Plus", "Show the catalog title, never the technical IPA filename")
check(DownloadPresentation.title(displayName: " WhatsApp 🟢 ", url: ipaURL) == "WhatsApp 🟢", "Preserve names and Unicode from the catalog")
check(DownloadPresentation.title(displayName: nil, url: URL(string: "https://example.com/WhatsApp.ipa")!) == "WhatsApp", "Manual file fallback excludes the IPA extension")
print("Repository identity and download names: 8 checks passed")

let libraryOriginal = LibraryAppIdentity(identifier: "test.app", version: "1", source: first, uuid: "download")
let libraryPrepared = LibraryAppIdentity(identifier: "test.app", version: "1", source: first, uuid: "prepared")
check(libraryOriginal == libraryPrepared, "A prepared file must share its downloaded library item")
check(libraryOriginal != LibraryAppIdentity(identifier: "test.app.copy1", version: "1", source: first, uuid: "copy"), "Copies must remain visible")
check(libraryOriginal != LibraryAppIdentity(identifier: "test.app", version: "2", source: first, uuid: "update"), "Different versions must remain visible")
check(libraryOriginal != LibraryAppIdentity(identifier: "test.app", version: "1", source: second, uuid: "other"), "Different IPA sources must remain visible")
check(LibraryAppIdentity(identifier: nil, version: nil, source: nil, uuid: "a") != LibraryAppIdentity(identifier: nil, version: nil, source: nil, uuid: "b"), "Unknown identifiers must not merge")
print("Unified library identity: originals and prepared files merged; copies, versions and sources preserved")
