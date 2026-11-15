import SwiftUI

/// A rounded label as in the design: collection chips, author chips.
struct Chip<Content: View>: View {
    var dashed = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                Capsule().strokeBorder(
                    dashed ? Color.secondary : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])
                )
            }
    }
}
