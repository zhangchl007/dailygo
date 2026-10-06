import SwiftUI

struct BrandMark: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.225, style: .continuous)
                    .fill(Color(red: 11 / 255, green: 61 / 255, blue: 112 / 255))

                Path { path in
                    path.move(to: point(0.50, 0.15, width, height))
                    path.addCurve(
                        to: point(0.47, 0.40, width, height),
                        control1: point(0.42, 0.25, width, height),
                        control2: point(0.42, 0.33, width, height)
                    )
                    path.addLine(to: point(0.50, 0.43, width, height))
                    path.addLine(to: point(0.53, 0.40, width, height))
                    path.addCurve(
                        to: point(0.50, 0.15, width, height),
                        control1: point(0.58, 0.33, width, height),
                        control2: point(0.58, 0.25, width, height)
                    )
                    path.closeSubpath()
                }
                .fill(Color(red: 1, green: 138 / 255, blue: 52 / 255))

                Path { path in
                    path.move(to: point(0.18, 0.39, width, height))
                    path.addCurve(
                        to: point(0.47, 0.48, width, height),
                        control1: point(0.30, 0.38, width, height),
                        control2: point(0.40, 0.41, width, height)
                    )
                    path.addLine(to: point(0.47, 0.77, width, height))
                    path.addCurve(
                        to: point(0.18, 0.69, width, height),
                        control1: point(0.38, 0.71, width, height),
                        control2: point(0.29, 0.68, width, height)
                    )
                    path.closeSubpath()

                    path.move(to: point(0.82, 0.39, width, height))
                    path.addCurve(
                        to: point(0.53, 0.48, width, height),
                        control1: point(0.70, 0.38, width, height),
                        control2: point(0.60, 0.41, width, height)
                    )
                    path.addLine(to: point(0.53, 0.77, width, height))
                    path.addCurve(
                        to: point(0.82, 0.69, width, height),
                        control1: point(0.62, 0.71, width, height),
                        control2: point(0.71, 0.68, width, height)
                    )
                    path.closeSubpath()
                }
                .fill(.white)

                Rectangle()
                    .fill(Color(red: 1, green: 138 / 255, blue: 52 / 255))
                    .frame(width: width * 0.03, height: height * 0.31)
                    .offset(y: height * 0.14)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func point(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGPoint {
        CGPoint(x: x * width, y: y * height)
    }
}

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            BrandMark()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("DailyGo")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color(red: 11 / 255, green: 61 / 255, blue: 112 / 255))
                    .accessibilityIdentifier("dailygo-brand")
                Text("深大附中 · 向上每一天")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
