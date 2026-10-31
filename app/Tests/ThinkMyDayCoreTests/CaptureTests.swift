import CoreGraphics
import Foundation
import Testing
@testable import ThinkMyDayCore

private let window = CGRect(x: 0, y: 0, width: 1000, height: 800)

private func text(_ value: String, _ frame: CGRect? = CGRect(x: 10, y: 10, width: 600, height: 40)) -> ElementSnapshot {
    ElementSnapshot(role: "AXStaticText", value: value, frame: frame)
}

private func group(_ children: [ElementSnapshot], role: String = "AXGroup", frame: CGRect? = nil) -> ElementSnapshot {
    ElementSnapshot(role: role, frame: frame, children: children)
}

@Suite struct VisibleTextTests {
    @Test func readsTextInReadingOrder() {
        let tree = group([text("第一行\n第二行"), group([text("third")])])
        #expect(VisibleText.extract(tree, windowFrame: window).lines == ["第一行", "第二行", "third"])
    }

    /// Rule 1: Chromium reports a near-empty AXVisibleCharacterRange on static text; it must not hide the text.
    @Test func ignoresVisibleRangeOnStaticText() {
        var el = text("Chromium static text that is fully visible")
        el.visibleRange = NSRange(location: 0, length: 1)
        let out = VisibleText.extract(group([el]), windowFrame: window)
        #expect(out.lines == ["Chromium static text that is fully visible"])
    }

    @Test func visibleRangeTrimsEditableText() {
        let el = ElementSnapshot(role: "AXTextArea", value: "line one\nline two\nline three",
                                 frame: CGRect(x: 0, y: 0, width: 500, height: 300), visibleRange: NSRange(location: 9, length: 8))
        #expect(VisibleText.extract(group([el]), windowFrame: window).lines == ["line two"])
    }

    /// Rule 2: a link titled with its children's text is read once, from the children.
    @Test func titleOnlyOnLeaves() {
        let link = ElementSnapshot(role: "AXLink", title: "Open settings", frame: CGRect(x: 0, y: 0, width: 200, height: 20),
                                   children: [text("Open settings", CGRect(x: 0, y: 0, width: 200, height: 20))])
        let button = ElementSnapshot(role: "AXButton", title: "Send", frame: CGRect(x: 0, y: 30, width: 60, height: 20))
        #expect(VisibleText.extract(group([link, button]), windowFrame: window).lines == ["Open settings", "Send"])
    }

    /// Rule 3: scrolled-out text squashed to a 1 pt strip, or outside its scroll pane, is not visible.
    @Test func dropsSquashedAndClippedText() {
        let pane = group([
            text("on screen", CGRect(x: 0, y: 100, width: 400, height: 20)),
            text("squashed at the edge", CGRect(x: 0, y: 99, width: 400, height: 1)),
            text("below the pane", CGRect(x: 0, y: 400, width: 400, height: 20)),
        ], role: "AXScrollArea", frame: CGRect(x: 0, y: 100, width: 500, height: 200))
        let outside = text("outside the window", CGRect(x: 0, y: 900, width: 400, height: 20))
        #expect(VisibleText.extract(group([pane, outside]), windowFrame: window).lines == ["on screen"])
    }

    /// Rule 4: a one-line label keeps its full text, but only what fits counts as visible.
    @Test func ellipsisLabelKeepsFullText() {
        let full = String(repeating: "预览", count: 300)
        let label = ElementSnapshot(role: "AXButton", title: full, frame: CGRect(x: 0, y: 0, width: 600, height: 28))
        let out = VisibleText.extract(group([label]), windowFrame: window)
        #expect(out.lines == [full])
        #expect(out.chars == 600)
        #expect(out.visibleChars == 200) // 600 pt / 6 pt × 2 lines of 14 pt
    }

