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
