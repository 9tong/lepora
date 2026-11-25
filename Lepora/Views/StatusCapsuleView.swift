import SwiftUI

struct StatusCapsuleView: View {
    let session: DocumentSession
    let settings: AppSettings

    @State private var isHovered: Bool = false
    @State private var showStatsPopover: Bool = false

    private var effectiveOpacity: Double {
        if isHovered || showStatsPopover || !session.isTypingMinimalMode {
            return 1.0
        }
        return 0.3
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if let toast = session.toastMessage {
                    Text(toast)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .capsule)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if settings.showWordCount {
                    Button {
                        showStatsPopover.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(session.stats.words) 字")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .monospacedDigit()

                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text("\(session.stats.readingMinutes) 分钟")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)

                            if session.stats.mathCount > 0 {
                                Label("\(session.stats.mathCount)", systemImage: "function")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            if session.stats.diagramCount > 0 {
                                Label("\(session.stats.diagramCount)", systemImage: "point.3.connected.trianglepath.dotted")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: .capsule)
                    .popover(isPresented: $showStatsPopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("文档统计")
                                .font(.system(size: 13, weight: .semibold))

                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                                statRow("字数（中英统计）", "\(session.stats.words)")
                                statRow("字符数（不含空白）", "\(session.stats.characters)")
                                statRow("段落 / 块数", "\(session.stats.lines)")
                                statRow("预计阅读时间", "约 \(session.stats.readingMinutes) 分钟")
                                statRow("LaTeX 公式", "\(session.stats.mathCount) 个")
                                statRow("Mermaid 图表", "\(session.stats.diagramCount) 个")
                            }

                            Divider().opacity(0.4)

                            HStack {
                                Text("公式引擎")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(settings.mathEngine == .auto ? "KaTeX + MathJax" : settings.mathEngine.rawValue.uppercased())
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(14)
                        .frame(width: 230)
                    }
                }
            }
        }
        .opacity(effectiveOpacity)
        .animation(.easeInOut(duration: 0.25), value: effectiveOpacity)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}
