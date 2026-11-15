import SwiftUI
import BuchhalterCore

/// The status control of the Add and Edit Book sheet. Looks like a segmented
/// control, but clicking the selected segment again clears it, so "no status"
/// needs no segment of its own. A system segmented `Picker` can't deselect.
struct StatusSegments: View {
    @Binding var status: DraftStatus?

    private let options: [(DraftStatus, LocalizedStringKey)] = [
        (.wantToRead, "Want to Read"),
        (.reading, "Reading"),
        (.read, "Read"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Divider().frame(height: 14).opacity(isDividerHidden(before: index) ? 0 : 1)
                }
                segment(option.0, option.1)
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }

    private func segment(_ value: DraftStatus, _ label: LocalizedStringKey) -> some View {
        let isSelected = status == value
        return Button {
            status = isSelected ? nil : value
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: 22)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    if isSelected { RoundedRectangle(cornerRadius: 5).fill(Theme.accent) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSelected ? Text("Click again to remove the status.") : Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? Text("Click again to remove the status.") : Text(verbatim: ""))
    }

    /// No divider next to the selected segment, as in a system segmented control.
    private func isDividerHidden(before index: Int) -> Bool {
        guard let status, let selected = options.firstIndex(where: { $0.0 == status }) else { return false }
        return selected == index || selected == index - 1
    }
}
