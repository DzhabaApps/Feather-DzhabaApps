import XCTest

final class NativePlayerUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "ru.dzhabaapps.fizer.preview")
    typealias Match = (XCUIElementSnapshot) -> Bool
    func find(_ snapshot: XCUIElementSnapshot, _ match: Match) -> XCUIElementSnapshot? {
        if match(snapshot) { return snapshot }
        for child in snapshot.children { if let result = find(child, match) { return result } }
        return nil
    }
    func current(_ match: Match) -> XCUIElementSnapshot? {
        guard let snapshot = try? app.snapshot() else { return nil }
        return find(snapshot, match)
    }
    func state() -> [String: Any] {
        guard let element = current({ $0.identifier == "instruction-ui-state" }),
              let text = element.value as? String, let data = text.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }
    func wait(_ message: String, timeout: TimeInterval = 25, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline { if condition() { return }; Thread.sleep(forTimeInterval: 0.2) }
        XCTFail(message + "\n" + app.debugDescription)
    }
    func button(_ words: [String]) -> Match {
        { element in element.elementType == .button && words.contains {
            element.label.localizedCaseInsensitiveContains($0) || element.identifier.localizedCaseInsensitiveContains($0)
        } }
    }
    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func showControls() {
        // Tap video away from the centre transport controls and top corner buttons.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.3)).tap()
    }
    func freshFrame(_ match: Match) -> CGRect {
        // One immutable snapshot replaces exists/isHittable/frame queries that
        // each wait and re-resolve an element while AVKit is auto-hiding it.
        // Toggle once; if that hid the controls, toggle again to show them fresh.
        showControls()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let element = current(match), !element.frame.isEmpty { return element.frame }
            showControls()
            Thread.sleep(forTimeInterval: 0.15)
        }
        XCTFail("Native control missing\n" + app.debugDescription)
        return .zero
    }
    func freshControl(_ match: Match) -> XCUICoordinate {
        let frame = freshFrame(match)
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }
    var transport: Match {
        { element in element.elementType == .button && ["play", "pause", "play button", "pause button", "play/pause", "воспроизвести", "пауза"].contains(element.label.lowercased()) }
    }
    var timeline: Match {
        { element in element.elementType == .slider &&
            !["volume", "громкост", "brightness", "яркост"].contains(where: { element.label.localizedCaseInsensitiveContains($0) }) }
    }
    func seek(_ fraction: CGFloat) {
        _ = freshFrame(timeline)
        // This is XCTest's real native slider drag, not AVPlayer.seek().
        let progress = app.sliders.matching(NSPredicate(format: "NOT (label CONTAINS[c] 'volume' OR label CONTAINS[c] 'громкост' OR label CONTAINS[c] 'brightness' OR label CONTAINS[c] 'яркост')")).firstMatch
        progress.adjust(toNormalizedSliderPosition: fraction)
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
        seek(0.1)
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
        _ = freshFrame(timeline)
        snapshot("DR-Store-native-fullscreen")
        setPlaying(true)
        seek(0.5)
        wait("Native scrub did not resume") { (self.state()["rate"] as? Double ?? 0) > 0 && (self.state()["time"] as? Double ?? 0) > 15 }
        let scrubbed = state()["time"] as? Double ?? 0
        wait("Native timeline stopped advancing") { (self.state()["time"] as? Double ?? 0) > scrubbed + 0.8 }

        // Native controls should disappear and return without our own overlay.
        setPlaying(false)
        seek(0.1)
        setPlaying(true)
        _ = freshControl(forward)
        showControls()
        wait("Native controls did not hide", timeout: 8) { self.current(forward) == nil }
        snapshot("DR-Store-native-controls-hidden")
        showControls()
        wait("Native controls did not return") { self.current(forward) != nil }
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

    func testAppIcons() {
        continueAfterFailure = false
        app.launchEnvironment["FIZER_PREVIEW_SCREEN"] = "app-icons"
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for key in ["V2Mac", "V1", "primary"] {
            let row = app.buttons["app-icon-" + key]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.tap()
            wait("Icon confirmation did not appear") {
                self.app.alerts.firstMatch.exists || springboard.alerts.firstMatch.exists
            }
            let alert = app.alerts.firstMatch.exists ? app.alerts.firstMatch : springboard.alerts.firstMatch
            snapshot("DR-Store-icon-confirmation-" + key)
            let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            XCTAssertTrue(text.localizedCaseInsensitiveContains("знач"), "Icon confirmation is not Russian: " + text)
            alert.buttons.firstMatch.tap()
            wait("Selected icon checkmark is stale") { (row.value as? String) == "Выбран" }
            for other in ["V2Mac", "V1", "primary"] where other != key {
                XCTAssertEqual(app.buttons["app-icon-" + other].value as? String, "Не выбран")
            }
            snapshot("DR-Store-icon-selected-" + key)
            app.terminate()
            app.launch()
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            wait("Icon selection did not survive relaunch") { (row.value as? String) == "Выбран" }
        }
    }
}
