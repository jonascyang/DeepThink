import ApplicationServices
import Foundation
import ThinkMyDayCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

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
        guard AXValueGetValue(position as! AXValue, .cgPoint, &pt), AXValueGetValue(size as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    /// AXUIElementCopyMultipleAttributeValues puts an AXValue of type .axError in failed slots.
    static func isError(_ v: CFTypeRef) -> Bool {
        CFGetTypeID(v) == AXValueGetTypeID() && AXValueGetType(v as! AXValue) == .axError
    }
}

/// Reads a window's accessibility tree into `ElementSnapshot`s within a node and time budget.
enum AXWalker {
    struct Budget {
        var maxNodes = 6000
        var maxMs = 400.0
    }

    struct Result {
        var root: ElementSnapshot
        var truncated: Bool
        var nodes: Int
        var ms: Double
    }

    private static let names: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXTitleAttribute,
        kAXChildrenAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXVisibleCharacterRangeAttribute,
    ]

    static func read(window: AXUIElement, windowFrame: CGRect, budget: Budget = Budget()) -> Result {
        let start = DispatchTime.now().uptimeNanoseconds
        var nodes = 0
        var truncated = false
        let cfNames = names as CFArray

        func visit(_ el: AXUIElement, clip: CGRect) -> ElementSnapshot? {
            nodes += 1
            if nodes > budget.maxNodes || elapsedMs(since: start) > budget.maxMs {
                truncated = true
                return nil
            }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(el, cfNames, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let vals = raw as? [CFTypeRef], vals.count == names.count else { return nil }
            func val(_ i: Int) -> CFTypeRef? { AX.isError(vals[i]) ? nil : vals[i] }

            var snap = ElementSnapshot(role: val(0) as? String ?? "", subrole: val(1) as? String ?? "")
            if let p = val(5), let s = val(6) { snap.frame = AX.rect(position: p, size: s) }
            // Never even copy a password field's value, and do not descend into it.
            if snap.isSecure { return snap }
            snap.value = val(2) as? String
            snap.title = val(3) as? String
            if let rv = val(7), CFGetTypeID(rv) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(rv as! AXValue, .cfRange, &range) { snap.visibleRange = NSRange(location: range.location, length: range.length) }
            }

            // Skip whole subtrees that sit outside the visible area: large web pages keep most of the DOM off screen.
            if let f = snap.frame, f.width >= 2, f.height >= 2, !f.intersects(clip) { return snap }
            var childClip = clip
            if VisibleText.clipRoles.contains(snap.role), let f = snap.frame, f.width > 0, f.height > 0 { childClip = clip.intersection(f) }

            if let kids = val(4) as? [AXUIElement] {
                for kid in kids {
                    if truncated { break }
                    if let child = visit(kid, clip: childClip) { snap.children.append(child) }
                }
            }
            return snap
        }

        let root = visit(window, clip: windowFrame) ?? ElementSnapshot(role: "AXWindow")
        return Result(root: root, truncated: truncated, nodes: nodes, ms: elapsedMs(since: start))
    }

    static func elapsedMs(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
