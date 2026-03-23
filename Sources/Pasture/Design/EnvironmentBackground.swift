import SwiftUI

struct EnvironmentBackground: View {
    let environment: ModelEnvironment

    @State private var farDrift = false
    @State private var nearDrift = false

    var body: some View {
        let palette = environment.palette

        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [palette.skyTop, palette.skyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        .black.opacity(environment.timeOfDay == .night ? 0.10 : 0.14),
                        .clear,
                        .black.opacity(environment.timeOfDay == .night ? 0.08 : 0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // A broad, low-contrast glow keeps the horizon atmospheric
                // without turning the background into a decorative illustration.
                Ellipse()
                    .fill(palette.horizonGlow.opacity(environment.timeOfDay == .night ? 0.22 : 0.32))
                    .frame(width: geometry.size.width * 1.55, height: geometry.size.height * 0.34)
                    .offset(y: geometry.size.height * 0.12)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.atmosphereTint.opacity(0.06),
                                palette.atmosphereTint.opacity(0.18),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()

                HorizonLayer(
                    color: palette.farLayer,
                    yPosition: 0.60,
                    crestHeight: 0.16,
                    baseHeight: 0.25
                )
                .offset(x: farDrift ? geometry.size.width * 0.07 : -geometry.size.width * 0.07)

                if palette.layerCount >= 3 {
                    HorizonLayer(
                        color: palette.midLayer,
                        yPosition: 0.70,
                        crestHeight: 0.18,
                        baseHeight: 0.28
                    )
                    .offset(x: nearDrift ? -geometry.size.width * 0.02 : geometry.size.width * 0.02)
                }

                HorizonLayer(
                    color: palette.nearLayer,
                    yPosition: 0.80,
                    crestHeight: 0.20,
                    baseHeight: 0.31
                )
                .offset(x: nearDrift ? -geometry.size.width * 0.08 : geometry.size.width * 0.08)

                if palette.layerCount == 4 {
                    Rectangle()
                        .fill(palette.foregroundLayer)
                        .frame(height: geometry.size.height * 0.12)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .ignoresSafeArea()
            .drawingGroup()
        }
        .onAppear {
            farDrift = false
            nearDrift = false

            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                farDrift = true
            }

            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                nearDrift = true
            }
        }
    }
}

private struct HorizonLayer: View {
    let color: Color
    let yPosition: CGFloat
    let crestHeight: CGFloat
    let baseHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let overscan = width * 0.18
                let horizonY = height * yPosition
                let crest = height * crestHeight

                path.move(to: CGPoint(x: -overscan, y: horizonY + crest * 0.30))
                path.addCurve(
                    to: CGPoint(x: width * 0.32, y: horizonY - crest * 0.58),
                    control1: CGPoint(x: width * 0.08, y: horizonY - crest * 0.10),
                    control2: CGPoint(x: width * 0.20, y: horizonY - crest * 0.62)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.72, y: horizonY - crest * 0.12),
                    control1: CGPoint(x: width * 0.47, y: horizonY - crest * 0.54),
                    control2: CGPoint(x: width * 0.60, y: horizonY + crest * 0.06)
                )
                path.addCurve(
                    to: CGPoint(x: width + overscan, y: horizonY + crest * 0.18),
                    control1: CGPoint(x: width * 0.85, y: horizonY - crest * 0.28),
                    control2: CGPoint(x: width * 0.97, y: horizonY + crest * 0.14)
                )

                path.addLine(to: CGPoint(x: width + overscan, y: height + (height * baseHeight)))
                path.addLine(to: CGPoint(x: -overscan, y: height + (height * baseHeight)))
                path.closeSubpath()
            }
            .fill(color)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
