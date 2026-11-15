import SwiftUI

/// A filled line in the Settings pane: green for a working key, amber for a
/// problem that may pass, red for a refusal, grey for a neutral note. The
/// colours are the lookup hints' fixed fill and text pairs.
struct SettingsHint<Trailing: View>: View {
    enum Tone {
        case success, warning, error, neutral

        var fill: Color {
            switch self {
            case .success: Theme.tint
            case .warning: Theme.warningFill
            case .error: Theme.errorFill
            case .neutral: Color.secondary.opacity(0.12)
            }
        }

        var text: AnyShapeStyle {
            switch self {
            case .success: AnyShapeStyle(Theme.tintText)
            case .warning: AnyShapeStyle(Theme.warningText)
            case .error: AnyShapeStyle(Theme.errorText)
            case .neutral: AnyShapeStyle(.secondary)
            }
        }
    }

    var tone: Tone
    var systemImage: String?
    var message: Text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            message
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            trailing
        }
        .font(.system(size: 12))
        .foregroundStyle(tone.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }
}

extension SettingsHint where Trailing == EmptyView {
    init(tone: Tone, systemImage: String? = nil, message: Text) {
        self.init(tone: tone, systemImage: systemImage, message: message) { EmptyView() }
    }
}
