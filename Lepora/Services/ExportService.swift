import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

@MainActor
final class ExportService {
    private static var activePDFExporter: PDFExportRunner?

    static func exportStandaloneHTML(
        title: String,
        bodyHTML: String,
        editorCSS: String,
        baseDirPath: String,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "导出独立 HTML"
        panel.nameFieldStringValue = "\(title).html"
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destURL = panel.url else {
            completion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
            return
        }

        let standaloneHTML = buildStandaloneHTML(
            title: title,
            bodyHTML: bodyHTML,
            editorCSS: editorCSS,
            baseDirPath: baseDirPath,
            forPrint: false
        )

        do {
            try standaloneHTML.write(to: destURL, atomically: true, encoding: .utf8)
            completion(.success(destURL))
        } catch {
            completion(.failure(error))
        }
    }

    static func exportPDF(
        title: String,
        bodyHTML: String,
        editorCSS: String,
        baseDirPath: String,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "导出 PDF 文档"
        panel.nameFieldStringValue = "\(title).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destURL = panel.url else {
            completion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
            return
        }

        let html = buildStandaloneHTML(
            title: title,
            bodyHTML: bodyHTML,
            editorCSS: editorCSS,
            baseDirPath: baseDirPath,
            forPrint: true
        )

        let runner = PDFExportRunner()
        activePDFExporter = runner
        runner.export(html: html, to: destURL) { result in
            activePDFExporter = nil
            completion(result)
        }
    }

    private static func buildStandaloneHTML(
        title: String,
        bodyHTML: String,
        editorCSS: String,
        baseDirPath: String,
        forPrint: Bool
    ) -> String {
        let inlinedCSS = inlineKaTeXFontsInCSS(editorCSS)
        let inlinedBody = inlineLocalImagesInHTML(bodyHTML, baseDirPath: baseDirPath)
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let exportOverrides = """
        html, body {
          overflow: visible !important;
          height: auto !important;
          background: \(forPrint ? "#ffffff" : "var(--bg-canvas)") !important;
          \(forPrint ? "color-scheme: light !important; --bg-canvas: #ffffff; --text-primary: #1d2129; --heading-color: #0f1419;" : "")
        }
        .lepora-prose {
          padding-block: \(forPrint ? "24px 32px" : "56px 96px") !important;
          max-inline-size: \(forPrint ? "740px" : "820px") !important;
          margin-inline: auto;
        }
        """

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <meta name="color-scheme" content="\(forPrint ? "light" : "light dark")" />
          <title>\(escapedTitle)</title>
          <style>
          \(inlinedCSS)
          \(exportOverrides)
          </style>
        </head>
        <body data-theme="\(forPrint ? "light" : "system")">
          <article class="lepora-prose">
            \(inlinedBody)
          </article>
        </body>
        </html>
        """
    }

    /// Replaces `lepora-app://editor/assets/KaTeX_*.woff2` URLs in CSS with inline base64 font data URIs
    private static func inlineKaTeXFontsInCSS(_ css: String) -> String {
        guard let assetsDir = Bundle.main.resourceURL?
            .appendingPathComponent("EditorBundle/assets", isDirectory: true) else {
            return css
        }

        let pattern = #"url\(["']?([^"')]+\.(?:woff2|woff|ttf))["']?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return css
        }

        let nsCSS = css as NSString
        let matches = regex.matches(in: css, range: NSRange(location: 0, length: nsCSS.length))
        var result = css

        for match in matches.reversed() {
            let urlRange = match.range(at: 1)
            let rawRef = nsCSS.substring(with: urlRange)
            let filename = URL(fileURLWithPath: rawRef).lastPathComponent
            let fontURL = assetsDir.appendingPathComponent(filename)
            guard let fontData = try? Data(contentsOf: fontURL) else { continue }
            let mime = BundleSchemeHandler.mimeType(for: fontURL.pathExtension)
            let dataURI = "url(\"data:\(mime);base64,\(fontData.base64EncodedString())\")"
            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: dataURI)
            }
        }
        return result
    }

    /// Replaces `lepora-local://asset?...` image src attributes with embedded base64 data URIs
    private static func inlineLocalImagesInHTML(_ html: String, baseDirPath: String) -> String {
        let pattern = #"src="lepora-local://asset\?([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var result = html

        for match in matches.reversed() {
            let queryStr = nsHTML.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard let comps = URLComponents(string: "lepora-local://asset?\(queryStr)") else { continue }
            let items = comps.queryItems ?? []
            let rawPath = items.first(where: { $0.name == "path" })?.value ?? ""
            let base = items.first(where: { $0.name == "base" })?.value ?? baseDirPath

            guard let fileURL = LocalAssetSchemeHandler.resolveLocalURL(rawPath: rawPath, baseDir: base),
                  let data = try? Data(contentsOf: fileURL) else {
                continue
            }
            let mime = BundleSchemeHandler.mimeType(for: fileURL.pathExtension)
            let replacement = "src=\"data:\(mime);base64,\(data.base64EncodedString())\""
            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: replacement)
            }
        }
        return result
    }
}

@MainActor
private final class PDFExportRunner: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var destinationURL: URL?
    private var completion: (@MainActor (Result<URL, Error>) -> Void)?

    func export(html: String, to url: URL, completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        self.destinationURL = url
        self.completion = completion

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv
        wv.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait briefly for web fonts & SVG layout to stabilize
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            let pdfConfig = WKPDFConfiguration()
            webView.createPDF(configuration: pdfConfig) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, let dest = self.destinationURL else { return }
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: dest, options: .atomic)
                            self.completion?(.success(dest))
                        } catch {
                            self.completion?(.failure(error))
                        }
                    case .failure(let error):
                        self.completion?(.failure(error))
                    }
                    self.webView = nil
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        completion?(.failure(error))
        self.webView = nil
    }
}
