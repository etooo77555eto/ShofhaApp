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

struct WebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    static let homeURL = URL(string: "https://shofha.vercel.app")!
    static let sharedProcessPool = WKProcessPool()

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Persistent store: cookies, cache and site data survive between launches,
        // so repeat opens skip re-downloading what is already on the phone.
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.processPool = WebView.sharedProcessPool

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.078, alpha: 1)
        webView.scrollView.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.078, alpha: 1)
        webView.isOpaque = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: WebView.homeURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView

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
            parent.isLoading = false
            parent.loadError = "تأكد من الإنترنت وحاول مرة ثانية"
        }

        // External schemes (Telegram, WhatsApp, tel, mailto...) open in their apps
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" {
                decisionHandler(.allow)
            } else {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
            }
        }

        // target="_blank" links load inside the same web view instead of dying
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if let scheme = url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
                    if UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    webView.load(navigationAction.request)
                }
            }
            return nil
        }
    }
}
