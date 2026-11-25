import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            appearanceTab
                .tabItem {
                    Label("外观与排版", systemImage: "textformat.size")
                }

            mathAndDiagramTab
                .tabItem {
                    Label("公式与图表", systemImage: "function")
                }

            assetsAndSavingTab
                .tabItem {
                    Label("图片与保存", systemImage: "photo.on.rectangle.angled")
                }
        }
        .padding(20)
        .frame(width: 500, height: 370)
    }

    private var appearanceTab: some View {
        Form {
            Section("画布主题") {
                Picker("主题风格", selection: $settings.theme) {
                    ForEach(EditorTheme.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.iconName).tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("排版参数") {
                HStack {
                    Text("正文字号")
                    Spacer()
                    Slider(value: $settings.fontSize, in: 12...24, step: 1)
                        .frame(width: 190)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                HStack {
                    Text("行高倍数")
                    Spacer()
                    Slider(value: $settings.lineHeight, in: 1.3...2.2, step: 0.05)
                        .frame(width: 190)
                    Text(String(format: "%.2f", settings.lineHeight))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                HStack {
                    Text("最大阅读宽度")
                    Spacer()
                    Slider(value: $settings.maxWidth, in: 560...1100, step: 20)
                        .frame(width: 190)
                    Text("\(Int(settings.maxWidth)) px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }

            Section("极简界面") {
                Toggle("显示右下角悬浮字数统计胶囊", isOn: $settings.showWordCount)
                Toggle("默认开启专注模式 (Focus Mode)", isOn: $settings.focusMode)
                Toggle("默认开启打字机居中模式 (Typewriter Mode)", isOn: $settings.typewriterMode)
            }
        }
        .formStyle(.grouped)
    }

    private var mathAndDiagramTab: some View {
        Form {
            Section("LaTeX 公式渲染引擎") {
                Picker("渲染策略", selection: $settings.mathEngine) {
                    ForEach(MathEnginePreference.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("支持全部定界符：$…$、\\(…\\)、$$…$$、\\[…\\]、```math 以及独立 \\begin{equation/align/gather/cases/multline/...} 环境与 mhchem 化学公式。自动模式下优先使用极速 KaTeX，遇到复杂 AMS 环境或宏时无缝自动切换至本地离线 MathJax SVG。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mermaid 图表") {
                Text("内置离线 Mermaid v11 引擎，自动随浅色/深色主题切换配色，支持流程图、时序图、类图、状态图、甘特图、思维导图、ER 图等全套语法。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var assetsAndSavingTab: some View {
        Form {
            Section("图片插入存储策略") {
                Picker("插入图片时", selection: $settings.imageStrategy) {
                    ForEach(ImageStorageStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("支持直接拖入图片、⌘V 粘贴系统截图或剪贴板图片、以及 ⇧⌘I 选择文件；图片右下角手柄可直接拖拽缩放宽度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("保存行为") {
                Toggle("编辑停顿后自动保存已命名文档", isOn: $settings.autoSave)
            }
        }
        .formStyle(.grouped)
    }
}
