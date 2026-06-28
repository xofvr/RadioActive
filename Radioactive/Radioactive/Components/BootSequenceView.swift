import SwiftUI

/// RobCo/Vault-Tec style cold-boot overlay. Types a handful of phosphor lines,
/// flickers behind a `CRTOverlay`, then hands off to the app. First launch runs
/// the long sequence (~1.8s); a returning launch runs a short one (~0.6s).
///
/// Owns its own timing and is purely cosmetic — it never blocks scanning, which
/// continues underneath. `onFinish()` is invoked exactly once (tap-to-skip or the
/// auto-finish, whichever lands first).
struct BootSequenceView: View {
    var isFirstRun: Bool
    var onFinish: () -> Void

    /// How many lines are currently revealed.
    @State private var revealed = 0
    /// Latches the single `onFinish` call.
    @State private var finished = false
    /// Drives the subtle phosphor scanline flicker.
    @State private var flicker = false

    private var lines: [String] {
        isFirstRun
        ? [
            "ROBCO INDUSTRIES (TM) TERMLINK",
            "PIP-BOY 3000 MK IV",
            "INITIALISING GEIGER-MÜLLER TUBE…",
            "CALIBRATING DETECTOR ARRAY…",
            "VAULT-TEC ENVIRONMENTAL SUITE ONLINE",
          ]
        : [
            "ROBCO TERMLINK — WARM START",
            "DETECTOR ARRAY ONLINE",
          ]
    }

    /// Cadence per line; the long run lands near 1.8s, the short one near 0.6s.
    private var lineInterval: Double { isFirstRun ? 0.32 : 0.26 }

    var body: some View {
        ZStack {
            Theme.bgDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.prefix(revealed).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        Text(">")
                            .foregroundStyle(Theme.phosphorDim)
                        Text(line)
                            .foregroundStyle(Theme.phosphor)
                    }
                    .font(Theme.mono(20))
                }
                // Blinking cursor while the sequence is still running.
                if revealed < lines.count {
                    Text("_")
                        .font(Theme.mono(20))
                        .foregroundStyle(Theme.phosphor)
                        .opacity(flicker ? 1 : 0.2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .padding(.top, 60)

            CRTOverlay()
                .opacity(flicker ? 1 : 0.85)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }                 // tap-to-skip
        .task { await runSequence() }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.08).repeatForever(autoreverses: true)) {
                flicker = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pip-Boy boot sequence")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to skip")
    }

    private func runSequence() async {
        for index in lines.indices {
            try? await Task.sleep(nanoseconds: UInt64(lineInterval * 1_000_000_000))
            if finished { return }
            withAnimation(.easeOut(duration: 0.12)) { revealed = index + 1 }
        }
        try? await Task.sleep(nanoseconds: UInt64(0.2 * 1_000_000_000))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
