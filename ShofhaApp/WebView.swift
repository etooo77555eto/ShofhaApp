import SwiftUI
import WebKit

struct ContentView: View {
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.043, blue: 0.078)
                .ignoresSafeArea()

            WebView(isLoading: $isLoading, loadError: $loadError)
                .id(reloadToken)
                .ignoresSafeArea()

            if isLoading {
                VStack(spacing: 16) {
                    Text("شوفها")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 0.486, green: 0.361, blue: 1.0),
                                                    Color(red: 0.0, green: 0.761, blue: 1.0)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                }
            }

            if let err = loadError {
                VStack(spacing: 14) {
                    Text("📡")
                        .font(.system(size: 44))
                    Text("ماكو اتصال")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("حاول مرة ثانية") {
                        loadError = nil
                        isLoading = true
                        reloadToken += 1
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [Color(red: 0.486, green: 0.361, blue: 1.0),
                                                Color(red: 0.0, green: 0.761, blue: 1.0)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
    }
}

// Ad / pop-up networks used by the video hosts' players. Anything served
// from these domains is blocked before it loads, and any navigation to
// them is cancelled.
enum AdBlocker {
    static let domains: [String] = [
        "popads.net", "popcash.net", "poponclick.com", "onclickads.net",
        "onclickperformance.com", "onadclick.com",
        "exosrv.com", "exdynsrv.com", "exoclick.com",
        "adcash.com", "propellerads.com", "hilltopads.com",
        "trafficjunky.com", "juicyads.com", "a-ads.com", "bidvertiser.com",
        "mgid.com", "adskeeper.com", "tsyndicate.com",
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "amazon-adsystem.com", "adsterra.com", "highperformanceformat.com",
        "profitablecpmrate.com", "effectivecpmcontent.com",
        "clickadu.com", "monetag.com", "evadav.com", "galaksion.com",
        "rollerads.com", "zeydoo.com"
    ]

    static func isAdHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return domains.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    // Safari-style content rule list JSON: block every request whose
    // domain is one of the ad networks above.
    static func ruleListJSON() -> String {
        let rules: [[String: Any]] = [[
            "trigger": ["url-filter": ".*",
                        "if-domain": domains.map { "*" + $0 }],
            "action": ["type": "block"]
        ]]
        if let data = try? JSONSerialization.data(withJSONObject: rules),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    // Inside embedded players only: window.open is the ad pop-up door.
    // The main page keeps window.open (the site itself uses it).
    static let popupKillerJS = """
    (function() {
      if (window === window.top) { return; }
      try { window.open = function() { return null; }; } catch (e) {}
    })();
    """
}

struct WebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    static let homeURL = URL(string: "https://shofha.vercel.app")!
    static let homeHost = "shofha.vercel.app"
    static let sharedProcessPool = WKProcessPool()

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Persistent store: cookies, cache and site data survive between launches,
        // so repeat opens skip re-downloading what is already on the phone.
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.processPool = WebView.sharedProcessPool

        // Kill pop-up calls inside embedded players from the very start.
        let script = WKUserScript(source: AdBlocker.popupKillerJS,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.078, alpha: 1)
        webView.scrollView.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.078, alpha: 1)
        webView.isOpaque = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        // Compile the ad-block rule list, attach it, then load the site.
        // If compilation ever fails the site still loads, just unfiltered.
        if let store = WKContentRuleListStore.default() {
            store.compileContentRuleList(forIdentifier: "shofha-adblock",
                                         encodedContentRuleList: AdBlocker.ruleListJSON()) { list, _ in
                DispatchQueue.main.async {
                    if let list = list {
                        config.userContentController.add(list)
                    }
                    webView.load(URLRequest(url: WebView.homeURL))
                }
            }
        } else {
            webView.load(URLRequest(url: WebView.homeURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView
        // Foreign hosts the user deliberately opened from the site itself
        // (e.g. a download-server page): their in-flow taps stay allowed.
        var approvedHosts = Set<String>()
        // Short window after opening such a page, so its redirect chain
        // can finish without being mistaken for an ad hijack.
        var approvedUntil = Date.distantPast

        init(parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.loadError = "تأكد من الإنترنت وحاول مرة ثانية"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Cancelled navigations (blocked ads) also land here — stay silent.
            if (error as NSError).code == NSURLErrorCancelled { return }
            parent.isLoading = false
            parent.loadError = "تأكد من الإنترنت وحاول مرة ثانية"
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            // External schemes (Telegram, WhatsApp, tel, mailto...) open in their apps
            guard scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" else {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            let host = url.host?.lowercased()
            // Nothing from an ad network may navigate anywhere, in any frame.
            if AdBlocker.isAdHost(host) {
                decisionHandler(.cancel)
                return
            }
            // New-window requests are decided by createWebViewWith below.
            guard let target = navigationAction.targetFrame else {
                decisionHandler(.allow)
                return
            }
            if target.isMainFrame, let h = host, h != WebView.homeHost {
                // The top page may only leave the site through a flow the
                // user opened himself (download page) — anything else is a
                // player trying to hijack the screen with an ad page.
                let currentHost = webView.url?.host?.lowercased()
                let inApprovedFlow = approvedHosts.contains(h)
                    || Date() < approvedUntil
                    || (currentHost != nil && currentHost != WebView.homeHost)
                decisionHandler(inApprovedFlow ? .allow : .cancel)
                return
            }
            decisionHandler(.allow)
        }

        // Pop-up windows: the video players fire their ads through these.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if let scheme = url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
                return nil
            }
            let host = url.host?.lowercased()
            if AdBlocker.isAdHost(host) { return nil }
            // Only pop-ups the site's own page asked for (download / social
            // buttons) are honoured; player iframes' pop-ups die silently.
            if navigationAction.sourceFrame.isMainFrame {
                if let h = host, h == "t.me" || h == "telegram.me" || h.hasSuffix(".t.me") {
                    UIApplication.shared.open(url)
                    return nil
                }
                if let h = host {
                    approvedHosts.insert(h)
                    approvedUntil = Date().addingTimeInterval(30)
                }
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
