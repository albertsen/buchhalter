import SwiftUI

/// First launch: nothing in the library yet.
struct EmptyLibraryView: View {
    var add: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Your library is empty")
                .font(Theme.serif(22))
            Text("Add the book you are reading now, or the ones you want to read next.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Book…", action: add)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
            Text("or press ⌘N")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 340)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A search or an empty list without results.
struct NoMatchesView: View {
    var searchText: String

    var body: some View {
        VStack(spacing: 6) {
            Text("No books match \u{201C}\(searchText)\u{201D}")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// A list without books and without a search.
struct EmptyListView: View {
    var body: some View {
        Text("No books in this list yet.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
