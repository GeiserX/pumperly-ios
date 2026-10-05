import SwiftUI
import WebKit

/// Hosts the model's single WKWebView, so SwiftUI updates never recreate it.
struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
