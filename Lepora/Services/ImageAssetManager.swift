import Foundation
import AppKit

@MainActor
enum ImageAssetManager {
    static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "tif", "bmp", "avif"
    ]

    static func draftAssetsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Lepora/DraftAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saves a copied/dragged/picked local image file according to the user's storage strategy
    /// and returns the Markdown path string to insert.
    static func importImageFile(
        from sourceURL: URL,
        documentURL: URL?,
        workspaceURL: URL?,
        strategy: ImageStorageStrategy
    ) throws -> String {
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()

        if strategy == .originalPath {
            if let docDir = documentURL?.deletingLastPathComponent() {
                return relativePath(from: docDir, to: sourceURL) ?? sourceURL.path
            }
            return sourceURL.path
        }

        let targetDir = destinationDirectory(documentURL: documentURL, workspaceURL: workspaceURL, strategy: strategy)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let cleanStem = sanitizeFilename(sourceURL.deletingPathExtension().lastPathComponent)
        let filename = "\(cleanStem)-\(timestampSuffix()).\(ext)"
        let destURL = targetDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        return markdownPath(for: destURL, documentURL: documentURL)
    }

    /// Saves raw pasted clipboard image data (screenshot, copied web image, etc.)
    static func saveImageData(
        _ data: Data,
        mimeType: String,
        suggestedName: String?,
        documentURL: URL?,
        workspaceURL: URL?,
        strategy: ImageStorageStrategy
    ) throws -> String {
        let ext = extensionForMimeType(mimeType)
        let effectiveStrategy: ImageStorageStrategy = (strategy == .originalPath) ? .docAssetsFolder : strategy
        let targetDir = destinationDirectory(documentURL: documentURL, workspaceURL: workspaceURL, strategy: effectiveStrategy)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let baseName: String
        if let name = suggestedName, !name.isEmpty {
            let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            baseName = sanitizeFilename(stem.isEmpty ? "image" : stem)
        } else {
            baseName = "image"
        }

        let filename = "\(baseName)-\(timestampSuffix()).\(ext)"
        let destURL = targetDir.appendingPathComponent(filename)
        try data.write(to: destURL, options: .atomic)

        return markdownPath(for: destURL, documentURL: documentURL)
    }

    /// Extracts an image directly from NSPasteboard (handles screenshots, TIFF, PNG, copied Finder image files)
    static func importFromPasteboard(
        _ pasteboard: NSPasteboard,
        documentURL: URL?,
        workspaceURL: URL?,
        strategy: ImageStorageStrategy
    ) throws -> (markdownPath: String, alt: String)? {
        // 1. Check copied image file URLs first
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let firstImage = urls.first(where: { supportedImageExtensions.contains($0.pathExtension.lowercased()) }) {
            let path = try importImageFile(
                from: firstImage,
                documentURL: documentURL,
                workspaceURL: workspaceURL,
                strategy: strategy
            )
            return (path, firstImage.deletingPathExtension().lastPathComponent)
        }

        // 2. Check PNG data directly
        if let pngData = pasteboard.data(forType: .png) {
            let path = try saveImageData(
                pngData,
                mimeType: "image/png",
                suggestedName: "image",
                documentURL: documentURL,
                workspaceURL: workspaceURL,
                strategy: strategy
            )
            return (path, "image")
        }

        // 3. Check TIFF / NSImage -> convert cleanly to PNG
        if let tiffData = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            let path = try saveImageData(
                pngData,
                mimeType: "image/png",
                suggestedName: "image",
                documentURL: documentURL,
                workspaceURL: workspaceURL,
                strategy: strategy
            )
            return (path, "image")
        }

        return nil
    }

    static func revealImageInFinder(rawSrc: String, documentURL: URL?) {
        let baseDir = documentURL?.deletingLastPathComponent().path ?? ""
        if let resolved = LocalAssetSchemeHandler.resolveLocalURL(rawPath: rawSrc, baseDir: baseDir),
           FileManager.default.fileExists(atPath: resolved.path) {
            NSWorkspace.shared.activateFileViewerSelecting([resolved])
        }
    }

    private static func destinationDirectory(
        documentURL: URL?,
        workspaceURL: URL?,
        strategy: ImageStorageStrategy
    ) -> URL {
        switch strategy {
        case .docAssetsFolder, .originalPath:
            if let docURL = documentURL {
                let stem = docURL.deletingPathExtension().lastPathComponent
                return docURL.deletingLastPathComponent()
                    .appendingPathComponent("\(stem).assets", isDirectory: true)
            }
            return draftAssetsDirectory()

        case .workspaceAssetsFolder:
            if let wsURL = workspaceURL {
                return wsURL.appendingPathComponent("assets", isDirectory: true)
            }
            if let docURL = documentURL {
                return docURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
            }
            return draftAssetsDirectory()
        }
    }

    private static func markdownPath(for fileURL: URL, documentURL: URL?) -> String {
        if let docDir = documentURL?.deletingLastPathComponent(),
           let rel = relativePath(from: docDir, to: fileURL) {
            return rel
        }
        return fileURL.path
    }

    static func relativePath(from baseDir: URL, to target: URL) -> String? {
        let baseParts = baseDir.standardizedFileURL.pathComponents
        let targetParts = target.standardizedFileURL.pathComponents

        var common = 0
        while common < min(baseParts.count, targetParts.count), baseParts[common] == targetParts[common] {
            common += 1
        }
        guard common > 0 else { return nil }

        let upSteps = Array(repeating: "..", count: baseParts.count - common)
        let downSteps = Array(targetParts[common...])
        return (upSteps + downSteps).joined(separator: "/")
    }

    private static func timestampSuffix() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmmss"
        let rand = String(format: "%04x", UInt16.random(in: 0...UInt16.max))
        return "\(fmt.string(from: Date()))-\(rand)"
    }

    private static func sanitizeFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let str = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return str.isEmpty ? "image" : String(str.prefix(40))
    }

    private static func extensionForMimeType(_ mime: String) -> String {
        switch mime.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/svg+xml": return "svg"
        case "image/heic": return "heic"
        default: return "png"
        }
    }
}
