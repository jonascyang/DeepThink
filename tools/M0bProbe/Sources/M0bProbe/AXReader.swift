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
    private static let titleRoles: Set<String> = ["AXStaticText", "AXHeading", "AXLink", "AXCell", "AXMenuItem", "AXButton", "AXTab", "AXRadioButton"]

    static func read(window: AXUIElement, windowFrame: CGRect) -> AXReadResult {
        var r = AXReadResult()
        let start = DispatchTime.now().uptimeNanoseconds
        var stack: [AXUIElement] = [window]
        let cfNames = names as CFArray

        while let el = stack.popLast() {
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
            // Password fields are never read, and neither is anything inside them.
            if subrole == kAXSecureTextFieldSubrole || role == "AXSecureTextField" { continue }

            var text = val(2) as? String ?? ""
            if text.isEmpty, titleRoles.contains(role) { text = val(3) as? String ?? "" }

            if !text.isEmpty {
                let count = text.count
                r.chars += count
                var visible = count
                if let rv = val(7), CFGetTypeID(rv) == AXValueGetTypeID() {
                    var range = CFRange()
                    if AXValueGetValue(rv as! AXValue, .cfRange, &range) {
                        visible = min(count, max(0, range.length))
                        let ns = text as NSString
                        if visible < count, range.location >= 0, range.location + range.length <= ns.length {
                            text = ns.substring(with: NSRange(location: range.location, length: range.length))
                        }
                    }
                } else if let p = val(5), let s = val(6), let f = AX.rect(position: p, size: s), f.width > 0, f.height > 0,
                          !f.intersects(windowFrame) {
                    visible = 0
                }
                if visible > 0 {
                    r.visibleChars += visible
                    for line in text.split(whereSeparator: \.isNewline) {
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { r.lines.append(t) }
                    }
                }
            }
            if let kids = val(4) as? [AXUIElement] {
                stack.append(contentsOf: kids.reversed())
            }
        }
        r.ms = elapsedMs(since: start)
        return r
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
