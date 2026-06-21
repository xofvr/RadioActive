import SwiftUI

/// Liquid Glass helpers (iOS 26). Floating chrome — the audio control, range
/// chip, filter chips, NEXT button — rides on real Liquid Glass, while the dark
/// "instrument panel" surfaces keep the CRT body of the device.
extension View {
    /// Apply Liquid Glass clipped to `shape`, optionally tinted/interactive.
    func liquidGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }

    /// Dark inset instrument-panel surface (gradient fill + phosphor hairline).
    func instrumentPanel(cornerRadius: CGFloat = 6, strokeOpacity: Double = 0.30) -> some View {
        background(Theme.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.phosphor.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}
