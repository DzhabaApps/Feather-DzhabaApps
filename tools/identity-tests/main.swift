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
print("Repository identity: 5 checks passed")
