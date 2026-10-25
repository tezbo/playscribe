// Duo Pose Driver: drives Xcode Device Hub's pose controls through the Accessibility API, so QA
// can capture every iPhone Duo pose without anyone dragging the hinge. Signed with a stable
// self-signed identity, so rebuilds keep the Accessibility grant.
//
//   posedriver tree [maxDepth] [maxNodes]   windows' AX tree to /tmp/posedriver.txt (menus skipped)
//   posedriver press <text>                 AXPress the first window element whose title, description,
//                                           help, identifier or value equals <text> (then contains it)
//   posedriver set <text> <number>          set that element's value (sliders)
//   posedriver click <text>                 post a mouse click at the centre of that element
//   posedriver menu <title> <item>…         walk the menu bar by titles and press the last item
//   posedriver keys <text>                  type text into the frontmost field
import AppKit
import ApplicationServices

let out = URL(fileURLWithPath: "/tmp/posedriver.txt")
var log = ""
func emit(_ s: String) { log += s + "\n" }
func finish(_ code: Int32) -> Never { try? log.write(to: out, atomically: true, encoding: .utf8); exit(code) }

let args = Array(CommandLine.arguments.dropFirst())
guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
    emit("ERROR not-trusted"); finish(2)
}
guard let hub = NSWorkspace.shared.runningApplications.first(where: { ($0.bundleIdentifier ?? "").contains("DeviceHub") || $0.localizedName == "Device Hub" }) else {
    emit("ERROR Device Hub is not running"); finish(3)
}
let app = AXUIElementCreateApplication(hub.processIdentifier)
AXUIElementSetMessagingTimeout(app, 2)

func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func s(_ e: AXUIElement, _ n: String) -> String { attr(e, n).map { "\($0)" } ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, kAXPositionAttribute), let z = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(z as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}
func texts(_ e: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute, kAXValueAttribute].map { s(e, $0) }.filter { !$0.isEmpty }
}
func describe(_ e: AXUIElement) -> String {
    let f = frame(e).map { " @\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
    let acts = ((try? { var a: CFArray?; AXUIElementCopyActionNames(e, &a); return a as? [String] ?? [] }()) ?? []).joined(separator: ",")
    return "\(s(e, kAXRoleAttribute)) title=\(s(e, kAXTitleAttribute)) desc=\(s(e, kAXDescriptionAttribute)) help=\(s(e, kAXHelpAttribute)) id=\(s(e, kAXIdentifierAttribute)) value=\(s(e, kAXValueAttribute))\(f) [\(acts)]"
}
func windows() -> [AXUIElement] { (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }

/// Breadth-first over the windows, bounded, so deep 3D views can't stall it.
func search(maxDepth: Int = 30, maxNodes: Int = 6000, _ visit: (AXUIElement, Int) -> Bool) {
    var queue: [(AXUIElement, Int)] = windows().map { ($0, 0) }
    var n = 0
    while !queue.isEmpty, n < maxNodes {
        let (e, d) = queue.removeFirst(); n += 1
        if visit(e, d) { return }
        if d < maxDepth { queue += kids(e).map { ($0, d + 1) } }
    }
}
func find(_ text: String) -> AXUIElement? {
    let t = text.lowercased()
    var exact: AXUIElement?, partial: AXUIElement?
    search { e, _ in
        let ts = texts(e).map { $0.lowercased() }
        if ts.contains(t) { exact = e; return true }
        if partial == nil, ts.contains(where: { $0.contains(t) }) { partial = e }
        return false
    }
    return exact ?? partial
}
func click(_ p: CGPoint) {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
}

hub.activate()
usleep(300_000)
switch args.first {
case "tree":
    let depth = args.count > 1 ? Int(args[1]) ?? 30 : 30, nodes = args.count > 2 ? Int(args[2]) ?? 6000 : 6000
    search(maxDepth: depth, maxNodes: nodes) { e, d in emit(String(repeating: "  ", count: d) + describe(e)); return false }
case "press":
    guard args.count > 1, let e = find(args[1...].joined(separator: " ")) else { emit("ERROR no match"); finish(4) }
    emit("press \(describe(e)) → \(AXUIElementPerformAction(e, kAXPressAction as CFString).rawValue)")
case "set":
    guard args.count > 2, let e = find(args[1]), let v = Double(args[2]) else { emit("ERROR usage or no match"); finish(4) }
    emit("set \(describe(e)) → \(AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, NSNumber(value: v)).rawValue)")
case "click":
    guard args.count > 1, let e = find(args[1...].joined(separator: " ")), let f = frame(e) else { emit("ERROR no match"); finish(4) }
    click(CGPoint(x: f.midX, y: f.midY)); emit("clicked \(describe(e))")
case "menu":
    var cur: AXUIElement? = attr(app, kAXMenuBarAttribute).map { $0 as! AXUIElement }
    for title in args.dropFirst() {
        guard let c = cur else { break }
        var next: AXUIElement?
        var q = kids(c)
        while !q.isEmpty { let e = q.removeFirst(); if s(e, kAXTitleAttribute) == title { next = e; break }; if s(e, kAXRoleAttribute) == "AXMenu" { q += kids(e) } }
        guard let n = next else { emit("ERROR menu item \(title) not found"); finish(4) }
        AXUIElementPerformAction(n, kAXPressAction as CFString); usleep(200_000)
        cur = n
    }
    emit("menu done")
case "keys":
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in (args.dropFirst().joined(separator: " ")).utf16 {
        for down in [true, false] {
            let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            var c = ch; ev?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c); ev?.post(tap: .cghidEventTap)
        }
    }
    emit("typed")
default:
    emit("usage: tree | press | set | click | menu | keys")
}
finish(0)
