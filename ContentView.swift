import SwiftUI
import WebKit
import CoreLocation
#if os(iOS)
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#else
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

struct ContentView: View {
    var body: some View { WebView() }
}

/// Sert les fichiers de l'app (page, JSZip, horaires) sous app://local/...
/// Les horaires mis à jour par l'utilisateur (Application Support) ont priorité sur ceux inclus dans l'app.
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static var updatedGTFS: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gtfs.zip")
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var name = url.lastPathComponent
        if name.isEmpty || name == "local" { name = "index.html" }

        var fileURL: URL?
        var mime = "text/plain"
        switch name {
        case "index.html":
            fileURL = Bundle.main.url(forResource: "index", withExtension: "html"); mime = "text/html"
        case "jszip.min.js":
            fileURL = Bundle.main.url(forResource: "jszip.min", withExtension: "js"); mime = "text/javascript"
        case "gtfs.zip":
            let updated = AppSchemeHandler.updatedGTFS
            fileURL = FileManager.default.fileExists(atPath: updated.path)
                ? updated
                : Bundle.main.url(forResource: "google-transit", withExtension: "zip")
            mime = "application/zip"
        default: break
        }

        if let f = fileURL, let data = try? Data(contentsOf: f) {
            let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
            task.didReceive(resp); task.didReceive(data); task.didFinish()
        } else {
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            task.didReceive(resp); task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct WebView: PlatformViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    private func make(_ context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        cfg.userContentController.add(context.coordinator, name: "haptic")
        cfg.userContentController.add(context.coordinator, name: "live")
        cfg.userContentController.add(context.coordinator, name: "locate")
        for n in ["listen", "listenStop", "speak", "speakStop", "beep"] { cfg.userContentController.add(context.coordinator, name: n) }
        cfg.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "saveGtfs")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        context.coordinator.web = wv
        SpeechManager.shared.web = wv
        #if os(iOS)
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.bounces = false
        wv.isOpaque = false
        wv.underPageBackgroundColor = .systemBackground
        #endif
        wv.load(URLRequest(url: URL(string: "app://local/index.html")!))
        return wv
    }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { make(context) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView { make(context) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    final class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate, CLLocationManagerDelegate {
        weak var web: WKWebView?
        private let lm = CLLocationManager()
        private var wantsLocation = false

        override init() {
            super.init()
            lm.delegate = self
            lm.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        }

        // Position demandée par la page : arrêts les plus proches
        private func requestLocation() {
            wantsLocation = true
            switch lm.authorizationStatus {
            case .notDetermined: lm.requestWhenInUseAuthorization()
            case .denied, .restricted: failLocation()
            default: lm.requestLocation()
            }
        }
        private func failLocation() {
            wantsLocation = false
            web?.evaluateJavaScript("window.onLocErr && window.onLocErr()", completionHandler: nil)
        }
        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard wantsLocation else { return }
            switch manager.authorizationStatus {
            case .notDetermined: break
            case .denied, .restricted: failLocation()
            default: manager.requestLocation()
            }
        }
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard wantsLocation, let l = locations.last else { return }
            wantsLocation = false
            web?.evaluateJavaScript("window.onLoc && window.onLoc(\(l.coordinate.latitude), \(l.coordinate.longitude))", completionHandler: nil)
        }
        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { failLocation() }
        #if os(iOS)
        private let haptic = UIImpactFeedbackGenerator(style: .light)
        #endif

        // Petite vibration au toucher d'une ligne
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "live" { LiveActivityManager.shared.start(message.body); return }
            if message.name == "locate" { requestLocation(); return }
            switch message.name {
            case "listen": SpeechManager.shared.listen(); return
            case "listenStop": SpeechManager.shared.finish(); return
            case "speak": if let t = message.body as? String { SpeechManager.shared.speak(t) }; return
            case "speakStop": SpeechManager.shared.stopSpeaking(); return
            case "beep": SpeechManager.shared.beep(up: (message.body as? Int ?? 1) == 1); return
            default: break
            }
            #if os(iOS)
            haptic.impactOccurred()
            #else
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            #endif
        }

        // Mise à jour annuelle : la page envoie le nouveau fichier .zip (base64), on le garde sur l'iPhone
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard let b64 = message.body as? String, let data = Data(base64Encoded: b64) else {
                replyHandler(nil, "Fichier invalide"); return
            }
            do {
                try data.write(to: AppSchemeHandler.updatedGTFS, options: .atomic)
                replyHandler("ok", nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }
        }

        // Les liens externes (ex. téléchargement des horaires) s'ouvrent dans Safari
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, url.scheme?.hasPrefix("http") == true,
               action.navigationType == .linkActivated {
                #if os(iOS)
                UIApplication.shared.open(url)
                #else
                NSWorkspace.shared.open(url)
                #endif
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
