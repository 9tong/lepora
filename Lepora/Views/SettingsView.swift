import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    private var isDefaultTypography: Bool {
        Int(settings.fontSize) == 16 &&
        abs(settings.lineHeight - 1.78) < 0.01 &&
        Int(settings.maxWidth) == 780
    }

    var body: some View {
        TabView {
            Tab("外观", systemImage: "paintpalette") {
                appearanceTab
            }

            Tab("排版", systemImage: "textformat") {
                typographyTab
            }

            Tab("渲染", systemImage: "function") {
                renderingTab
            }

            Tab("文件", systemImage: "folder") {
                filesTab
            }
        }
        .frame(width: 540, height: 430)
        .preferredColorScheme(settings.theme.preferredColorScheme)
    }

    // MARK: - 1. 外观

    private var appearanceTab: some View {
        Form {
            Section {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                    spacing: 10
                ) {
                    ForEach(EditorTheme.allCases) { theme in
                        ThemeSwatchCard(
                            theme: theme,
                            isSelected: settings.theme == theme
                        ) {
                            withAnimation(.snappy(duration: 0.2)) {
                                settings.theme = theme
                            }
                        }
                    }
                }
                .padding(.vertical, 6)

                if settings.theme == .translucent {
                    HStack(spacing: 12) {
                        Text("玻璃幅度")
                            .font(.system(size: 13))
                            .frame(width: 64, alignment: .leading)

                        Image(systemName: "drop")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Slider(value: $settings.glassIntensity, in: 0...1)

                        Image(systemName: "aqi.medium")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Text("\(Int((settings.glassIntensity * 100).rounded()))%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("画布主题")
            }

            Section {
                settingToggleRow(
                    title: "漂浮羽毛",
                    subtitle: "在右下角显示轻盈漂浮羽毛，点击可查看文档统计",
                    isOn: $settings.showWordCount
                )
                settingToggleRow(
                    title: "专注模式",
                    subtitle: "柔化非当前段落，聚焦正在书写的内容",
                    isOn: $settings.focusMode
                )
                settingToggleRow(
                    title: "打字机模式",
                    subtitle: "始终将当前编辑行柔和保持在窗口中央",
                    isOn: $settings.typewriterMode
                )
            } header: {
                Text("书写氛围")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 2. 排版

    private var typographyTab: some View {
        Form {
            Section {
                typographySliderRow(
                    title: "正文字号",
                    valueText: "\(Int(settings.fontSize)) pt",
                    value: $settings.fontSize,
                    range: 12...24,
                    step: 1
                )

                typographySliderRow(
                    title: "行高倍数",
                    valueText: String(format: "%.2f", settings.lineHeight),
                    value: $settings.lineHeight,
                    range: 1.3...2.2,
                    step: 0.05
                )

                typographySliderRow(
                    title: "阅读宽度",
                    valueText: "\(Int(settings.maxWidth)) px",
                    value: $settings.maxWidth,
                    range: 560...1100,
                    step: 20
                )
            } header: {
                HStack {
                    Text("版面参数")
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            settings.fontSize = 16
                            settings.lineHeight = 1.78
                            settings.maxWidth = 780
                        }
                    } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isDefaultTypography ? Color.secondary.opacity(0.45) : Color.accentColor)
                    .disabled(isDefaultTypography)
                }
            }

            Section("实时预览") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("轻盈如羽，专注文字本身")
                        .font(.system(size: min(17, max(12.5, settings.fontSize * 0.92)), weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Lepora 将 Markdown 写作化繁为简，兼顾即时所见即所得与优雅排版节奏，让长文、公式与图表都自然呼吸。")
                        .font(.system(size: min(15, max(11, settings.fontSize * 0.78))))
                        .lineSpacing(max(2, (settings.lineHeight - 1.15) * 8))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 3. 渲染

    private var renderingTab: some View {
        Form {
            Section("LaTeX 公式引擎") {
                ForEach(MathEnginePreference.allCases) { mode in
                    SelectableOptionRow(
                        title: mode.shortTitle,
                        subtitle: mode.subtitle,
                        badge: mode == .auto ? "推荐" : nil,
                        isSelected: settings.mathEngine == mode
                    ) {
                        settings.mathEngine = mode
                    }
                }
            }

            Section("内置离线能力") {
                LabeledContent("LaTeX 定界符") {
                    Text("$…$  \\(…\\)  $$…$$  \\[…\\]  AMS  mhchem")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Mermaid 图表") {
                    Text("v11 离线内置 · 自动跟随深浅色主题")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 4. 文件

    private var filesTab: some View {
        Form {
            Section("图片存储位置") {
                ForEach(ImageStorageStrategy.allCases) { strategy in
                    SelectableOptionRow(
                        title: strategy.shortTitle,
                        subtitle: strategy.subtitle,
                        badge: strategy == .docAssetsFolder ? "默认" : nil,
                        isSelected: settings.imageStrategy == strategy
                    ) {
                        settings.imageStrategy = strategy
                    }
                }
            }

            Section("保存与交互") {
                settingToggleRow(
                    title: "自动保存",
                    subtitle: "编辑停顿后自动保存已命名文档",
                    isOn: $settings.autoSave
                )

                LabeledContent("快捷插图") {
                    Text("支持拖拽、⌘V 粘贴截图及 ⇧⌘I 选取")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Reusable Setting Rows

    private func settingToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func typographySliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 72, alignment: .leading)

            Slider(value: value, in: range, step: step)

            Text(valueText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

// MARK: - Visual Theme Swatch Card

private struct ThemeSwatchCard: View {
    let theme: EditorTheme
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    swatchPreview
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? Color.accentColor
                                        : Color.primary.opacity(isHovered ? 0.24 : 0.12),
                                    lineWidth: isSelected ? 2 : 0.8
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(isSelected ? 0.10 : 0.04),
                            radius: isSelected ? 5 : 2,
                            x: 0,
                            y: 2
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(4)
                    }
                }

                Text(theme.displayName)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var swatchPreview: some View {
        switch theme {
        case .system:
            HStack(spacing: 0) {
                miniCanvas(
                    bg: Color.white,
                    heading: Color(white: 0.16),
                    line: Color(white: 0.72),
                    accent: Color.accentColor
                )
                miniCanvas(
                    bg: Color(red: 0.11, green: 0.12, blue: 0.145),
                    heading: Color(white: 0.92),
                    line: Color(white: 0.42),
                    accent: Color.accentColor
                )
            }

        case .light:
            miniCanvas(
                bg: Color.white,
                heading: Color(white: 0.14),
                line: Color(white: 0.74),
                accent: Color.accentColor
            )

        case .dark:
            miniCanvas(
                bg: Color(red: 0.09, green: 0.10, blue: 0.125),
                heading: Color(white: 0.92),
                line: Color(white: 0.42),
                accent: Color.accentColor
            )

        case .paper:
            miniCanvas(
                bg: Color(red: 0.968, green: 0.952, blue: 0.916),
                heading: Color(red: 0.24, green: 0.20, blue: 0.16),
                line: Color(red: 0.68, green: 0.63, blue: 0.56),
                accent: Color(red: 0.68, green: 0.45, blue: 0.24)
            )

        case .translucent:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.87, blue: 0.98),
                        Color(red: 0.91, green: 0.94, blue: 0.99),
                        Color(red: 0.84, green: 0.89, blue: 0.96),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .padding(6)
                    .overlay(
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(Color.primary.opacity(0.65)).frame(width: 24, height: 3.5)
                            Capsule().fill(Color.primary.opacity(0.28)).frame(width: 38, height: 2.5)
                            Capsule().fill(Color.primary.opacity(0.22)).frame(width: 30, height: 2.5)
                        }
                        .padding(11),
                        alignment: .topLeading
                    )
            }
        }
    }

    private func miniCanvas(bg: Color, heading: Color, line: Color, accent: Color) -> some View {
        ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Capsule().fill(accent).frame(width: 3, height: 8)
                    Capsule().fill(heading).frame(width: 22, height: 3.5)
                }
                Capsule().fill(line).frame(maxWidth: .infinity).frame(height: 2.5)
                Capsule().fill(line.opacity(0.75)).frame(width: 28, height: 2.5)
            }
            .padding(9)
        }
    }
}

// MARK: - Selectable Radio Option Row

private struct SelectableOptionRow: View {
    let title: String
    let subtitle: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(.primary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
