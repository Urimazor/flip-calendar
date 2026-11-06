import AppKit
import WebKit

/// Flip Calendar as a live desktop wallpaper: one borderless window per screen, at desktop level,
/// behind the icons and all apps, ignoring the mouse. A menu-bar icon lets you quit.
/// Sticky notes live in a second, transparent window per screen, just above Finder's desktop-icon layer (Finder keeps a
/// full-screen window there that would otherwise swallow every click). That page shows only the + and the notes and
/// reports where they are; while the pointer is over one of them the overlay takes clicks, otherwise everything goes
/// through to the desktop.
final class DeskWindow: NSWindow {
    override var canBecomeKey: Bool { true }     // so a note can be typed into
    override var canBecomeMain: Bool { false }
}
final class DeskWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   // first click acts, even when inactive
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, WKScriptMessageHandler {
    private var windows: [NSWindow] = []
    private var windowScreens: [String] = []          // display UUID for each window
    private var thisDesktopItem: NSMenuItem?
    private var allDesktopsItem: NSMenuItem?
    private let allKey = "showOnAllDesktops", enabledKey = "enabledDesktops"
    private var showOnAll: Bool {
        get { UserDefaults.standard.object(forKey: allKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: allKey) }
    }
    private var enabledDesktops: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: enabledKey) }
    }
    private var statusItem: NSStatusItem?
    private var html: String = ""
    private var webViews: [WKWebView] = []
    private let scaleKey = "wallpaperScale"
    private var scale: Double {
        get { let v = UserDefaults.standard.double(forKey: scaleKey); return v == 0 ? 1.0 : v }
        set { UserDefaults.standard.set(newValue, forKey: scaleKey) }
    }
    private var sizeLabel: NSTextField?
    private var hoverTimer: Timer?
    private var lastMouse = NSPoint(x: -1, y: -1)
    private var hoverIndex: Int? = nil
    private var slider: NSSlider?
    private var hotRects: [[CGRect]] = []           // clickable areas per overlay (page coordinates, top-left origin)
    private var overlays: [NSWindow] = []
    private var overlayViews: [WKWebView] = []
    private var lastHot: Int? = nil

    func applicationDidFinishLaunching(_ note: Notification) {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html"),
           let s = try? String(contentsOf: url, encoding: .utf8) { html = s }
        buildWindows()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◷"
        let menu = NSMenu()
        // Size: shrinks/enlarges the clock + calendar; the rest of the screen stays black
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 18, y: 30, width: 230, height: 18)
        label.font = NSFont.menuFont(ofSize: 13)
        let sl = NSSlider(value: scale * 100, minValue: 40, maxValue: 100, target: self, action: #selector(sliderMoved(_:)))
        sl.frame = NSRect(x: 16, y: 6, width: 228, height: 22)
        sl.isContinuous = true
        box.addSubview(label); box.addSubview(sl)
        let sizeItem = NSMenuItem(); sizeItem.view = box
        menu.addItem(sizeItem)
        sizeLabel = label; slider = sl
        updateLabel()
        for pct in [100, 90, 80, 70, 60, 50] {
            let mi = NSMenuItem(title: "\(pct)%", action: #selector(presetChosen(_:)), keyEquivalent: "")
            mi.tag = pct; mi.target = self; mi.indentationLevel = 1
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        // Desktops (Spaces): choose on which desktops the wallpaper appears
        let thisItem = NSMenuItem(title: "Show on This Desktop", action: #selector(toggleThisDesktop), keyEquivalent: "d")
        thisItem.target = self
        let allItem = NSMenuItem(title: "Show on All Desktops", action: #selector(toggleAllDesktops), keyEquivalent: "")
        allItem.target = self
        menu.addItem(thisItem); menu.addItem(allItem)
        thisDesktopItem = thisItem; allDesktopsItem = allItem
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reload Flip Calendar", action: #selector(screensChanged), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flip Calendar Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        // Hover: the window ignores the mouse (so desktop icons keep working); instead we follow the pointer
        // and, while it is over uncovered desktop, tell the page where it is so it can show the date tooltip.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.trackHover() }
    }

    private func trackHover() {
        let mouse = NSEvent.mouseLocation
        let dragging = NSEvent.pressedMouseButtons != 0
        if mouse == lastMouse && !dragging { return }
        lastMouse = mouse
        var target: (Int, NSPoint)? = nil
        for (i, w) in windows.enumerated() where w.isVisible && NSMouseInRect(mouse, w.frame, false) {
            if !isCovered(mouse) {
                target = (i, NSPoint(x: mouse.x - w.frame.minX, y: w.frame.maxY - mouse.y))
            }
            break
        }
        // the overlay takes clicks only over a note or the + (and keeps them for the rest of a drag that started there)
        var hotIndex: Int? = nil
        for (i, w) in overlays.enumerated() {
            var hot = false
            if let (ti, p) = target, ti == i, i < hotRects.count {
                hot = hotRects[i].contains { $0.insetBy(dx: -2, dy: -2).contains(p) }
            }
            if dragging && !w.ignoresMouseEvents { hot = true }
            if w.ignoresMouseEvents == hot { w.ignoresMouseEvents = !hot }
            if hot { hotIndex = i }
        }
        // notes/+ hover goes to the overlay; the date tooltip to the calendar underneath (not while over a note)
        if let old = lastHot, old != hotIndex, old < overlayViews.count {
            overlayViews[old].evaluateJavaScript("window.__hover && window.__hover(null)", completionHandler: nil)
        }
        lastHot = hotIndex
        if let i = hotIndex, let (_, p) = target, i < overlayViews.count {
            overlayViews[i].evaluateJavaScript("window.__hover && window.__hover(\(p.x), \(p.y))", completionHandler: nil)
        }
        let calTarget = hotIndex == nil ? target : nil
        if let old = hoverIndex, old != calTarget?.0, old < webViews.count {
            webViews[old].evaluateJavaScript("window.__hover && window.__hover(null)", completionHandler: nil)
        }
        hoverIndex = calTarget?.0
        if let (i, p) = calTarget, i < webViews.count {
            webViews[i].evaluateJavaScript("window.__hover && window.__hover(\(p.x), \(p.y))", completionHandler: nil)
        }
    }

    /// True if any normal window, the Dock or the menu bar is on top of this point.
    private func isCovered(_ mouse: NSPoint) -> Bool {
        guard let main = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let pt = CGPoint(x: mouse.x, y: main.frame.maxY - mouse.y)   // Quartz coordinates (top-left origin)
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            if (info[kCGWindowOwnerPID as String] as? Int32) == me { continue }
            if (info[kCGWindowLayer as String] as? Int ?? 0) < 0 { continue }
            if (info[kCGWindowAlpha as String] as? Double ?? 1) <= 0.01 { continue }
            guard let bd = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd) else { continue }
            // The Dock keeps an invisible full-screen window (layer 20) for Mission Control; it covers nothing.
            if (info[kCGWindowOwnerName as String] as? String) == "Dock",
               NSScreen.screens.contains(where: { $0.frame.size == r.size }) { continue }
            if r.contains(pt) { return true }
        }
        return false
    }

    @objc private func screensChanged() { buildWindows() }

    // MARK: messages from the page (sticky notes)

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String,
              let wv = message.webView, let i = overlayViews.firstIndex(where: { $0 === wv }) else { return }
        switch type {
        case "rects":
            let rs = (body["rects"] as? [[Double]] ?? []).compactMap { a -> CGRect? in
                a.count == 4 ? CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) : nil }
            while hotRects.count <= i { hotRects.append([]) }
            hotRects[i] = rs
            lastMouse = NSPoint(x: -1, y: -1)        // re-check the pointer now
        case "notes":
            if let j = body["json"] as? String, i < windowScreens.count {
                UserDefaults.standard.set(j, forKey: notesKey(windowScreens[i]))
            }
        case "focus":
            NSApp.activate(ignoringOtherApps: true)
            overlays[i].makeKey()
            overlays[i].makeFirstResponder(overlayViews[i])
        default: break
        }
    }

    fileprivate var scaleValue: Double { scale }
    fileprivate var pageHTML: String { html }
    fileprivate func notesJSONFor(_ d: String) -> String { notesJSON(d) }
    private func notesKey(_ display: String) -> String { "notes-" + (display.isEmpty ? "main" : display) }

    /// Saved notes for a display as a JSON array literal (validated, so it is safe to put into the page).
    private func notesJSON(_ display: String) -> String {
        guard let j = UserDefaults.standard.string(forKey: notesKey(display)), let d = j.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: d)) is [Any] else { return "[]" }
        return j
    }

    // MARK: desktops (Spaces)

    @objc private func spaceChanged() { applyVisibility() }

    /// Space key of the desktop currently shown on the screen with the mouse (the one the user is working in).
    private func currentDesktop() -> (key: String, number: Int)? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return Spaces.current(forDisplay: screen.flatMap(displayUUID))
    }

    @objc private func toggleThisDesktop() {
        guard let cur = currentDesktop() else { return }
        var set = enabledDesktops
        if showOnAll {
            // switching from "everywhere" to a per-desktop list: keep every other known desktop on, turn this one off
            set = Set(Spaces.allDesktopKeys()); set.remove(cur.key); showOnAll = false
        } else if set.contains(cur.key) { set.remove(cur.key) } else { set.insert(cur.key) }
        enabledDesktops = set
        applyVisibility()
    }

    @objc private func toggleAllDesktops() {
        showOnAll.toggle()
        if !showOnAll, enabledDesktops.isEmpty, let cur = currentDesktop() { enabledDesktops = [cur.key] }
        applyVisibility()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let cur = currentDesktop()
        if let cur = cur {
            thisDesktopItem?.title = "Show on This Desktop (Desktop \(cur.number))"
            thisDesktopItem?.state = (showOnAll || enabledDesktops.contains(cur.key)) ? .on : .off
            thisDesktopItem?.isEnabled = true
        } else {
            thisDesktopItem?.title = "Show on This Desktop (unavailable)"
            thisDesktopItem?.isEnabled = false
        }
        allDesktopsItem?.state = showOnAll ? .on : .off
    }

    private func applyVisibility() {
        for (i, w) in windows.enumerated() {
            var visible = true
            if !showOnAll {
                if let cur = Spaces.current(forDisplay: windowScreens[i]) { visible = enabledDesktops.contains(cur.key) }
            }
            if visible { w.orderBack(nil) } else { w.orderOut(nil) }
            if i < overlays.count { if visible { overlays[i].orderFrontRegardless() } else { overlays[i].orderOut(nil) } }
        }
    }

    @objc private func sliderMoved(_ s: NSSlider) { applyScale((s.doubleValue / 5).rounded() * 5 / 100) }
    @objc private func presetChosen(_ m: NSMenuItem) { applyScale(Double(m.tag) / 100); slider?.doubleValue = Double(m.tag) }

    private func applyScale(_ v: Double) {
        scale = v
        updateLabel()
        for wv in webViews + overlayViews { wv.evaluateJavaScript("window.__setScale && window.__setScale(\(v))", completionHandler: nil) }
    }

    private func updateLabel() { sizeLabel?.stringValue = "Size: \(Int((scale * 100).rounded()))%" }

    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        overlays.forEach { $0.orderOut(nil) }
        windows.removeAll()
        overlays.removeAll()
        overlayViews.removeAll()
        lastHot = nil
        webViews.removeAll()
        windowScreens.removeAll()
        hotRects.removeAll()
        for screen in NSScreen.screens {
            let display = displayUUID(screen) ?? ""
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            w.ignoresMouseEvents = true
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.isReleasedWhenClosed = false

            let config = WKWebViewConfiguration()
            config.userContentController.addUserScript(WKUserScript(
                source: "window.__SAVER__ = { wallpaper: true, scale: \(scale) };",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
            // App windows cover the desktop, so WebKit would think the page is hidden and freeze it.
            for sel in ["_setHiddenPageDOMTimerThrottlingEnabled:", "_setHiddenPageDOMTimerThrottlingAutoIncreases:",
                        "_setPageVisibilityBasedProcessSuppressionEnabled:"] {
                callBoolSetter(config.preferences, sel, false)
            }
            let wv = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
            callBoolSetter(wv, "_setWindowOcclusionDetectionEnabled:", false)
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")
            wv.loadHTMLString(html, baseURL: nil)
            w.contentView = wv
            webViews.append(wv)
            w.setFrame(screen.frame, display: true)
            w.orderBack(nil)
            windows.append(w)
            windowScreens.append(display)
            hotRects.append([])
            addOverlay(screen: screen, display: display)
        }
        applyVisibility()
    }
}

