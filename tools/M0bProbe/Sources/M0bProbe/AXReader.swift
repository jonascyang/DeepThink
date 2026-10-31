import ApplicationServices
import Foundation

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(el, &id) == .success && id != 0 ? id : nil
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute) else { return nil }
        return rect(position: p, size: s)
    }

    static func rect(position: CFTypeRef, size: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &pt),
              AXValueGetValue(size as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    /// AXUIElementCopyMultipleAttributeValues puts an AXValue of type .axError in failed slots.
    static func isError(_ v: CFTypeRef) -> Bool {
        CFGetTypeID(v) == AXValueGetTypeID() && AXValueGetType(v as! AXValue) == .axError
    }
}

struct AXReadResult {
    var chars = 0
    var visibleChars = 0
    var nodes = 0
    var ms = 0.0
    var truncated = false
    // Diagnostics for the visibility rule: how many text elements took each branch.
    var textElems = 0
    var rangeElems = 0
    var rangeShort = 0
    var frameOutside = 0
    var noFrame = 0
    var cappedElems = 0
    /// Visible text split into trimmed, non-empty lines. Kept in memory only for de-duplication.
    var lines: [String] = []
}

enum AXReader {
    static let maxNodes = 6000
    static let maxMs = 400.0

    private static let names: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXTitleAttribute,
        kAXChildrenAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXVisibleCharacterRangeAttribute,
    ]
    private static let clipRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
    private static let editableRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
    private static let titleRoles: Set<String> = ["AXStaticText", "AXHeading", "AXLink", "AXCell", "AXMenuItem", "AXButton", "AXTab", "AXRadioButton"]

    static func read(window: AXUIElement, windowFrame: CGRect) -> AXReadResult {
        var r = AXReadResult()
        let start = DispatchTime.now().uptimeNanoseconds
        // Each element carries the visible area of its nearest scroll ancestors, so text
        // scrolled out of a pane counts as invisible even though it sits inside the window.
        var stack: [(AXUIElement, CGRect)] = [(window, windowFrame)]
        let cfNames = names as CFArray

        while let (el, clip) = stack.popLast() {
            r.nodes += 1
            if r.nodes > maxNodes || elapsedMs(since: start) > maxMs {
                r.truncated = true
                break
            }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(el, cfNames, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let vals = raw as? [CFTypeRef], vals.count == names.count else { continue }
            func val(_ i: Int) -> CFTypeRef? { AX.isError(vals[i]) ? nil : vals[i] }

            let role = val(0) as? String ?? ""
            let subrole = val(1) as? String ?? ""
            var frame: CGRect?
            if let p = val(5), let s = val(6), let f = AX.rect(position: p, size: s) { frame = f }
            var childClip = clip
            if clipRoles.contains(role), let frame, frame.width > 0, frame.height > 0 { childClip = clip.intersection(frame) }
            // Password fields are never read, and neither is anything inside them.
            if subrole == kAXSecureTextFieldSubrole || role == "AXSecureTextField" { continue }

            var text = val(2) as? String ?? ""
            // Chromium titles a link, button or heading with its children's text; read the title only
            // on leaves so the same words are not counted twice.
            let kids = val(4) as? [AXUIElement] ?? []
            if text.isEmpty, titleRoles.contains(role), kids.isEmpty { text = val(3) as? String ?? "" }

            if !text.isEmpty {
                let count = text.count
                r.chars += count
                r.textElems += 1
                var visible = count
                // Chromium reports a near-empty AXVisibleCharacterRange on ordinary static text,
                // so the frame decides visibility; the range only trims long editable text.
                // Chromium squashes scrolled-out text to a 1 pt strip at the edge of its scroll pane.
                if let f = frame {
                    if f.width < 2 || f.height < 2 || !f.intersects(clip) {
                        visible = 0
                        r.frameOutside += 1
                    }
                } else {
                    r.noFrame += 1
                }
                // Single-line labels often hold far more text than they show before the ellipsis;
                // cap at what the box can fit (≥6 pt per character, ≥14 pt per line).
                if visible > 0, let f = frame, !editableRoles.contains(role) {
                    let capacity = Int((f.width / 6).rounded(.up)) * max(1, Int(f.height / 14))
                    if capacity < visible {
                        visible = capacity
                        text = String(text.prefix(capacity))
                        r.cappedElems += 1
                    }
                }
                if visible > 0, editableRoles.contains(role), let rv = val(7), CFGetTypeID(rv) == AXValueGetTypeID() {
                    var range = CFRange()
                    if AXValueGetValue(rv as! AXValue, .cfRange, &range) {
                        r.rangeElems += 1
                        if range.length < count { r.rangeShort += 1 }
                        let ns = text as NSString
                        if range.length > 0, range.length < ns.length, range.location >= 0, range.location + range.length <= ns.length {
                            text = ns.substring(with: NSRange(location: range.location, length: range.length))
                            visible = text.count
                        }
                    }
                }
                if visible > 0 {
                    r.visibleChars += visible
                    for line in text.split(whereSeparator: \.isNewline) {
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { r.lines.append(t) }
                    }
                }
            }
            stack.append(contentsOf: kids.reversed().map { ($0, childClip) })
        }
        r.ms = elapsedMs(since: start)
        return r
    }

    /// Development aid: the element tree as role, subrole, frame and text length per line. Never any text.
    static func dumpStructure(window: AXUIElement, maxNodes: Int = 4000) -> String {
        var out = ""
        var stack: [(AXUIElement, Int)] = [(window, 0)]
        let cfNames = names as CFArray
        var count = 0
        while let (el, depth) = stack.popLast(), count < maxNodes {
            count += 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(el, cfNames, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let vals = raw as? [CFTypeRef], vals.count == names.count else { continue }
            func val(_ i: Int) -> CFTypeRef? { AX.isError(vals[i]) ? nil : vals[i] }
            let role = val(0) as? String ?? "?"
            let subrole = val(1) as? String ?? ""
            let len = (val(2) as? String)?.count ?? 0
            let tlen = (val(3) as? String)?.count ?? 0
            var fr = "-"
            if let p = val(5), let s = val(6), let f = AX.rect(position: p, size: s) {
                fr = "\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))"
            }
            out += String(repeating: " ", count: depth) + "\(role) \(subrole) \(fr) len=\(len) tlen=\(tlen)\n"
            if let kids = val(4) as? [AXUIElement] { stack.append(contentsOf: kids.reversed().map { ($0, depth + 1) }) }
        }
        return out
    }

    static func elapsedMs(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}

enum TextStats {
    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3000...0x303F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF: return true
        default: return false
        }
    }

    static func cjkCount(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { $0 + (isCJK($1) ? 1 : 0) }
    }
}
