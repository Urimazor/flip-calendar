import AppKit
import WebKit

/// Flip Calendar as a live desktop wallpaper: one borderless window per screen, at desktop level,
/// behind the icons and all apps, ignoring the mouse. A menu-bar icon lets you quit.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private var slider: NSSlider?

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
    }

    @objc private func screensChanged() { buildWindows() }

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
        }
    }

    @objc private func sliderMoved(_ s: NSSlider) { applyScale((s.doubleValue / 5).rounded() * 5 / 100) }
    @objc private func presetChosen(_ m: NSMenuItem) { applyScale(Double(m.tag) / 100); slider?.doubleValue = Double(m.tag) }

    private func applyScale(_ v: Double) {
        scale = v
        updateLabel()
        for wv in webViews { wv.evaluateJavaScript("window.__setScale && window.__setScale(\(v))", completionHandler: nil) }
    }

    private func updateLabel() { sizeLabel?.stringValue = "Size: \(Int((scale * 100).rounded()))%" }

    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        webViews.removeAll()
        windowScreens.removeAll()
        for screen in NSScreen.screens {
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
                source: "window.__SAVER__ = { wallpaper: true, scale: \(scale) };", injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
            windowScreens.append(displayUUID(screen) ?? "")
        }
        applyVisibility()
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