extension AppDelegate {
    /// Transparent window above Finder's desktop icons (below every app) that holds the + and the sticky notes.
    fileprivate func addOverlay(screen: NSScreen, display: String) {
        let o = DeskWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        o.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        o.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        o.ignoresMouseEvents = true
        o.backgroundColor = .clear
        o.isOpaque = false
        o.hasShadow = false
        o.isReleasedWhenClosed = false
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(
            source: "window.__SAVER__ = { wallpaper: true, overlay: true, scale: \(scaleValue), notes: \(notesJSONFor(display)) };",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(self, name: "flip")
        for sel in ["_setHiddenPageDOMTimerThrottlingEnabled:", "_setHiddenPageDOMTimerThrottlingAutoIncreases:",
                    "_setPageVisibilityBasedProcessSuppressionEnabled:"] {
            callBoolSetter(config.preferences, sel, false)
        }
        let wv = DeskWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
        callBoolSetter(wv, "_setWindowOcclusionDetectionEnabled:", false)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        wv.loadHTMLString(pageHTML, baseURL: nil)
        o.contentView = wv
        o.setFrame(screen.frame, display: true)
        o.orderFrontRegardless()
        overlays.append(o)
        overlayViews.append(wv)
    }
}

func displayUUID(_ screen: NSScreen) -> String? {
    guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
          let u = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, u) as String
}

