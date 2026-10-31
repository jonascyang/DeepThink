import CoreGraphics
import Foundation

/// One accessibility element, already read. The live walker in the app builds these; tests build them by hand.
public struct ElementSnapshot: Sendable {
    public var role: String
    public var subrole: String
    public var value: String?
    public var title: String?
    /// Global screen coordinates, top-left origin, like CGWindowList bounds.
    public var frame: CGRect?
    /// AXVisibleCharacterRange, if the element reports one.
    public var visibleRange: NSRange?
    public var children: [ElementSnapshot]

    public init(role: String, subrole: String = "", value: String? = nil, title: String? = nil,
                frame: CGRect? = nil, visibleRange: NSRange? = nil, children: [ElementSnapshot] = []) {
        self.role = role
        self.subrole = subrole
        self.value = value
        self.title = title
        self.frame = frame
        self.visibleRange = visibleRange
        self.children = children
    }

    /// Password fields are never read, and neither is anything inside them.
    public var isSecure: Bool { role == "AXSecureTextField" || subrole == "AXSecureTextField" }
}

public struct ExtractedText: Sendable, Equatable {
    /// Text of every visible element, split into trimmed non-empty lines, in reading order.
    public var lines: [String] = []
    /// Characters recorded (full text, including what a single-line label hides behind its ellipsis).
    public var chars = 0
    /// Characters that fit on screen. Statistics only; used to decide when to fall back to OCR.
    public var visibleChars = 0
}

/// Decides which text in a window is on screen. Every rule here comes from the M0b probe (docs/M0b-探测报告.md §3.1).
public enum VisibleText {
    public static let clipRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
    static let editableRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
    static let titleRoles: Set<String> = ["AXStaticText", "AXHeading", "AXLink", "AXCell", "AXMenuItem", "AXButton", "AXTab", "AXRadioButton"]

    public static func extract(_ root: ElementSnapshot, windowFrame: CGRect) -> ExtractedText {
        var out = ExtractedText()
        var stack: [(ElementSnapshot, CGRect)] = [(root, windowFrame)]
        while let (el, clip) = stack.popLast() {
            if el.isSecure { continue }

            var childClip = clip
            if clipRoles.contains(el.role), let f = el.frame, f.width > 0, f.height > 0 {
                childClip = clip.intersection(f)
            }

            // Chromium titles a link, button or heading with its children's text; read the title only
            // on leaves so the same words are not counted twice.
            var text = el.value ?? ""
            if text.isEmpty, titleRoles.contains(el.role), el.children.isEmpty { text = el.title ?? "" }

            if !text.isEmpty, isVisible(el.frame, clip: clip) {
                // AXVisibleCharacterRange is near-empty on Chromium's static text, so it only trims editable text.
                if editableRoles.contains(el.role), let range = el.visibleRange {
                    let ns = text as NSString
                    if range.length > 0, range.length < ns.length, range.location >= 0, NSMaxRange(range) <= ns.length {
                        text = ns.substring(with: range)
                    }
                }
                let count = text.count
                out.chars += count
                // Single-line labels may hold far more than they show; the full text is recorded, the
                // visible count is capped at what the box fits (≥ 6 pt per character, ≥ 14 pt per line).
                if let f = el.frame, !editableRoles.contains(el.role) {
                    out.visibleChars += min(count, Int((f.width / 6).rounded(.up)) * max(1, Int(f.height / 14)))
                } else {
                    out.visibleChars += count
                }
                for line in text.split(whereSeparator: \.isNewline) {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { out.lines.append(t) }
                }
            }
            stack.append(contentsOf: el.children.reversed().map { ($0, childClip) })
        }
        return out
    }

    /// No frame counts as visible. Chromium squashes scrolled-out text into a 1 pt strip at the pane edge.
    static func isVisible(_ frame: CGRect?, clip: CGRect) -> Bool {
        guard let f = frame else { return true }
        return f.width >= 2 && f.height >= 2 && f.intersects(clip)
    }
}
