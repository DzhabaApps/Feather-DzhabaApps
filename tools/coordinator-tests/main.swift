// Exercise the production coordinator with a real in-memory Core Data store.
// UI, certificate reader and signer are adapters; no real signing keys are used.
import Foundation
import CoreData

final class FeatherAccessManager {
    static let shared = FeatherAccessManager()
    var allowed = true
    func permitsAccess() -> Bool { allowed }
}

protocol AppInfoPresentable {
	var source: URL? { get }
	var name: String? { get }
	var identifier: String? { get }
	var uuid: String? { get }
	var isSigned: Bool { get }
}

final class TestApp: NSManagedObject, AppInfoPresentable {
	@NSManaged var source: URL?
	@NSManaged var name: String?
	@NSManaged var identifier: String?
	@NSManaged var uuid: String?
	@NSManaged var date: Date?
	var isSigned: Bool { entity.name == "Signed" }
}
typealias Signed = TestApp
struct AnyApp: Identifiable {
	let base: AppInfoPresentable
	var id: String { base.uuid! }
}
final class CertificatePair {
	var revoked = false
	var expiration: Date? = .now.addingTimeInterval(3600)
	var ppQCheck = false
}
struct Options {
	enum SigningOption { case `default`, onlyModify }
	var signingOption: SigningOption = .default
	var ppqProtection = false
	var ppqString = "test"
	var appIdentifier: String?
	var appName: String?
	var identifiers: [String: String] = [:]
	var displayNames: [String: String] = [:]
	var post_deleteAppAfterSigned = true
}
final class OptionsManager {
	static let shared = OptionsManager()
	var options = Options()
}
final class Storage {
	static let shared = Storage()
	let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	var certificate: CertificatePair?
	var signedCertificate: CertificatePair?
	init() {
		let model = NSManagedObjectModel()
		model.entities = ["Imported", "Signed"].map { name in
			let entity = NSEntityDescription()
			entity.name = name
			entity.managedObjectClassName = NSStringFromClass(TestApp.self)
			entity.properties = [("source", NSAttributeType.URIAttributeType), ("date", .dateAttributeType), ("uuid", .stringAttributeType), ("name", .stringAttributeType), ("identifier", .stringAttributeType)].map { name, type in
				let attribute = NSAttributeDescription()
				attribute.name = name; attribute.attributeType = type; attribute.isOptional = true
				return attribute
			}
			return entity
		}
		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		try! coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
		context.persistentStoreCoordinator = coordinator
		try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	}
	func getAppDirectory(for app: AppInfoPresentable) -> URL? { app.uuid.map { root.appendingPathComponent($0) } }
	func deleteApp(for app: AppInfoPresentable) { context.delete(app as! NSManagedObject); try! context.save() }
	func getCertificate(for index: Int) -> CertificatePair? { certificate }
	func getCertificate(from app: AppInfoPresentable) -> CertificatePair? { signedCertificate ?? certificate }
	func makeApp(_ entity: String, source: URL, date: Date = .now, hasFiles: Bool = true) -> TestApp {
		let app = NSEntityDescription.insertNewObject(forEntityName: entity, into: context) as! TestApp
		app.uuid = UUID().uuidString; app.source = source; app.name = "Example"; app.identifier = "example.app"; app.date = date
		if hasFiles { try! FileManager.default.createDirectory(at: getAppDirectory(for: app)!, withIntermediateDirectories: true) }
		try! context.save()
		return app
	}
}
enum FR {
	static var pending: ((Error?, Signed?) -> Void)?
	static var calls = 0
	static var lastOptions: Options?
	static var lastApp: AppInfoPresentable?
	static func signPackageFile(_ app: AppInfoPresentable, using options: Options, icon: Any?, certificate: CertificatePair?, completion: @escaping (Error?, Signed?) -> Void) {
		calls += 1; pending = completion; lastOptions = options; lastApp = app
	}
}
enum UIAlertController {
	static var messages: [String] = []
	static func showAlertWithOk(title: String, message: String) { messages.append(message) }
}
extension String { static func localized(_ key: String) -> String { key } }
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }

let store = Storage.shared
defer { try? FileManager.default.removeItem(at: store.root) }
let copies = AppCopyStore(fileURL: store.root.appendingPathComponent("copies.json"))
let installer = RepositoryInstallCoordinator(copies: copies)
let source = RepositoryFileIdentity.sourceURL(downloadURL: URL(string: "https://example.com/a.ipa")!, version: "1")
let otherSource = RepositoryFileIdentity.sourceURL(downloadURL: URL(string: "https://example.com/b.ipa")!, version: "1")
let original = store.makeApp("Imported", source: source)
let originalID = original.uuid!
let unrelated = store.makeApp("Imported", source: otherSource)
check(installer.libraryApp(for: source)?.uuid == originalID, "Repository must resolve its own file")
let orphan = store.makeApp("Imported", source: source, date: .now.addingTimeInterval(100), hasFiles: false)
check(installer.libraryApp(for: source)?.uuid == originalID, "Missing file must not hide a valid previous import")
store.context.reset()
let reloaded = installer.libraryApp(for: source)!
check(reloaded.uuid == originalID, "Saved repository identity must survive a context reload")
installer.install(reloaded)
check(FR.calls == 0 && !installer.isBusy, "Missing certificate must block signing")
store.certificate = CertificatePair()
installer.install(reloaded)
check(installer.isBusy && FR.calls == 1, "Valid certificate starts signing")
installer.install(reloaded)
check(FR.calls == 1, "Double tap must not start a duplicate signer")
FR.pending!(NSError(domain: "test", code: 1), nil)
check(!installer.isBusy && installer.libraryApp(for: source)?.uuid == originalID, "Signing failure must preserve the import for retry")
installer.install(installer.libraryApp(for: source)!)
let signed = store.makeApp("Signed", source: source)
let unrelatedSigned = store.makeApp("Signed", source: otherSource, date: .now.addingTimeInterval(200))
FR.pending!(nil, signed)
check(installer.installApp?.base.uuid == signed.uuid && installer.installApp?.base.uuid != unrelatedSigned.uuid, "Install must use the exact signer result, not the newest library item")
check(installer.libraryApp(for: source)?.isSigned == true, "Cleanup must retain the signed file for install retry")
installer.installApp = nil
store.certificate!.revoked = true
installer.install(signed)
check(installer.installApp == nil, "Revoked signed certificate must block a new installation")
store.certificate!.revoked = false
store.certificate!.expiration = .now.addingTimeInterval(-1)
installer.install(signed)
check(installer.installApp == nil, "Expired signed certificate must block a new installation")
store.signedCertificate = store.certificate
store.certificate = CertificatePair()
let previousCalls = FR.calls
installer.install(signed)
check(FR.calls == previousCalls + 1 && installer.isBusy, "A replacement certificate must allow re-signing the retained file")
let replacement = store.makeApp("Signed", source: source)
FR.pending!(nil, replacement)
check(installer.installApp?.base.uuid == replacement.uuid, "Certificate replacement must install the new signed result")
print("Repository coordinator: 13 checks passed")