    @Test func neverReadsPasswordFields() {
        let secure = ElementSnapshot(role: "AXTextField", subrole: "AXSecureTextField", value: "hunter2",
                                     frame: CGRect(x: 0, y: 0, width: 200, height: 20), children: [text("inside")])
        let secureRole = ElementSnapshot(role: "AXSecureTextField", value: "hunter3", frame: CGRect(x: 0, y: 30, width: 200, height: 20))
        let out = VisibleText.extract(group([secure, secureRole, text("visible")]), windowFrame: window)
        #expect(out.lines == ["visible"])
    }

    @Test func elementsWithoutFrameCount() {
        #expect(VisibleText.extract(group([text("no frame", nil)]), windowFrame: window).lines == ["no frame"])
    }
}

@Suite struct CaptureRuleTests {
    @Test func lineHistoryStoresOnlyNewLines() {
        var history = LineHistory()
        do { let r = history.added(window: 1, lines: ["a", "b", "a"]); #expect(r == ["a", "b"]) }
        do { let r = history.added(window: 1, lines: ["b", "a"]); #expect(r == nil) }
        do { let r = history.added(window: 1, lines: ["a", "b", "c"]); #expect(r == ["c"]) }
        do { let r = history.added(window: 1, lines: ["a"]); #expect(r == []) }
        do { let r = history.added(window: 2, lines: ["a"]); #expect(r == ["a"]) }
    }

    @Test func partialReadsDoNotRepeatLines() {
        var history = LineHistory()
        _ = history.added(window: 1, lines: ["a", "b", "c"])
        do { let r = history.added(window: 1, lines: ["a"], partial: true); #expect(r == nil || r == []) }
        do { let r = history.added(window: 1, lines: ["a", "b", "c"]); #expect(r == nil) }
        do { let r = history.added(window: 1, lines: ["a", "d"], partial: true); #expect(r == ["d"]) }
    }

    @Test func urlLosesQueryAndFragment() {
        #expect(URLCleaner.clean("https://example.com/a/b?token=secret&x=1#access_token=abc") == "https://example.com/a/b")
        #expect(URLCleaner.clean("https://example.com/") == "https://example.com/")
        #expect(URLCleaner.clean("chrome://newtab/") == "chrome://newtab/")
        #expect(URLCleaner.clean("not a url?with=query") == "not a url")
    }

    @Test func ocrBudgetLimitsPerWindowAndOverall() {
        var budget = OCRBudget(perWindow: 30, global: 5)
        let t = Date(timeIntervalSince1970: 0)
        do { let r = budget.take(window: 1, now: t); #expect(r) }
        do { let r = budget.take(window: 2, now: t.addingTimeInterval(4)); #expect(!r) }
        do { let r = budget.take(window: 2, now: t.addingTimeInterval(5)); #expect(r) }
        do { let r = budget.take(window: 1, now: t.addingTimeInterval(29)); #expect(!r) }
        do { let r = budget.take(window: 1, now: t.addingTimeInterval(30)); #expect(r) }
    }

    @Test func idleIsDatedFromTheLastInput() {
        var tracker = IdleTracker(threshold: 180)
        let t = Date(timeIntervalSince1970: 1000)
        do { let r = tracker.update(secondsSinceInput: 60, now: t); #expect(r == nil) }
        do { let r = tracker.update(secondsSinceInput: 200, now: t); #expect(r == Presence(state: .idle, since: t.addingTimeInterval(-200))) }
        do { let r = tracker.update(secondsSinceInput: 400, now: t); #expect(r == nil) }
        do { let r = tracker.update(secondsSinceInput: 1, now: t); #expect(r == Presence(state: .active, since: t)) }
    }

    @Test func recordBodiesRoundTrip() throws {
        let body = WindowText(windowID: 7, bundleID: "com.google.Chrome", appName: "Chrome", title: "Docs", focused: true,
                              method: .accessibility, url: "https://example.com/", added: ["新的一行"], lineCount: 3,
                              visibleChars: 120, truncated: false)
        let record = try Record(dayID: UUID(), at: Date(), kind: .windowText, body: body)
        #expect(record.kind == "windowText")
        #expect(try record.decode(WindowText.self) == body)
    }
}

@Suite struct PrivacyRuleTests {
    let list = BlockList(apps: [BlockList.App(bundleID: "cmb.pb", name: "招商银行")])

    @Test func blockedAppsAreNotRead() {
        #expect(PrivacyRules.decide(bundleID: "cmb.pb", browserURL: nil, incognito: false, blockList: list) == .blocked)
        #expect(PrivacyRules.decide(bundleID: "com.apple.Notes", browserURL: nil, incognito: false, blockList: list) == .read)
    }

    @Test func incognitoIsNeverRead() {
        #expect(PrivacyRules.decide(bundleID: "com.google.Chrome", browserURL: "https://example.com/", incognito: true, blockList: list) == .neverRead)
    }

    @Test func walletAndPasswordExtensionPagesAreNeverRead() {
        let metaMask = "chrome-extension://nkbihfbeogaeaoehlefnkodbefgpgknn/home.html#unlock"
        let bitwarden = "chrome-extension://nngceckbapebfimnlniiiahkandclblb/popup/index.html"
        for url in [metaMask, bitwarden, "moz-extension://abc/popup.html"] {
            #expect(PrivacyRules.decide(bundleID: "com.google.Chrome", browserURL: url, incognito: false, blockList: list) == .neverRead)
        }
        #expect(PrivacyRules.decide(bundleID: "com.google.Chrome", browserURL: "https://metamask.io/", incognito: false, blockList: list) == .read)
    }

    @Test func neverReadCannotBeOverriddenByAnEmptyList() {
        #expect(PrivacyRules.decide(bundleID: "com.google.Chrome", browserURL: nil, incognito: true, blockList: BlockList(apps: [])) == .neverRead)
    }

    @Test func listEdits() {
        var list = BlockList.presets
        #expect(list.contains("com.1password.1password"))
        list.remove("com.1password.1password")
        #expect(!list.contains("com.1password.1password"))
        list.add(BlockList.App(bundleID: "com.tencent.xinWeChat", name: "微信"))
        list.add(BlockList.App(bundleID: "com.tencent.xinWeChat", name: "微信"))
        #expect(list.apps.filter { $0.bundleID == "com.tencent.xinWeChat" }.count == 1)
    }

    @Test func hiddenFocusKeepsTheAppButNoTitle() throws {
        let record = try Record(dayID: UUID(), at: Date(), kind: .focus,
                                body: Focus.hidden(windowID: 9, reason: .blocked, bundleID: "cmb.pb", appName: "招商银行"))
        let focus = try record.decode(Focus.self)
        #expect(focus.hidden == .blocked && focus.appName == "招商银行" && focus.title == nil)
    }
}

@Suite struct LayoutTests {
    let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: -200, width: 2560, height: 1440)]

    private func window(_ id: UInt32, _ frame: CGRect, visible: Double = 1) -> Layout.Window {
        Layout.Window(windowID: id, bundleID: "app.\(id)", appName: "App \(id)", frame: frame,
                      screen: Layout.screen(for: frame, in: screens), visible: visible, focused: id == 1)
    }

    @Test func sideBySideWindowsOnTwoScreens() {
        let left = window(1, CGRect(x: 0, y: 30, width: 756, height: 950))
        let right = window(2, CGRect(x: 756, y: 30, width: 756, height: 950))
        let external = window(3, CGRect(x: 1600, y: 0, width: 1200, height: 900))
        #expect([left, right, external].map(\.screen) == [0, 0, 1])
        #expect(Layout.screen(for: CGRect(x: -2000, y: 0, width: 100, height: 100), in: screens) == -1)
    }

    @Test func recordsOnlyRealChanges() {
        let tracker = TrackerBox()
        let a = window(1, CGRect(x: 0, y: 30, width: 756, height: 950)), b = window(2, CGRect(x: 756, y: 30, width: 756, height: 950))
        #expect(tracker.changed(Layout(screens: screens, windows: [a, b])))
        #expect(!tracker.changed(Layout(screens: screens, windows: [a, b])))

        var nudged = a
        nudged.frame.origin.x += 3
        nudged.visible = 0.9
        #expect(!tracker.changed(Layout(screens: screens, windows: [nudged, b])), "small moves and visibility wobble are ignored")

        var refocused = a
        refocused.focused = false
        #expect(!tracker.changed(Layout(screens: screens, windows: [refocused, b])), "focus has its own records")

        #expect(tracker.changed(Layout(screens: screens, windows: [b, a])), "stacking order changed")
        var moved = b
        moved.frame.origin.x = 1700
        moved.screen = 1
        #expect(tracker.changed(Layout(screens: screens, windows: [moved, a])), "moved to the other screen")
        #expect(tracker.changed(Layout(screens: [screens[0]], windows: [moved, a])), "a screen was unplugged")
    }

    @Test func hiddenWindowKeepsFrameButNotApp() throws {
        let hidden = Layout.Window(windowID: 5, bundleID: "", appName: "", frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                                   screen: 0, visible: 1, focused: false, hidden: .blocked)
        let record = try Record(dayID: UUID(), at: Date(), kind: .layout, body: Layout(screens: screens, windows: [hidden]))
        #expect(try record.decode(Layout.self).windows.first?.hidden == .blocked)
    }
}

/// Lets #expect call the mutating tracker.
private final class TrackerBox {
    var tracker = LayoutTracker()
    func changed(_ layout: Layout) -> Bool { tracker.changed(layout) }
}

@Suite struct PlaceTests {
    let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)]

    @Test func sidesOnOneScreenAndAcrossTwo() {
        #expect(Place(frame: CGRect(x: 0, y: 30, width: 756, height: 950), screens: screens).label == "屏幕 1 左")
        #expect(Place(frame: CGRect(x: 756, y: 30, width: 756, height: 950), screens: screens).label == "屏幕 1 右")
        #expect(Place(frame: CGRect(x: 0, y: 30, width: 1512, height: 950), screens: screens).label == "屏幕 1 整屏")
        #expect(Place(frame: CGRect(x: 2400, y: 200, width: 800, height: 900), screens: screens).label == "屏幕 2 中")
        #expect(Place(frame: CGRect(x: -3000, y: 0, width: 400, height: 300), screens: screens).label == "屏幕外")
    }
}

@Suite struct ActivityTests {
    let t0 = Date(timeIntervalSince1970: 1_793_400_000)

    private func sample(_ id: UInt32, focused: Bool = false, typed: Int = 0, cleared: Int = 0, content: Int = 0, scrolls: Int = 0) -> ActivitySample {
        var s = ActivitySample(windowID: id, bundleID: "app.\(id)", appName: "App \(id)", place: nil)
        s.focused = focused
        s.typed = typed
        s.cleared = cleared
        s.contentAdded = content
        s.scrolls = scrolls
        return s
    }

    /// Type and send in ChatGPT, switch to Chrome while the reply arrives, come back and scroll, then sit still.
    @Test func typingWaitingReadingAndStillnessAreTellableApart() {
        let tracker = ActivityBox()
        var out: [Activity] = []
        out += tracker.add([sample(1, focused: true, typed: 80)], 5, t0.addingTimeInterval(5))
        out += tracker.add([sample(1, focused: true, typed: 40, cleared: 1)], 5, t0.addingTimeInterval(10))
        out += tracker.add([sample(1, content: 900), sample(2, focused: true, scrolls: 3)], 20, t0.addingTimeInterval(30))
        out += tracker.add([sample(1, focused: true, scrolls: 6)], 15, t0.addingTimeInterval(45))
        out += tracker.add([sample(1, focused: true)], 20, t0.addingTimeInterval(65))
        #expect(out.count == 2)
        let chat = out.first { $0.windowID == 1 }!, browser = out.first { $0.windowID == 2 }!
        #expect(chat.typedChars == 120 && chat.fieldCleared == 1)
        #expect(chat.contentAddedChars == 900, "the reply grew while focus was elsewhere")
        #expect(chat.focusedSeconds == 45 && chat.scrollSeconds == 15 && chat.stillSeconds == 20)
        #expect(browser.focusedSeconds == 20 && browser.scrollSeconds == 20 && browser.stillSeconds == 0)
        #expect(chat.from == t0 && chat.to == t0.addingTimeInterval(65))
    }

    @Test func emptyBucketsAreDropped() {
        let tracker = ActivityBox()
        #expect(tracker.add([sample(1)], 60, t0.addingTimeInterval(60)).isEmpty)
    }

    @Test func fieldLengthBecomesTypedDeletedCleared() {
        var f = FieldTracker()
        do { let r = f.update(window: 1, length: 0); #expect(r == (0, 0, 0)) }
        do { let r = f.update(window: 1, length: 12); #expect(r == (12, 0, 0)) }
        do { let r = f.update(window: 1, length: 9); #expect(r == (0, 3, 0)) }
        do { let r = f.update(window: 1, length: nil); #expect(r == (0, 0, 0)) }
        do { let r = f.update(window: 1, length: 0); #expect(r == (0, 9, 1)) }
        // Sent, then the field shows its placeholder instead of nothing.
        do { let r = f.update(window: 1, length: 40); #expect(r == (40, 0, 0)) }
        do { let r = f.update(window: 1, length: 6); #expect(r == (0, 34, 1)) }
        do { let r = f.update(window: 1, length: 3); #expect(r == (0, 3, 0)) }
    }

    @Test func filesAreRecordedWhenTheyAppear() {
        var h = OpenedFileHistory()
        do { let r = h.new(window: 1, files: [(.finderFolder, "/Users/a/Downloads"), (.finderSelection, "/Users/a/Downloads/a.png")]); #expect(r.count == 2) }
        do { let r = h.new(window: 1, files: [(.finderFolder, "/Users/a/Downloads"), (.finderSelection, "/Users/a/Downloads/a.png")]); #expect(r.isEmpty) }
        do { let r = h.new(window: 1, files: [(.finderFolder, "/Users/a/Downloads"), (.finderSelection, "/Users/a/Downloads/b.png")]); #expect(r.map(\.1) == ["/Users/a/Downloads/b.png"]) }
    }
}

private final class ActivityBox {
    var tracker = ActivityTracker(bucket: 60)
    func add(_ s: [ActivitySample], _ seconds: TimeInterval, _ now: Date) -> [Activity] { tracker.add(s, seconds: seconds, now: now) }
}

@Suite struct FocusedFieldTests {
    @Test func findsTheFocusedEditableField() {
        var field = ElementSnapshot(role: "AXTextArea", value: "你好，帮我看看")
        field.focused = true
        let tree = ElementSnapshot(role: "AXWindow", children: [
            ElementSnapshot(role: "AXGroup", children: [ElementSnapshot(role: "AXStaticText", value: "回复")]),
            ElementSnapshot(role: "AXGroup", children: [field]),
        ])
        #expect(tree.focusedFieldLength == 7)
        #expect(ElementSnapshot(role: "AXWindow", children: [ElementSnapshot(role: "AXTextArea", value: "x")]).focusedFieldLength == nil)
    }

    @Test func passwordFieldsDoNotCount() {
        var secure = ElementSnapshot(role: "AXTextField", subrole: "AXSecureTextField", value: "secret")
        secure.focused = true
        #expect(ElementSnapshot(role: "AXWindow", children: [secure]).focusedFieldLength == nil)
    }
}
