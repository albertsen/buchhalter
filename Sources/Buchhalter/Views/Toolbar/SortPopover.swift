import SwiftUI
import BuchhalterCore

/// The sort level editor for one list. Every change is saved at once.
struct SortPopover: View {
    var listName: String
    var levels: SortLevels
    var onChange: (SortLevels) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sort \(listName)")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Reset to Default") { onChange(.default) }
                    .buttonStyle(.link)
                    .disabled(levels.isDefault)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(levels.levels.enumerated()), id: \.element.field) { index, level in
                    GridRow {
                        Text(index == 0 ? "Sort by" : "then by")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Picker("Field", selection: Binding(
                            get: { level.field },
                            set: { onChange(levels.setting(field: $0, at: index)) }
                        )) {
                            ForEach([level.field] + levels.availableFields, id: \.self) { field in
                                Text(field.longName).tag(field)
                            }
                        }
                        .labelsHidden()
                        Picker("Order", selection: Binding(
                            get: { level.direction },
                            set: { onChange(levels.setting(direction: $0, at: index)) }
                        )) {
                            ForEach(SortDirection.allCases, id: \.self) { direction in
                                Text(level.field.name(for: direction)).tag(direction)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Button {
                            onChange(levels.removing(at: index))
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .accessibilityLabel("Remove level")
                    }
                }
            }
            Button("+ Add Level") { onChange(levels.adding()) }
                .disabled(!levels.canAdd)
                .padding(.leading, 70)
            Divider()
            Text("Fields: Author, Title, Year Published, Date Added, Date Started, Date Finished, Rating, Pages. Books that match on every level are sorted by title.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 420)
    }
}
