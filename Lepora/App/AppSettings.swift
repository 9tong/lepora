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
        case .auto: "智能自动（KaTeX + MathJax）"
        case .katex: "仅 KaTeX"
        case .mathjax: "仅 MathJax"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: "智能自动"
        case .katex: "仅 KaTeX"
        case .mathjax: "仅 MathJax"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: "优先极速 KaTeX，遇到复杂 AMS 环境自动切换离线 MathJax SVG"
        case .katex: "极致轻量与最快渲染速度，适合绝大多数日常公式"
        case .mathjax: "完整 AMS 环境与公式编号支持，纯离线矢量 SVG 输出"
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
        case .docAssetsFolder: "同级 <文档名>.assets/ 目录"
        case .workspaceAssetsFolder: "工作区 assets/ 目录"
        case .originalPath: "保留原始本地路径"
        }
    }

    var shortTitle: String {
        switch self {
        case .docAssetsFolder: "同级资源目录"
        case .workspaceAssetsFolder: "工作区统一目录"
        case .originalPath: "保留原始路径"
        }
    }

    var subtitle: String {
        switch self {
        case .docAssetsFolder: "自动复制到同级 ./<文档名>.assets/ 目录（Typora 默认）"
        case .workspaceAssetsFolder: "统一归档至当前工作区 ./assets/ 目录"
        case .originalPath: "不复制图片文件，直接引用原始本地路径"
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

    /// Controls Liquid Glass translucency-to-frost intensity (0.0 = ultra clear, 1.0 = deep frosted).
    var glassIntensity: Double {
        didSet { defaults.set(glassIntensity, forKey: Keys.glassIntensity) }
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
        static let glassIntensity = "lepora.glassIntensity"
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
        if let storedGlass = defaults.object(forKey: Keys.glassIntensity) as? Double {
            self.glassIntensity = min(1.0, max(0.0, storedGlass))
        } else {
            self.glassIntensity = 0.45
        }
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
