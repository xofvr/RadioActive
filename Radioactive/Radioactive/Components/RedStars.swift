import SwiftUI

/// The signature "red stars" rating — the worse a place, the more stars light up
/// in hazard red (with a CRT bloom). Empty stars sit dim. 5 red = maximally toxic.
struct RedStars: View {
    let red: Int
    var size: CGFloat = 26
    var spacing: CGFloat = 5
    var showGlow: Bool = true

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<5, id: \.self) { i in
                let on = i < red
                Image(systemName: on ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(on ? Theme.danger : Theme.ink.opacity(0.28))
                    .shadow(color: (on && showGlow) ? Theme.danger.opacity(0.6) : .clear, radius: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(red) of 5 red stars")
    }
}

/// Compact inline stars used inside field-report cards (0...5 filled).
struct QuoteStars: View {
    let stars: Int
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(i < stars ? Theme.danger : Theme.ink.opacity(0.2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) of 5 stars")
    }
}
