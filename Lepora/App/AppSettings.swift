import SwiftUI
import Observation

enum EditorTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark
    case paper
    case translucent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "纯净浅色"
        case .dark: "深邃暗黑"
        case .paper: "暖意纸张"
        case .translucent: "液态玻璃"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system, .translucent: nil
        case .light, .paper: .light
        case .dark: .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        case .paper: "book.pages"
        case .translucent: "sparkles"
        }
    }
}

enum MathEnginePreference: String, CaseIterable, Identifiable, Sendable {
    case auto
    case katex
    case mathjax

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "自动（KaTeX 主引擎 + MathJax 兜底）"
        case .katex: "仅 KaTeX（极速轻量）"
        case .mathjax: "仅 MathJax（完整 AMS 编号）"
        }
    }
}

enum ImageStorageStrategy: String, CaseIterable, Identifiable, Sendable {
    case docAssetsFolder
    case workspaceAssetsFolder
    case originalPath

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .docAssetsFolder: "复制到同级 <文档名>.assets/ 目录（Typora 默认）"
        case .workspaceAssetsFolder: "统一复制到工作区 assets/ 目录"
        case .originalPath: "直接引用原始本地路径"
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var theme: EditorTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    var lineHeight: Double {
        didSet { defaults.set(lineHeight, forKey: Keys.lineHeight) }
    }

    var maxWidth: Double {
        didSet { defaults.set(maxWidth, forKey: Keys.maxWidth) }
    }

    var mathEngine: MathEnginePreference {
        didSet { defaults.set(mathEngine.rawValue, forKey: Keys.mathEngine) }
    }

    var imageStrategy: ImageStorageStrategy {
        didSet { defaults.set(imageStrategy.rawValue, forKey: Keys.imageStrategy) }
    }

    var autoSave: Bool {
        didSet { defaults.set(autoSave, forKey: Keys.autoSave) }
    }

    var focusMode: Bool {
        didSet { defaults.set(focusMode, forKey: Keys.focusMode) }
    }

    var typewriterMode: Bool {
        didSet { defaults.set(typewriterMode, forKey: Keys.typewriterMode) }
    }

    var showWordCount: Bool {
        didSet { defaults.set(showWordCount, forKey: Keys.showWordCount) }
    }

    private enum Keys {
        static let theme = "lepora.theme"
        static let fontSize = "lepora.fontSize"
        static let lineHeight = "lepora.lineHeight"
        static let maxWidth = "lepora.maxWidth"
        static let mathEngine = "lepora.mathEngine"
        static let imageStrategy = "lepora.imageStrategy"
        static let autoSave = "lepora.autoSave"
        static let focusMode = "lepora.focusMode"
        static let typewriterMode = "lepora.typewriterMode"
        static let showWordCount = "lepora.showWordCount"
    }

    private init() {
        self.theme = EditorTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        let storedSize = defaults.double(forKey: Keys.fontSize)
        self.fontSize = storedSize > 0 ? storedSize : 16
        let storedLineHeight = defaults.double(forKey: Keys.lineHeight)
        self.lineHeight = storedLineHeight > 0 ? storedLineHeight : 1.78
        let storedMaxWidth = defaults.double(forKey: Keys.maxWidth)
        self.maxWidth = storedMaxWidth > 0 ? storedMaxWidth : 780
        self.mathEngine = MathEnginePreference(rawValue: defaults.string(forKey: Keys.mathEngine) ?? "") ?? .auto
        self.imageStrategy = ImageStorageStrategy(rawValue: defaults.string(forKey: Keys.imageStrategy) ?? "") ?? .docAssetsFolder
        self.autoSave = defaults.object(forKey: Keys.autoSave) as? Bool ?? true
        self.focusMode = defaults.bool(forKey: Keys.focusMode)
        self.typewriterMode = defaults.bool(forKey: Keys.typewriterMode)
        self.showWordCount = defaults.object(forKey: Keys.showWordCount) as? Bool ?? true
    }

    var bridgePayload: [String: Any] {
        [
            "theme": theme.rawValue,
            "fontSize": fontSize,
            "lineHeight": lineHeight,
            "maxWidth": maxWidth,
            "mathEngine": mathEngine.rawValue,
            "focusMode": focusMode,
            "typewriterMode": typewriterMode,
        ]
    }
}
