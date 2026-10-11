import XCTest

final class NativePlayerUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "ru.dzhabaapps.fizer.preview")
    func state() -> [String: Any] {
        let element = app.descendants(matching: .any).matching(identifier: "instruction-ui-state").firstMatch
        guard element.exists, let text = element.value as? String, let data = text.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }
    func wait(_ message: String, timeout: TimeInterval = 25, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline { if condition() { return }; Thread.sleep(forTimeInterval: 0.2) }
        XCTFail(message + "\n" + app.debugDescription)
    }
    func button(_ words: [String]) -> XCUIElement {
        let clauses = words.map { "label CONTAINS[c] '\($0)' OR identifier CONTAINS[c] '\($0)'" }
        return app.buttons.matching(NSPredicate(format: clauses.joined(separator: " OR "))).firstMatch
    }
    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func showControls() {
        // Tap video away from the centre transport controls and top corner buttons.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.3)).tap()
    }
    func freshControl(_ element: XCUIElement) -> XCUICoordinate {
        if !element.isHittable { showControls() }
        wait("System control missing") { element.exists && element.isHittable }
        let frame = element.frame
        // Resolve the accessibility element before restarting AVKit's short
        // auto-hide timer. XCTest's element.tap() otherwise performs several
        // fresh snapshots and can outlive the timer on a busy CI simulator.
        showControls()
        Thread.sleep(forTimeInterval: 0.4)
        showControls()
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }
    var transport: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label MATCHES[c] '^(Play|Pause|Play Button|Pause Button|Play/Pause|Воспроизвести|Пауза)$'")).firstMatch
    }
    func setPlaying(_ playing: Bool) {
        if ((state()["rate"] as? Double ?? 0) > 0) != playing { freshControl(transport).tap() }
        wait("Native play/pause failed") { ((self.state()["rate"] as? Double ?? 0) > 0) == playing }
    }
    func testSystemPlayer() {
        continueAfterFailure = false
        app.launchEnvironment["FIZER_PREVIEW_SCREEN"] = "instruction-detail"
        app.launch()
        let start = app.buttons["instruction-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        wait("Remote video did not start") { (self.state()["rate"] as? Double ?? 0) > 0 }
        let item = state()["item"] as? String
        let expand = button(["Full Screen", "FullScreen", "полный экран", "весь экран", "на весь экран", "полноэкран", "развернуть"])
        freshControl(expand).tap()
        wait("Native fullscreen did not present") { self.state()["fullscreen"] as? Bool == true }
        XCTAssertEqual(item, state()["item"] as? String)
        // The real sample lasts only 45 seconds. Pause using the native button
        // while discovering controls, so test setup cannot finish the video.
        setPlaying(false)
        print("NATIVE FULLSCREEN HIERARCHY\n" + app.debugDescription)
        let forward = button(["Forward", "вперед", "вперёд"])
        let backward = button(["Backward", "Rewind", "назад"])
        if !forward.isHittable { showControls() }
        let progress = app.sliders.allElementsBoundByIndex.first {
            !$0.label.localizedCaseInsensitiveContains("volume") && !$0.label.localizedCaseInsensitiveContains("громкост") &&
            !$0.label.localizedCaseInsensitiveContains("brightness") && !$0.label.localizedCaseInsensitiveContains("яркост")
        }
        XCTAssertNotNil(progress, "Native timeline missing\n" + app.debugDescription)
        guard let progress else { return }
        _ = freshControl(progress)
        progress.adjust(toNormalizedSliderPosition: 0.1)
        setPlaying(true)
        let forwardPoint = freshControl(forward)
        let before = state()["time"] as? Double ?? 0
        forwardPoint.tap()
        wait("Native forward skip failed") { (self.state()["time"] as? Double ?? 0) > before + 8 }
        let backwardPoint = freshControl(backward)
        let advanced = state()["time"] as? Double ?? 0
        backwardPoint.tap()
        wait("Native backward skip failed") { (self.state()["time"] as? Double ?? 100) < advanced - 7 }
        wait("Playback did not continue after native skip") { (self.state()["rate"] as? Double ?? 0) > 0 }
        setPlaying(false)
        _ = freshControl(progress)
        snapshot("DR-Store-native-fullscreen")
        setPlaying(true)
        _ = freshControl(progress)
        progress.adjust(toNormalizedSliderPosition: 0.5)
        wait("Native scrub did not resume") { (self.state()["rate"] as? Double ?? 0) > 0 && (self.state()["time"] as? Double ?? 0) > 15 }
        let scrubbed = state()["time"] as? Double ?? 0
        wait("Native timeline stopped advancing") { (self.state()["time"] as? Double ?? 0) > scrubbed + 0.8 }

        // Native controls should disappear and return without our own overlay.
        setPlaying(false)
        _ = freshControl(progress)
        progress.adjust(toNormalizedSliderPosition: 0.1)
        setPlaying(true)
        _ = freshControl(forward)
        showControls()
        wait("Native controls did not hide", timeout: 8) { !forward.isHittable }
        snapshot("DR-Store-native-controls-hidden")
        showControls()
        wait("Native controls did not return") { forward.isHittable }
        let close = button(["Done", "Close", "Готово", "Закрыть", "Exit Full Screen", "Выход из полноэкран", "Свернуть"])
        freshControl(close).tap()
        wait("Native fullscreen did not return inline") { self.state()["fullscreen"] as? Bool == false }
        XCTAssertEqual(item, state()["item"] as? String)
        wait("Returning inline stopped playback") { (self.state()["rate"] as? Double ?? 0) > 0 }
        snapshot("DR-Store-native-inline-return")
        // Re-enter/exit a second time to catch a released controller/item.
        freshControl(expand).tap()
        wait("Second fullscreen failed") { self.state()["fullscreen"] as? Bool == true }
        XCTAssertEqual(item, state()["item"] as? String)
        freshControl(close).tap()
        wait("Second return failed") { self.state()["fullscreen"] as? Bool == false }
        XCTAssertEqual(item, state()["item"] as? String)
    }
}
