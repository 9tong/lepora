import Foundation

struct FileTreeNode: Identifiable, Hashable, Sendable {
    let id: URL
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileTreeNode]?

    static let supportedExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "rmd", "qmd", "txt"
    ]

    static let ignoredNames: Set<String> = [
        ".git", ".DS_Store", "node_modules", ".svn", ".hg", "build", ".build",
        "DerivedData", "dist", "target", ".venv", "venv", "__pycache__", ".cache"
    ]

    static func scan(directory: URL, maxDepth: Int = 5) -> [FileTreeNode] {
        guard maxDepth > 0 else { return [] }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var folders: [FileTreeNode] = []
        var files: [FileTreeNode] = []

        for url in urls {
            let name = url.lastPathComponent
            if ignoredNames.contains(name) || name.hasSuffix(".assets") {
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDir = values?.isDirectory ?? false
            let isPackage = values?.isPackage ?? false

            if isDir && !isPackage {
                let kids = scan(directory: url, maxDepth: maxDepth - 1)
                folders.append(
                    FileTreeNode(id: url, name: name, url: url, isDirectory: true, children: kids)
                )
            } else if !isDir {
                let ext = url.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    files.append(
                        FileTreeNode(id: url, name: name, url: url, isDirectory: false, children: nil)
                    )
                }
            }
        }

        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folders + files
    }

    static func flattenMarkdownFiles(from nodes: [FileTreeNode]) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for node in nodes {
            if node.isDirectory {
                if let children = node.children {
                    result.append(contentsOf: flattenMarkdownFiles(from: children))
                }
            } else {
                result.append(node)
            }
        }
        return result
    }
}
