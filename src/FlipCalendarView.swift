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
        // The saver's window lives in legacyScreenSaver and AppKit reports it as occluded,
        // so WebKit suspends the page ~2 s after load and the screen goes black.
        // Turn off WebKit's visibility-based throttling (private keys, guarded).
        for setter in ["_setPageVisibilityBasedProcessSuppressionEnabled:",
                       "_setHiddenPageDOMTimerThrottlingEnabled:",
                       "_setHiddenPageDOMTimerThrottlingAutoIncreases:"] {
            Self.callBoolSetter(config.preferences, setter, false)
        }
        let flag = "window.__SAVER__ = { preview: \(isPreview ? "true" : "false") };"
        config.userContentController.addUserScript(
            WKUserScript(source: flag, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let wv = WKWebView(frame: bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        Self.callBoolSetter(wv, "_setWindowOcclusionDetectionEnabled:", false)
        wv.navigationDelegate = self
        addSubview(wv)
        webView = wv
        missedBeats = 0
        if let html = html {
            // Fonts are embedded in the HTML, so no file access is needed.
            wv.loadHTMLString(html, baseURL: nil)
        }
    }

    /// Calls a private `-(void)setX:(BOOL)` method if it exists (no-op otherwise).
    private static func callBoolSetter(_ obj: NSObject, _ name: String, _ value: Bool) {
        let sel = Selector(name)
        guard obj.responds(to: sel), let imp = obj.method(for: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(imp, to: Fn.self)(obj, sel, value)
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