/// Reads macOS desktops (Spaces) through the private SkyLight/CoreGraphics calls that tools like
/// yabai and Hammerspoon use. If Apple removes them, per-desktop control turns off and the wallpaper shows everywhere.
enum Spaces {
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias CopyFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func sym(_ a: String, _ b: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, a) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), b)   // -2 = RTLD_DEFAULT
    }
    private static let conn: ConnFn? = sym("SLSMainConnectionID", "CGSMainConnectionID").map { unsafeBitCast($0, to: ConnFn.self) }
    private static let copy: CopyFn? = sym("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopyFn.self) }

    private static func displays() -> [[String: Any]] {
        guard let conn = conn, let copy = copy, let arr = copy(conn())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return arr
    }
    private static func key(_ space: [String: Any]) -> String {
        if let u = space["uuid"] as? String, !u.isEmpty { return u }
        return "id-\(space["ManagedSpaceID"] ?? space["id64"] ?? "main")"
    }
    /// Current desktop on a display (display UUID; nil = main). Number counts regular desktops 1, 2, 3…
    static func current(forDisplay uuid: String?) -> (key: String, number: Int)? {
        let all = displays(); if all.isEmpty { return nil }
        let d = all.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(uuid ?? "") == .orderedSame }
            ?? all.first { ($0["Display Identifier"] as? String) == "Main" } ?? all[0]
        guard let cur = d["Current Space"] as? [String: Any] else { return nil }
        let regular = (d["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int ?? 0) == 0 }
        let n = (regular.firstIndex { key($0) == key(cur) } ?? -1) + 1
        return (key(cur), n)
    }
    static func allDesktopKeys() -> [String] {
        displays().flatMap { ($0["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int ?? 0) == 0 }.map(key) }
    }
}

/// Calls a private `-(void)setX:(BOOL)` method if it exists (no-op otherwise).
/// (`perform(_:with:)` would pass an object pointer, not a BOOL, so the flag would not reliably be NO.)
func callBoolSetter(_ obj: NSObject, _ name: String, _ value: Bool) {
    let sel = NSSelectorFromString(name)
    guard obj.responds(to: sel), let imp = obj.method(for: sel) else { return }
    typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
    unsafeBitCast(imp, to: Fn.self)(obj, sel, value)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
