import SwiftUI

/// Full-screen CRT treatment: fine scanlines + a soft vignette. Purely cosmetic,
/// never intercepts touches. Sits above content but below the status bar.
struct CRTOverlay: View {
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let line = Color.black.opacity(0.16)
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(line))
                    y += 3
                }
            }
            .blendMode(.multiply)
            .opacity(0.5)

            RadialGradient(
                colors: [.clear, .black.opacity(0.45)],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadius: 140,
                endRadius: 560
            )
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
