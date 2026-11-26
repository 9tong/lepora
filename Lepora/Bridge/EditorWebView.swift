import SwiftUI
import WebKit
import AppKit

/// Custom WKWebView supporting native transparent vibrancy, macOS drag-and-drop for images & Markdown files,
/// and direct NSPasteboard image interception (screenshots, copied Finder images).
final class LeporaWKWebView: WKWebView {
    var onDroppedImageURLs: (([URL]) -> Void)?
    var onDroppedMarkdownURL: ((URL) -> Void)?
    var onPasteboardImageTriggered: (() -> Bool)?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Intercept ⌘V when pasteboard holds an image (screenshot / copied Finder image file)
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            if let handled = onPasteboardImageTriggered?(), handled {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let urls = extractFileURLs(from: sender), !urls.isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = extractFileURLs(from: sender), !urls.isEmpty else {
            return super.performDragOperation(sender)
        }

        let imageURLs = urls.filter {
            ImageAssetManager.supportedImageExtensions.contains($0.pathExtension.lowercased())
        }
        if !imageURLs.isEmpty {
            onDroppedImageURLs?(imageURLs)
            return true
        }

        if let first = urls.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir),
               isDir.boolValue || FileTreeNode.supportedExtensions.contains(first.pathExtension.lowercased()) {
                onDroppedMarkdownURL?(first)
                return true
            }
        }

        return super.performDragOperation(sender)
    }

    private func extractFileURLs(from info: any NSDraggingInfo) -> [URL]? {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}

