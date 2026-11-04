import AppKit
import WebKit

/// Flip Calendar as a live desktop wallpaper: one borderless window per screen, at desktop level,
/// behind the icons and all apps, ignoring the mouse. A menu-bar icon lets you quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var html: String = ""

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
        menu.addItem(NSMenuItem(title: "Reload Flip Calendar", action: #selector(screensChanged), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flip Calendar Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func screensChanged() { buildWindows() }

    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
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
                source: "window.__SAVER__ = { wallpaper: true };", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            // App windows cover the desktop, so WebKit would think the page is hidden and freeze it.
            let prefs = config.preferences
            for sel in ["_setHiddenPageDOMTimerThrottlingEnabled:", "_setHiddenPageDOMTimerThrottlingAutoIncreases:",
                        "_setPageVisibilityBasedProcessSuppressionEnabled:"] {
                let s = NSSelectorFromString(sel)
                if prefs.responds(to: s) { prefs.perform(s, with: false as NSNumber) }
            }
            let wv = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
            let occ = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
            if wv.responds(to: occ) { wv.perform(occ, with: false as NSNumber) }
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")
            wv.loadHTMLString(html, baseURL: nil)
            w.contentView = wv
            w.setFrame(screen.frame, display: true)
            w.orderBack(nil)
            windows.append(w)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
