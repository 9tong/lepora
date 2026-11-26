import SwiftUI
import AppKit

/// Loads and caches the Retina floating feather PNGs once in memory so the 60fps animation stays pure GPU.
@MainActor
private enum FloatingFeatherAssets {
    static let lightImage: NSImage? = loadImage(named: "FloatingFeatherLight")
    static let darkImage: NSImage? = loadImage(named: "FloatingFeatherDark")

    private static func loadImage(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}

/// Bottom-trailing serene animated floating feather (replaces the old text stats capsule).
/// Keeps transient toast pills to its left when active, and reveals full document stats on click.
struct StatusCapsuleView: View {
    let session: DocumentSession
    let settings: AppSettings

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered: Bool = false
    @State private var showStatsPopover: Bool = false

    private var effectiveFeatherOpacity: Double {
        if isHovered || showStatsPopover {
            return 0.96
        }
        return session.isTypingMinimalMode ? 0.50 : 0.84
    }

    private var featherImage: NSImage? {
        colorScheme == .dark ? FloatingFeatherAssets.darkImage : FloatingFeatherAssets.lightImage
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if let toast = session.toastMessage {
                Text(toast)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.14)), in: .capsule)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if settings.showWordCount {
                floatingFeatherButton
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: session.toastMessage != nil)
    }

    private var floatingFeatherButton: some View {
        Button {
            showStatsPopover.toggle()
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate

                // Organic multi-harmonic indoor breeze motion (weightless & non-mechanical)
                let verticalFloat = sin(t * 1.12) * 4.4 + sin(t * 0.46 + 1.15) * 1.7
                let horizontalDrift = cos(t * 0.62) * 3.1 + sin(t * 0.29) * 1.1
                let pitchDegrees = 9.0 + sin(t * 0.84 - 0.55) * 4.2 + cos(t * 0.39) * 1.4
                let bank3DDegrees = sin(t * 0.55 + 0.35) * 10.5

                // Normalized elevation (0 = lowest settle, 1 = highest buoy) for coupled air shadow
                let elevation = max(0.0, min(1.0, (-verticalFloat + 6.1) / 12.2))
                let hoverBoost: Double = isHovered ? 0.35 : 0.0
                let totalElevation = min(1.35, elevation + hoverBoost)

                ZStack(alignment: .bottom) {
                    // Physics-coupled soft floating contact shadow
                    Ellipse()
                        .fill(
                            colorScheme == .dark
                                ? Color.black.opacity(0.42 - totalElevation * 0.14)
                                : Color.black.opacity(0.13 - totalElevation * 0.055)
                        )
                        .frame(
                            width: 34 + totalElevation * 11,
                            height: 6.5 + totalElevation * 2.2
                        )
                        .blur(radius: 4.0 + totalElevation * 3.2)
                        .offset(
                            x: horizontalDrift * 0.68 - 2,
                            y: -2
                        )

                    // Weightless floating feather
                    Group {
                        if let nsImage = featherImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "leaf")
                                .font(.system(size: 22, weight: .ultraLight))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 58, height: 48)
                    .rotationEffect(.degrees(pitchDegrees + (isHovered ? -3.0 : 0.0)))
                    .rotation3DEffect(
                        .degrees(bank3DDegrees),
                        axis: (x: 0.22, y: 1.0, z: 0.08),
                        perspective: 0.45
                    )
                    .scaleEffect(isHovered ? 1.08 : 1.0)
                    .offset(
                        x: horizontalDrift,
                        y: verticalFloat - 9 + (isHovered ? -4.5 : 0)
                    )
                    .shadow(
                        color: colorScheme == .dark
                            ? Color.white.opacity(isHovered ? 0.16 : 0.08)
                            : Color.black.opacity(0.08),
                        radius: isHovered ? 8 : 4,
                        x: 0,
                        y: 3
                    )
                }
                .frame(width: 74, height: 64)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(effectiveFeatherOpacity)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: isHovered)
        .animation(.easeInOut(duration: 0.28), value: effectiveFeatherOpacity)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("文档统计：\(session.stats.words) 字 · 约 \(session.stats.readingMinutes) 分钟（点击查看详情）")
        .popover(isPresented: $showStatsPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("文档统计")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(session.stats.words) 字")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

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
            .frame(width: 236)
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
