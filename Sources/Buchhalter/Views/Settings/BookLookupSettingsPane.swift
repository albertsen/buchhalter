import SwiftUI
import BuchhalterCore

/// The Book Lookup pane: which sources Complete and Find Cover ask and in
/// what order, and the Google Books key. Changes apply at once; there is no
/// Save button for the list. Shared-ready: no AppKit.
struct BookLookupSettingsPane: View {
    @Environment(BookSources.self) private var sources

    private static let rowHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            sourcesSection
            VStack(alignment: .leading, spacing: 10) {
                Text("Google Books").font(.system(size: 13, weight: .semibold))
                Text("Google Books has covers for many English editions the other sources miss. It needs your own API key, which Google gives out for free.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GoogleBooksKeySection()
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(width: 620, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.system(size: 13, weight: .semibold))
            Text("Complete and Find Cover ask the sources that are on, from top to bottom. Drag a source to change the order.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // A bordered list of fixed height: three rows that can be dragged.
            List {
                ForEach(sources.list.entries) { entry in
                    row(entry)
                        .frame(height: Self.rowHeight - 10)
                }
                .onMove { source, destination in sources.move(fromOffsets: source, toOffset: destination) }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: Self.rowHeight * CGFloat(sources.list.entries.count))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)) }
            .accessibilityLabel("Sources")
            Text("Google Books can be turned on once a key is saved below. With every source off, Complete and Find Cover are unavailable.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ entry: LookupSourceList.Entry) -> some View {
        let needsKey = entry.source == .googleBooks && !sources.hasGoogleKey
        let isOn = entry.isOn && !needsKey
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isOn }, set: { sources.setOn(entry.source, $0) })) {
                Text(verbatim: entry.source.displayName)
            }
            .toggleStyle(.checkbox)
            .disabled(needsKey)
            // The name is the toggle's label, so a click on it switches the source.
            Spacer(minLength: 8)
            detail(for: entry.source, needsKey: needsKey)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.system(size: 13))
        .foregroundStyle(needsKey ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move Up") { move(entry.source, by: -1) }
        .accessibilityAction(named: "Move Down") { move(entry.source, by: 1) }
    }

    @ViewBuilder
    private func detail(for source: LookupSource, needsKey: Bool) -> some View {
        switch source {
        case .dnb:
            Text("Books published in Germany").font(.system(size: 12)).foregroundStyle(.secondary)
        case .openLibrary:
            Text("Mostly English books").font(.system(size: 12)).foregroundStyle(.secondary)
        case .googleBooks:
            Text(needsKey ? "Needs a key" : "Set up")
                .font(.system(size: 12))
                .foregroundStyle(needsKey ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.tintText))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(needsKey ? Color.secondary.opacity(0.15) : Theme.tint, in: Capsule())
        }
    }

    /// The same move for VoiceOver and the keyboard, which cannot drag.
    private func move(_ source: LookupSource, by offset: Int) {
        guard let index = sources.list.entries.firstIndex(where: { $0.source == source }) else { return }
        let target = index + offset
        guard sources.list.entries.indices.contains(target) else { return }
        sources.move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? target + 1 : target)
    }
}
