import SwiftUI

/// Apple macOS 26/27 Liquid Glass style fluid intensity bar used inside Settings
/// for live adjustment of the Liquid Glass canvas clarity ↔ frosted intensity.
struct LiquidGlassIntensitySliderBar: View {
    @Binding var intensity: Double

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragging: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    intensity = max(0.0, intensity - 0.15)
                }
            } label: {
                Image(systemName: "drop")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(intensity < 0.35 ? Color.primary.opacity(0.92) : Color.secondary.opacity(0.8))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("更通透")

            LiquidGlassFluidTrack(value: $intensity, isDragging: $isDragging)
                .frame(maxWidth: .infinity)
                .frame(height: 22)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    intensity = min(1.0, intensity + 0.15)
                }
            } label: {
                Image(systemName: "aqi.medium")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(intensity > 0.65 ? Color.primary.opacity(0.92) : Color.secondary.opacity(0.8))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("更柔雾")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .glassEffect(.regular, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.65),
                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.14),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
                .allowsHitTesting(false)
        }
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
