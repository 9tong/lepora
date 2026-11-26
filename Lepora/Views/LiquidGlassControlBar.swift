import SwiftUI

/// Apple macOS 26/27 Liquid Glass style floating slider bar for live adjustment
/// of the Liquid Glass canvas clarity ↔ frosted intensity.
/// Appears exclusively when the "液态玻璃" theme is active.
struct LiquidGlassControlBar: View {
    @Binding var intensity: Double
    let isTypingMinimalMode: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false

    private var effectiveOpacity: Double {
        if isDragging || isHovered || !isTypingMinimalMode {
            return 1.0
        }
        return 0.20
    }

    private var intensityLabel: String {
        switch intensity {
        case ..<0.20: "极清通透"
        case ..<0.42: "轻透液态"
        case ..<0.66: "均衡玻璃"
        case ..<0.86: "柔雾磨砂"
        default: "深雾沉浸"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Subtle floating readout pill while hovering or dragging
            if isDragging || isHovered {
                HStack(spacing: 5) {
                    Text(intensityLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text("\(Int((intensity * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main Apple-style Liquid Glass capsule slider bar
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        intensity = max(0.0, (intensity - 0.15))
                    }
                } label: {
                    Image(systemName: "drop")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(
                            intensity < 0.35 ? Color.primary.opacity(0.92) : Color.secondary.opacity(0.8)
                        )
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("更通透")

                LiquidGlassFluidTrack(value: $intensity, isDragging: $isDragging)
                    .frame(width: 146, height: 22)

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        intensity = min(1.0, (intensity + 0.15))
                    }
                } label: {
                    Image(systemName: "aqi.medium")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(
                            intensity > 0.65 ? Color.primary.opacity(0.92) : Color.secondary.opacity(0.8)
                        )
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("更柔雾")
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassEffect(.regular, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.68),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.14),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.09),
                radius: 14,
                x: 0,
                y: 5
            )
            .scaleEffect(isDragging ? 1.025 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isDragging)
        }
        .opacity(effectiveOpacity)
        .animation(.easeInOut(duration: 0.22), value: effectiveOpacity)
        .animation(.snappy(duration: 0.18), value: isHovered)
        .animation(.snappy(duration: 0.18), value: isDragging)
        .onHover { isHovered = $0 }
    }
}

/// Custom tactile Liquid Glass slider track with a swelling liquid-droplet lens thumb.
private struct LiquidGlassFluidTrack: View {
    @Binding var value: Double
    @Binding var isDragging: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let thumbW: CGFloat = isDragging ? 26 : 21
            let thumbH: CGFloat = isDragging ? 18 : 14.5
            let trackH: CGFloat = isDragging ? 7.5 : 5.5
            let usableW = max(1, geo.size.width - thumbW)
            let clamped = min(1.0, max(0.0, value))
            let thumbCenterX = thumbW * 0.5 + usableW * clamped
            let fillW = max(trackH, thumbCenterX + thumbW * 0.18)

            ZStack(alignment: .leading) {
                // Recessed translucent groove
                Capsule()
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.14)
                            : Color.black.opacity(0.10)
                    )
                    .frame(height: trackH)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06),
                                lineWidth: 0.5
                            )
                    )

                // Luminous liquid fill segment
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.55), Color.white.opacity(0.88)]
                                : [Color.primary.opacity(0.32), Color.primary.opacity(0.58)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: min(geo.size.width, fillW), height: trackH)

                // Apple Tahoe Liquid Glass lens droplet thumb (cleanly turns crystal-clear while sliding)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [
                                    Color.white.opacity(isDragging ? 0.36 : 0.94),
                                    Color.white.opacity(isDragging ? 0.16 : 0.78),
                                ]
                                : [
                                    Color.white.opacity(isDragging ? 0.68 : 0.99),
                                    Color.white.opacity(isDragging ? 0.38 : 0.90),
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: thumbW, height: thumbH)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.72 : 0.98),
                                        Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.18),
                        radius: isDragging ? 6 : 3.5,
                        x: 0,
                        y: isDragging ? 2.5 : 1.5
                    )
                    .position(x: thumbCenterX, y: geo.size.height * 0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                        }
                        let raw = (gesture.location.x - thumbW * 0.5) / usableW
                        value = min(1.0, max(0.0, raw))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isDragging)
        }
    }
}
