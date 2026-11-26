import Foundation

struct OutlineItem: Identifiable, Hashable, Sendable {
    let id: String
    let level: Int
    let text: String
    let pos: Int
}

struct DocumentStats: Equatable, Sendable {
    var words: Int = 0
    var characters: Int = 0
    var lines: Int = 1
    var readingMinutes: Int = 1
    var mathCount: Int = 0
    var diagramCount: Int = 0
}

enum EditorMode: String, CaseIterable, Sendable {
    case wysiwyg
    case source

    var label: String {
        switch self {
        case .wysiwyg: "阅读模式"
        case .source: "源码模式"
        }
    }

    var iconName: String {
        switch self {
        case .wysiwyg: "book"
        case .source: "chevron.left.forwardslash.chevron.right"
        }
    }
}
