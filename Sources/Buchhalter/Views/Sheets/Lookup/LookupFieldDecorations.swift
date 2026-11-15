import SwiftUI

/// The small note under a field whose value differs from the found one:
/// "DNB: 2009 · Use".
struct LookupOfferNote: View {
    var label: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: label)
            Text(verbatim: "·")
            Button("Use", action: action)
                .buttonStyle(.link)
                .accessibilityLabel("Use Found Value")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
    }
}

private struct LookupFilledModifier: ViewModifier {
    var isFilled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isFilled {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.filledFill)
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.filledBorder, lineWidth: 1) }
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// The light green fill and border of a field Complete filled in. It is
    /// drawn over the control, so it works for text fields and popups alike.
    func lookupFilled(_ isFilled: Bool) -> some View {
        modifier(LookupFilledModifier(isFilled: isFilled))
    }
}
