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

    @Test func hiddenFocusCarriesNoIdentity() throws {
        let record = try Record(dayID: UUID(), at: Date(), kind: .focus, body: Focus.hidden(windowID: 9, reason: .blocked))
        let text = String(decoding: record.body, as: UTF8.self)
        #expect(!text.contains("cmb") && text.contains("blocked"))
        #expect(try record.decode(Focus.self).hidden == .blocked)
    }
}
