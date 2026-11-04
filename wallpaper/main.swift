import AppKit
import WebKit

/// Flip Calendar as a live desktop wallpaper: one borderless window per screen, at desktop level,
/// behind the icons and all apps, ignoring the mouse. A menu-bar icon lets you quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
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
        menu.addItem(NSMenuItem(title: "Reload Flip Calendar", action: #selector(screensChanged), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flip Calendar Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func screensChanged() { buildWindows() }

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
        }
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