installer.installApp = nil
store.signedCertificate = store.certificate
let copySource = RepositoryFileIdentity.sourceURL(downloadURL: URL(string: "https://example.com/copy-v1.ipa")!, version: "1")
let copyOriginal = store.makeApp("Imported", source: copySource)
let copyOne = try copies.create(originalIdentifier: "example.app", name: "Рабочий")
let copyTwo = try copies.create(originalIdentifier: "example.app", name: "Личный")
OptionsManager.shared.options.ppqProtection = true
store.certificate!.ppQCheck = true
OptionsManager.shared.options.identifiers = ["example.app": "legacy.replacement"]
OptionsManager.shared.options.displayNames = ["Example": "Legacy name"]
let beforeChoice = FR.calls
installer.chooseInstallation(copyOriginal)
check(installer.isBusy && FR.calls == beforeChoice, "Choice must not start a signer")
let choice = installer.installRequest!
installer.chooseInstallation(copyOriginal)
check(installer.installRequest?.id == choice.id, "Repeated taps must not replace the choice")
installer.selectInstallation(choice, copy: copyOne)
check(FR.calls == beforeChoice && installer.isBusy, "Wait for sheet dismissal before signing")
installer.finishInstallationChoice()
check(FR.calls == beforeChoice + 1 && FR.lastOptions?.appIdentifier == copyOne.identifier && FR.lastOptions?.appName == copyOne.name, "Saved identity overrides PPQ and global dictionaries")
installer.finishInstallationChoice()
check(FR.calls == beforeChoice + 1, "Dismissal callback must not duplicate signing")
FR.pending!(NSError(domain: "test", code: 1), nil)
let savedAfterFailure = try copies.copies(for: "example.app")
check(savedAfterFailure.contains(copyOne), "Signing failure keeps identity for a retry")
installer.install(copyOriginal, copy: copyOne)
let signedCopy = store.makeApp("Signed", source: copySource)
signedCopy.identifier = copyOne.identifier; signedCopy.name = copyOne.name
try store.context.save()
FR.pending!(nil, signedCopy)
check(installer.installApp?.base.uuid == signedCopy.uuid && !copyOriginal.isDeleted, "Copy signing installs exact result and retains common original")
check(installer.libraryApp(for: copySource)?.uuid == copyOriginal.uuid, "Catalog must select original, never a prepared clone")
installer.installApp = nil
let callsBeforeRetry = FR.calls
installer.install(signedCopy, copy: copyOne)
check(FR.calls == callsBeforeRetry && installer.installApp?.base.uuid == signedCopy.uuid, "Same prepared copy can retry installation without signing")
installer.installApp = nil
installer.install(signedCopy, copy: copyTwo)
check(FR.calls == callsBeforeRetry + 1 && FR.lastApp?.uuid == copyOriginal.uuid && FR.lastOptions?.appIdentifier == copyTwo.identifier, "Different copy must be prepared from the common original")
let wrongResult = store.makeApp("Signed", source: copySource)
FR.pending!(nil, wrongResult)
check(installer.installApp == nil && wrongResult.managedObjectContext == nil && copyOriginal.managedObjectContext != nil, "Wrong signer identity must never install or destroy the source")

let newSource = RepositoryFileIdentity.sourceURL(downloadURL: URL(string: "https://example.com/copy-v2.ipa")!, version: "2")
let newOriginal = store.makeApp("Imported", source: newSource)
installer.install(newOriginal, copy: copyOne)
check(FR.lastApp?.uuid == newOriginal.uuid && FR.lastOptions?.appIdentifier == copyOne.identifier && FR.lastOptions?.appName == copyOne.name, "New catalog version updates the same copy with its permanent identity")
let updated = store.makeApp("Signed", source: newSource)
updated.identifier = copyOne.identifier; updated.name = copyOne.name
try store.context.save()
FR.pending!(nil, updated)
installer.installApp = nil
try copies.forget(copyOne)
let beforeForgotten = FR.calls
installer.install(newOriginal, copy: copyOne)
check(FR.calls == beforeForgotten && !installer.isBusy, "Stale selection of a forgotten copy must fail")
let anotherApp = store.makeApp("Imported", source: otherSource)
anotherApp.identifier = "other.application"
installer.install(anotherApp, copy: copyTwo)
check(FR.calls == beforeForgotten, "A copy cannot be applied to a different original app")
store.context.delete(copyOriginal); try store.context.save()
check(installer.libraryApp(for: copySource) == nil, "A clone alone must not suppress redownloading its source")
installer.install(signedCopy)
check(installer.installApp == nil && FR.calls == beforeForgotten, "Ordinary install must never silently use a clone when its original is missing")
FeatherAccessManager.shared.allowed = false
installer.chooseInstallation(newOriginal)
check(installer.installRequest == nil && !installer.isBusy, "Subscription gate also protects copy choices")
FeatherAccessManager.shared.allowed = true
installer.chooseInstallation(newOriginal)
installer.installRequest = nil
installer.finishInstallationChoice()
check(!installer.isBusy && FR.calls == beforeForgotten, "Cancel choice must not install anything")
print("Copy coordinator: 18 checks passed")
