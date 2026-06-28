import SwiftUI

/// A "CONTAMINANT LOGGED" rubber-stamp that slams down then fades. Purely
/// cosmetic — driven by `.logStamp(trigger:)` on a false → true transition.
struct LogStamp: View {
    var body: some View {
        Text("CONTAMINANT LOGGED")
            .font(Theme.mono(26))
            .tracking(2)
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.danger, lineWidth: 3)
            )
            .rotationEffect(.degrees(-12))
            .phosphorGlow(Theme.danger, radius: 10)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Plays the stamp once each time `trigger` transitions false → true; no-op on
    /// true → false. Callers pass a Bool that reflects "is logged" so logging-on
    /// plays the stamp while un-logging is silent.
    func logStamp(trigger: Bool) -> some View {
        modifier(LogStampModifier(trigger: trigger))
    }
}

private struct LogStampModifier: ViewModifier {
    let trigger: Bool

    @State private var show = false
    @State private var scale: CGFloat = 1.6
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if show {
                    LogStamp()
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: trigger) { _, isLogged in
                guard isLogged else { return }
                play()
            }
    }

    private func play() {
        scale = 1.6
        opacity = 0
        show = true
        // Slam down.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            scale = 1.0
            opacity = 1
        }
        // Hold, then fade out.
        withAnimation(.easeOut(duration: 0.4).delay(0.8)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            show = false
        }
    }
}