@MainActor
final class EditorBridgeController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var webView: LeporaWKWebView?
    unowned let session: DocumentSession
    let settings: AppSettings

    private var isEditorReady = false
    private var pendingLoad: (markdown: String, baseDirPath: String)?

    init(session: DocumentSession, settings: AppSettings) {
        self.session = session
        self.settings = settings
        super.init()
    }

    // MARK: - JS -> Swift Messages

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            isEditorReady = true
            applyPreferences(settings.bridgePayload)
            if let pending = pendingLoad {
                pendingLoad = nil
                loadDocument(markdown: pending.markdown, baseDirPath: pending.baseDirPath)
            } else {
                loadDocument(markdown: session.markdown, baseDirPath: session.baseDirectoryPath)
            }

        case "contentChanged":
            if let md = dict["markdown"] as? String {
                session.handleEditorContentChanged(md)
            }

        case "statsChanged":
            if let statsDict = dict["stats"] as? [String: Any] {
                session.stats = DocumentStats(
                    words: statsDict["words"] as? Int ?? 0,
                    characters: statsDict["characters"] as? Int ?? 0,
                    lines: statsDict["lines"] as? Int ?? 1,
                    readingMinutes: statsDict["readingMinutes"] as? Int ?? 1,
                    mathCount: statsDict["mathCount"] as? Int ?? 0,
                    diagramCount: statsDict["diagramCount"] as? Int ?? 0
                )
            }

        case "outlineChanged":
            if let items = dict["outline"] as? [[String: Any]] {
                session.outline = items.compactMap { entry in
                    guard let id = entry["id"] as? String,
                          let level = entry["level"] as? Int,
                          let text = entry["text"] as? String,
                          let pos = entry["pos"] as? Int else { return nil }
                    return OutlineItem(id: id, level: level, text: text, pos: pos)
                }
            }

        case "activeHeadingChanged":
            if let id = dict["headingId"] as? String {
                session.activeHeadingId = id
            }

        case "typingActivity":
            session.registerTypingActivity()

        case "modeChanged":
            if let modeStr = dict["mode"] as? String, let mode = EditorMode(rawValue: modeStr) {
                session.editorMode = mode
            }

        case "pastedImageData":
            if let base64 = dict["base64"] as? String,
               let data = Data(base64Encoded: base64) {
                let mime = dict["mimeType"] as? String ?? "image/png"
                let fileName = dict["fileName"] as? String
                session.insertPastedImageData(data, mimeType: mime, fileName: fileName)
            }

        case "revealImage":
            if let src = dict["src"] as? String {
                ImageAssetManager.revealImageInFinder(rawSrc: src, documentURL: session.fileURL)
            }

        case "openExternalLink":
            if let href = dict["href"] as? String, let url = URL(string: href) {
                NSWorkspace.shared.open(url)
            }

        default:
            break
        }
    }

    // MARK: - Swift -> JS Commands

    private func jsonLiteral(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let str = String(data: data, encoding: .utf8),
              str.count >= 2 else {
            return "null"
        }
        return String(str.dropFirst().dropLast())
    }

    private func eval(_ js: String) {
        // Always conclude with a JSON-serializable primitive (`true`) so WKWebView never fails
        // with WKError.javaScriptResultTypeIsUnsupported on void/Promise/non-serializable results.
        let wrapped = "(function(){ \(js) })(); true;"
        webView?.evaluateJavaScript(wrapped) { [weak session] _, error in
            if let error {
                Task { @MainActor in
                    session?.showToast("编辑器执行异常：\(error.localizedDescription)")
                }
            }
        }
    }

    func loadDocument(markdown: String, baseDirPath: String) {
        guard isEditorReady else {
            pendingLoad = (markdown, baseDirPath)
            return
        }
        eval("window.LeporaBridge?.loadDocument(\(jsonLiteral(markdown)), \(jsonLiteral(baseDirPath)));")
    }

    func setMode(_ mode: EditorMode) {
        guard isEditorReady, let webView else { return }
        let modeValue = mode.rawValue
        Task { @MainActor [weak session, weak webView] in
            guard let webView else { return }
            do {
                _ = try await webView.callAsyncJavaScript(
                    "if (window.LeporaBridge) { await window.LeporaBridge.setMode(mode); } return true;",
                    arguments: ["mode": modeValue],
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                session?.showToast("切换模式失败：\(error.localizedDescription)")
            }
        }
    }

    func applyPreferences(_ payload: [String: Any]) {
        guard isEditorReady else { return }
        eval("window.LeporaBridge?.applyPreferences(\(jsonLiteral(payload)));")
    }

    func insertImage(relativePath: String, alt: String) {
        guard isEditorReady else { return }
        eval("window.LeporaBridge?.insertImage(\(jsonLiteral(relativePath)), \(jsonLiteral(alt)));")
    }

    func execCommand(_ cmd: String, arg: String? = nil) {
        guard isEditorReady else { return }
        if let arg {
            eval("window.LeporaBridge?.execCommand(\(jsonLiteral(cmd)), \(jsonLiteral(arg)));")
        } else {
            eval("window.LeporaBridge?.execCommand(\(jsonLiteral(cmd)));")
        }
    }

    func scrollToPos(_ pos: Int) {
        guard isEditorReady else { return }
        eval("window.LeporaBridge?.scrollToPos(\(pos));")
    }

    func clearFind() {
        guard isEditorReady else { return }
        eval("window.LeporaBridge?.clearFind();")
    }

    func fetchMarkdown() async -> String? {
        guard isEditorReady, let webView else { return nil }
        return try? await webView.evaluateJavaScript("window.LeporaBridge?.getMarkdown() ?? ''") as? String
    }

    func find(query: String, caseSensitive: Bool, direction: String) async -> (count: Int, current: Int)? {
        guard isEditorReady, let webView else { return nil }
        let js = "window.LeporaBridge?.find(\(jsonLiteral(query)), \(caseSensitive ? "true" : "false"), \(jsonLiteral(direction))) ?? null"
        guard let dict = try? await webView.evaluateJavaScript(js) as? [String: Any] else { return nil }
        return (dict["count"] as? Int ?? 0, dict["current"] as? Int ?? 0)
    }

    func replaceCurrent(query: String, replacement: String) async -> (count: Int, current: Int)? {
        guard isEditorReady, let webView else { return nil }
        let js = "window.LeporaBridge?.replaceCurrent(\(jsonLiteral(query)), \(jsonLiteral(replacement))) ?? null"
        guard let dict = try? await webView.evaluateJavaScript(js) as? [String: Any] else { return nil }
        return (dict["count"] as? Int ?? 0, dict["current"] as? Int ?? 0)
    }

    func replaceAll(query: String, replacement: String) async -> (count: Int, current: Int)? {
        guard isEditorReady, let webView else { return nil }
        let js = "window.LeporaBridge?.replaceAll(\(jsonLiteral(query)), \(jsonLiteral(replacement))) ?? null"
        guard let dict = try? await webView.evaluateJavaScript(js) as? [String: Any] else { return nil }
        return (dict["count"] as? Int ?? 0, dict["current"] as? Int ?? 0)
    }

    func fetchExportData() async -> (html: String, css: String)? {
        guard isEditorReady, let webView else { return nil }
        guard let dict = try? await webView.evaluateJavaScript("window.LeporaBridge?.getExportData() ?? null") as? [String: Any],
              let html = dict["html"] as? String,
              let css = dict["css"] as? String else {
            return nil
        }
        return (html, css)
    }

    // Intercept Finder drag-and-drop file URLs (which WKContentView tries to navigate to) and external links
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "lepora-app" || url.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL {
            if ImageAssetManager.supportedImageExtensions.contains(url.pathExtension.lowercased()) {
                session.insertImageFile(url)
            } else {
                session.openURL(url)
            }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}

struct EditorWebView: NSViewRepresentable {
    let session: DocumentSession
    let settings: AppSettings

    func makeCoordinator() -> EditorBridgeController {
        let controller = EditorBridgeController(session: session, settings: settings)
        session.bridgeController = controller
        return controller
    }

    func makeNSView(context: Context) -> LeporaWKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: "lepora-app")
        config.setURLSchemeHandler(LocalAssetSchemeHandler(), forURLScheme: "lepora-local")
        config.userContentController.add(context.coordinator, name: "lepora")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = LeporaWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.webView = webView

        webView.onDroppedImageURLs = { [weak session] urls in
            for url in urls {
                session?.insertImageFile(url)
            }
        }

        webView.onDroppedMarkdownURL = { [weak session] url in
            session?.openURL(url)
        }

        webView.onPasteboardImageTriggered = { [weak session, weak settings] in
            guard let session, let settings else { return false }
            let pb = NSPasteboard.general
            // Only intercept if pasteboard has actual image data or copied image files (and NOT plain text!)
            let hasPlainText = pb.string(forType: .string) != nil
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
               urls.contains(where: { ImageAssetManager.supportedImageExtensions.contains($0.pathExtension.lowercased()) }) {
                if let imported = try? ImageAssetManager.importFromPasteboard(
                    pb,
                    documentURL: session.fileURL,
                    workspaceURL: session.workspaceURL,
                    strategy: settings.imageStrategy
                ) {
                    session.bridgeController?.insertImage(relativePath: imported.markdownPath, alt: imported.alt)
                    session.showToast("已粘贴并保存图片")
                    return true
                }
            }
            if !hasPlainText, (pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil) {
                if let imported = try? ImageAssetManager.importFromPasteboard(
                    pb,
                    documentURL: session.fileURL,
                    workspaceURL: session.workspaceURL,
                    strategy: settings.imageStrategy
                ) {
                    session.bridgeController?.insertImage(relativePath: imported.markdownPath, alt: imported.alt)
                    session.showToast("已粘贴并保存图片")
                    return true
                }
            }
            return false
        }

        if let url = URL(string: "lepora-app://editor/index.html") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: LeporaWKWebView, context: Context) {
        // Trigger reactive preference synchronization whenever observed settings change
        context.coordinator.applyPreferences(settings.bridgePayload)
    }
}
