// `swift scripts/webkit-smoke.swift` (macOS): the built page in a real WKWebView, the way the app hosts it — a
// kudos-editor:// scheme handler serving dist/ with the §11 CSP header, events through the `kudos` message handler,
// calls through callAsyncJavaScript with the same constant body as RichEditorBridgeEncoder.callScript. Prints one
// line per check and exits non-zero on the first failure. Run `npm run bundle` first.
import AppKit
import WebKit

let dist = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist", isDirectory: true)
let csp = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:"
let callScript = """
try {
  if (!window.KudosEditor || typeof window.KudosEditor.call !== "function") {
    return { ok: false, error: { code: "bridge-missing", message: "window.KudosEditor.call is not available" } };
  }
  const value = await window.KudosEditor.call(name, args);
  return { ok: true, value: value == null ? {} : value };
} catch (error) {
  const code = (error && typeof error.code === "string") ? error.code : "js-error";
  const message = (error && typeof error.message === "string") ? error.message : String(error ?? "Unknown error");
  return { ok: false, error: { code, message } };
}
"""

final class Schemes: NSObject, WKURLSchemeHandler {
    var served: [String] = []
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let path = task.request.url?.path ?? ""
        served.append(path)
        let file = dist.appendingPathComponent(String(path.drop { $0 == "/" }))
        let types = ["html": "text/html; charset=utf-8", "js": "application/javascript; charset=utf-8", "css": "text/css; charset=utf-8"]
        guard let data = try? Data(contentsOf: file), let type = types[file.pathExtension] else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": type, "Content-Security-Policy": csp])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

final class Events: NSObject, WKScriptMessageHandler {
    var all: [[String: Any]] = []
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { all.append(body) }
    }
}

@MainActor
func fail(_ what: String) -> Never {
    print("FAIL \(what)")
    exit(1)
}

@MainActor
func check(_ ok: Bool, _ what: String) {
    if !ok { fail(what) }
    print("ok   \(what)")
}

@MainActor
func run() async {
    let schemes = Schemes()
    let events = Events()
    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(schemes, forURLScheme: "kudos-editor")
    config.userContentController.add(events, name: "kudos")
    config.websiteDataStore = .nonPersistent()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
    let web = WKWebView(frame: window.contentView!.bounds, configuration: config)
    window.contentView!.addSubview(web)
    window.orderFrontRegardless() // a CLI window still reads as hidden: the caret tracker's timer fallback covers it
    web.load(URLRequest(url: URL(string: "kudos-editor://editor/editor.html")!))

    func wait(_ what: String, _ seconds: Double = 10, _ until: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !until() {
            if Date() > end { fail("timed out waiting for \(what)") }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    func call(_ name: String, _ args: [String: Any]) async -> [String: Any] {
        do {
            let raw = try await web.callAsyncJavaScript(callScript, arguments: ["name": name, "args": args], in: nil, contentWorld: .page)
            guard let reply = raw as? [String: Any] else { fail("\(name): reply is not an object") }
            if reply["ok"] as? Bool == true { return reply["value"] as? [String: Any] ?? [:] }
            return ["__error": reply["error"] ?? "?"]
        } catch { fail("\(name): \(error)") }
    }

    await wait("ready") { events.all.contains { $0["type"] as? String == "ready" } }
    let ready = events.all.first { $0["type"] as? String == "ready" }!
    check((ready["bundleVersion"] as? String)?.isEmpty == false, "ready, bundle \(ready["bundleVersion"]!)")
    check(Set(schemes.served) == ["/editor.html", "/editor.css", "/editor.js"], "the page loaded only its own three files: \(schemes.served)")

    let conf = await call("configure", ["bridgeVersion": 1, "schemaVersion": 1, "variant": "content", "locale": "en_GB",
        "theme": ["background": "#FFFFFF", "text": "#1E1E1E", "accent": "#821019", "link": "#0B66C2",
                  "fontFamily": "'New York', ui-serif, Georgia, serif", "fontSizePx": 17, "lineHeight": 1.62]])
    check(conf["bridgeVersion"] as? Int == 1, "configure answers bridgeVersion 1")
    _ = await call("setAppearance", ["fontFamily": "-apple-system", "fontSizePx": 19, "lineHeight": 1.6, "contentSizeCategory": "UICTContentSizeCategoryL",
                                     "isAccessibilityCategory": false, "colorScheme": "light", "increaseContrast": false, "boldText": false])
    let source = "<p>Once upon a <em>time</em>.</p>\n<p>The end.</p>\n<table><tr><td>t</td></tr></table>"
    let loaded = await call("load", ["html": source, "revision": 3])
    check(loaded["revision"] as? Int == 3, "load")
    let editable = try? await web.evaluateJavaScript("document.querySelector('.kd-editor').getAttribute('contenteditable')")
    check(editable as? String == "false", "loaded read-only")
    let raw = try? await web.evaluateJavaScript("document.querySelector('.kd-raw')?.getAttribute('aria-label') ?? ''")
    check((raw as? String) == "Table. Edit in HTML view", "the table is a locked chip")
    _ = await call("setMirror", ["enabled": true])
    let activated = await call("activate", ["caret": (source as NSString).range(of: "time").location + 2, "focus": true])
    check(activated["caretFound"] as? Bool == true, "activate finds the caret")
    await wait("a caret rectangle") { events.all.contains { $0["type"] as? String == "caretRect" } }
    let caret = events.all.last { $0["type"] as? String == "caretRect" }!
    check((caret["height"] as? Double ?? Double(caret["height"] as? Int ?? 0)) > 5 && caret["block"] as? Int == 0, "caretRect from real layout: \(caret)")
    let bold = await call("command", ["name": "toggleMark", "attrs": ["mark": "bold"]])
    check(bold["applied"] as? Bool == true, "toggleMark")
    _ = await call("command", ["name": "insertText", "attrs": ["text": "less "]])
    let pasted = await call("command", ["name": "paste", "attrs": ["html": "<p><font color=red>Hi</font> <i>there</i></p>"]])
    check(((pasted["paste"] as? [String: Any])?["words"] as? Int) == 2, "paste through the AO3 pipeline")
    try? await Task.sleep(for: .milliseconds(500))
    check(events.all.contains { $0["type"] as? String == "mirrorBlocks" }, "mirrorBlocks arrive")
    check(events.all.contains { $0["type"] as? String == "edited" }, "edited arrives")
    let frozen = await call("freeze", [:])
    let snap = await call("snapshot", ["caret": true])
    check(snap["revision"] as? Int == frozen["revision"] as? Int, "freeze and snapshot agree on the revision")
    let html = snap["html"] as? String ?? ""
    check(html.hasPrefix("<p>Once upon a <em>ti</em><strong><em>less </em></strong>"), "snapshot: \(html.prefix(90))")
    check(html.hasSuffix("<table><tr><td>t</td></tr></table>"), "the untouched table keeps its source bytes")
    let verify = await call("verifySwitch", ["direction": "richToSource", "html": html])
    check(verify["ok"] as? Bool == true, "verifySwitch passes")
    let bad = await call("load", ["html": 1, "revision": 1])
    check(((bad["__error"] as? [String: Any])?["code"] as? String) == "bad-args", "a rejection reaches native as {code, message}")
    let inline = try? await web.evaluateJavaScript("""
        (() => { const s = document.createElement('script'); s.textContent = 'window.__inlineRan = true'; document.head.appendChild(s); return window.__inlineRan === true; })()
        """)
    check(inline as? Bool == false, "the CSP blocks inline script")
    print("PASS real WebKit (\(events.all.count) events)")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
