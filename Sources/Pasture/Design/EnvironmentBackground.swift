import SwiftUI

struct EnvironmentBackground: View {
    let environment: ModelEnvironment

    @State private var drift = false

    var body: some View {
        let palette = environment.palette

        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [palette.skyTop, palette.skyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: geometry.size.width * 0.58)
                    .offset(
                        x: drift ? geometry.size.width * 0.22 : -geometry.size.width * 0.14,
                        y: -geometry.size.height * 0.35
                    )
                    .blur(radius: 2)

                LandscapeLayer(
                    color: palette.farLayer,
                    width: geometry.size.width * 1.35,
                    height: geometry.size.height * 0.44,
                    yOffset: geometry.size.height * 0.26,
                    xOffset: drift ? -geometry.size.width * 0.06 : geometry.size.width * 0.06
                )

                LandscapeLayer(
                    color: palette.midLayer,
                    width: geometry.size.width * 1.28,
                    height: geometry.size.height * 0.42,
                    yOffset: geometry.size.height * 0.33,
                    xOffset: drift ? geometry.size.width * 0.05 : -geometry.size.width * 0.03
                )

                LandscapeLayer(
                    color: palette.nearLayer,
                    width: geometry.size.width * 1.3,
                    height: geometry.size.height * 0.4,
                    yOffset: geometry.size.height * 0.41,
                    xOffset: drift ? -geometry.size.width * 0.04 : geometry.size.width * 0.04
                )
            }
            .ignoresSafeArea()
            .drawingGroup()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

private struct LandscapeLayer: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let yOffset: CGFloat
    let xOffset: CGFloat

    var body: some View {
        Ellipse()
            .fill(color)
            .frame(width: width, height: height)
            .offset(x: xOffset, y: yOffset)
    }
}
