import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serves bundled offline editor resources under `lepora-app://editor/...`
/// so ES modules, KaTeX woff2 fonts, MathJax chunks, and Mermaid load cleanly with zero network traffic.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let bundleRootURL: URL?

    override init() {
        self.bundleRootURL = Bundle.main.resourceURL?.appendingPathComponent("EditorBundle", isDirectory: true)
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let root = bundleRootURL else {
            urlSchemeTask.didFailWithError(NSError(domain: "LeporaScheme", code: 404))
            return
        }

        var relativePath = url.path
        if relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        if relativePath.isEmpty {
            relativePath = "index.html"
        }

        let fileURL = root.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "LeporaScheme", code: 404))
            return
        }

        let mimeType = Self.mimeType(for: fileURL.pathExtension)
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]

        if let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } else {
            urlSchemeTask.didFailWithError(NSError(domain: "LeporaScheme", code: 500))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        default:
            if let utType = UTType(filenameExtension: ext), let mime = utType.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }
    }
}

/// Safely serves local/relative Markdown images under `lepora-local://asset?path=...&base=...`
final class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(NSError(domain: "LeporaLocalAsset", code: 400))
            return
        }

        let queryItems = components.queryItems ?? []
        let rawPath = queryItems.first(where: { $0.name == "path" })?.value ?? ""
        let baseDir = queryItems.first(where: { $0.name == "base" })?.value ?? ""

        guard let resolvedURL = Self.resolveLocalURL(rawPath: rawPath, baseDir: baseDir),
              let data = try? Data(contentsOf: resolvedURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "LeporaLocalAsset", code: 404))
            return
        }

        let mimeType = BundleSchemeHandler.mimeType(for: resolvedURL.pathExtension)
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    static func resolveLocalURL(rawPath: String, baseDir: String) -> URL? {
        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
        let trimmed = decodedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://"), let fileURL = URL(string: trimmed) {
            return fileURL
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }
        if trimmed.hasPrefix("~/") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        if !baseDir.isEmpty {
            let baseURL = URL(fileURLWithPath: baseDir, isDirectory: true)
            return baseURL.appendingPathComponent(trimmed).standardizedFileURL
        }

        // Fallback to temporary draft assets directory
        let draftDir = ImageAssetManager.draftAssetsDirectory()
        return draftDir.appendingPathComponent(trimmed).standardizedFileURL
    }
}
