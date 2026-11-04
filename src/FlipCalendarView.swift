import AppKit
import ScreenSaver
import WebKit

/// Native macOS screen saver that renders web/index.html (flip clock + landscape calendar) in a WKWebView.
@objc(FlipCalendarView)
public final class FlipCalendarView: ScreenSaverView, WKNavigationDelegate {
    private var webView: WKWebView?
    private var html: String?
    private var missedBeats = 0

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 5.0

        let bundle = Bundle(for: FlipCalendarView.self)
        if let url = bundle.url(forResource: "index", withExtension: "html") {
            html = try? String(contentsOf: url, encoding: .utf8)
        }
        makeWebView()

        // macOS 14+ keeps legacyScreenSaver alive after the saver stops; quit it cleanly.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(willStop(_:)),
            name: Notification.Name("com.apple.screensaver.willstop"), object: nil)
    }

    private func makeWebView() {
        webView?.removeFromSuperview()
        let config = WKWebViewConfiguration()
        let flag = "window.__SAVER__ = { preview: \(isPreview ? "true" : "false") };"
        config.userContentController.addUserScript(
            WKUserScript(source: flag, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // The saver window is reported as "occluded", so WebKit would freeze the page after ~2 s.
        // Turn off hidden-page throttling/suppression (private settings, used only if present).
        let prefs = config.preferences
        for sel in ["_setHiddenPageDOMTimerThrottlingEnabled:", "_setHiddenPageDOMTimerThrottlingAutoIncreases:",
                    "_setPageVisibilityBasedProcessSuppressionEnabled:"] {
            let s = NSSelectorFromString(sel)
            if prefs.responds(to: s) { prefs.perform(s, with: false as NSNumber) }
        }
        let wv = WKWebView(frame: bounds, configuration: config)
        let occ = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if wv.responds(to: occ) { wv.perform(occ, with: false as NSNumber) }
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = self
        addSubview(wv)
        webView = wv
        missedBeats = 0
        if let html = html {
            // Fonts are embedded in the HTML, so no file access is needed.
            wv.loadHTMLString(html, baseURL: nil)
        }
    }

    // If macOS kills the web content process, the page goes black: rebuild it.
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        makeWebView()
    }

    // Every 5 s check that the page is alive and drawing; rebuild it if not.
    public override func animateOneFrame() {
        guard let wv = webView else { makeWebView(); return }
        wv.evaluateJavaScript("document.getElementById('cal') ? document.getElementById('cal').childElementCount : 0") { [weak self] result, error in
            guard let self = self else { return }
            if error != nil || (result as? Int ?? 0) == 0 {
                self.missedBeats += 1
                if self.missedBeats >= 2 { self.makeWebView() }
            } else {
                self.missedBeats = 0
            }
        }
    }

    @objc private func willStop(_ note: Notification) {
        if !isPreview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { exit(0) }
        }
    }

    public override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
