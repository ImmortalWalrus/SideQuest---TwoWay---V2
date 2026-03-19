import SwiftUI
import WebKit

struct Character3DView: View {
    let characterType: PlayerCharacterType
    var allowsControl: Bool = false
    var autoRotate: Bool = true
    var framing: Character3DFraming = .fullBody
    var modelYawDegrees: Int = 0
    var sceneStyle: Character3DSceneStyle = .standard
    var debugMode: Character3DDebugMode = .beauty
    var isActive: Bool = true

    @State private var isPreviewReady: Bool = false

    var body: some View {
        ZStack {
            Character3DWebView(
                previewRequest: previewRequest,
                isActive: isActive,
                isPreviewReady: $isPreviewReady
            )

            if !isPreviewReady {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.42), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            isPreviewReady = false
        }
        .onChange(of: previewRequest.key) { _, _ in
            isPreviewReady = false
        }
        .animation(.easeOut(duration: 0.18), value: isPreviewReady)
    }

    private var previewRequest: CharacterPreviewRequest {
        CharacterPreviewRequest(
            characterType: characterType,
            allowsControl: allowsControl,
            autoRotate: autoRotate,
            framing: framing,
            modelYawDegrees: modelYawDegrees,
            sceneStyle: sceneStyle,
            debugMode: debugMode
        )
    }
}

private struct Character3DWebView: UIViewRepresentable {
    let previewRequest: CharacterPreviewRequest
    let isActive: Bool
    @Binding var isPreviewReady: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPreviewReady: $isPreviewReady)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: Coordinator.previewStateHandlerName)
        config.userContentController = userContentController
        config.setURLSchemeHandler(CharacterPreviewSchemeHandler(), forURLScheme: CharacterPreviewSchemeHandler.scheme)

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.bind(webView)
        context.coordinator.load(previewRequest)
        context.coordinator.setActive(isActive, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.navigationDelegate = context.coordinator
        context.coordinator.isPreviewReady = $isPreviewReady
        context.coordinator.load(previewRequest)
        context.coordinator.setActive(isActive, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let previewStateHandlerName = "previewState"

        private weak var webView: WKWebView?
        private var requestKey: String?
        private var lastRequest: CharacterPreviewRequest?
        private var currentlyActive: Bool = true
        var isPreviewReady: Binding<Bool>

        init(isPreviewReady: Binding<Bool>) {
            self.isPreviewReady = isPreviewReady
        }

        func bind(_ webView: WKWebView) {
            self.webView = webView
        }

        func setActive(_ active: Bool, in webView: WKWebView) {
            guard active != currentlyActive else { return }
            currentlyActive = active
            let js = active ? "window._resume && window._resume()" : "window._pause && window._pause()"
            webView.evaluateJavaScript(js)
        }

        func load(_ request: CharacterPreviewRequest, forceReload: Bool = false) {
            guard let webView else { return }
            guard forceReload || requestKey != request.key else { return }

            isPreviewReady.wrappedValue = false
            requestKey = request.key
            lastRequest = request

            var components = URLComponents()
            components.scheme = CharacterPreviewSchemeHandler.scheme
            components.host = "preview"
            components.path = "/index.html"
            components.queryItems = [
                URLQueryItem(name: "model", value: request.characterType.fileName),
                URLQueryItem(name: "controls", value: request.allowsControl ? "1" : "0"),
                URLQueryItem(name: "rotate", value: request.autoRotate ? "1" : "0"),
                URLQueryItem(name: "framing", value: request.framing.rawValue),
                URLQueryItem(name: "yaw", value: "\(request.modelYawDegrees)"),
                URLQueryItem(name: "sceneStyle", value: request.sceneStyle.rawValue),
                URLQueryItem(name: "debugMode", value: request.debugMode.rawValue)
            ]

            guard let url = components.url else { return }
            webView.load(URLRequest(url: url))
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                reloadIfNeeded()
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                reloadIfNeeded()
            }
        }

        nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor in
                reloadIfNeeded()
            }
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                handlePreviewStateMessage(message.body)
            }
        }

        @MainActor
        private func handlePreviewStateMessage(_ body: Any) {
            let state: String?
            if let rawState = body as? String {
                state = rawState
            } else if let payload = body as? [String: Any] {
                state = payload["state"] as? String
            } else {
                state = nil
            }

            switch state {
            case "ready":
                isPreviewReady.wrappedValue = true
            case "init":
                isPreviewReady.wrappedValue = false
            default:
                break
            }
        }

        private func reloadIfNeeded() {
            guard let request = lastRequest else { return }
            requestKey = nil
            load(request, forceReload: true)
        }
    }
}

struct CharacterPreviewRequest: Sendable {
    let characterType: PlayerCharacterType
    let allowsControl: Bool
    let autoRotate: Bool
    let framing: Character3DFraming
    let modelYawDegrees: Int
    let sceneStyle: Character3DSceneStyle
    let debugMode: Character3DDebugMode

    var key: String {
        "\(characterType.rawValue)|\(framing.rawValue)|\(modelYawDegrees)|\(sceneStyle.rawValue)|\(debugMode.rawValue)|\(allowsControl)|\(autoRotate)"
    }
}
