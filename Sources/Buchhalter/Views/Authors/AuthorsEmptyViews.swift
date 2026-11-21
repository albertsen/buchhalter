import SwiftUI

/// Authors with no books in the library.
struct NoAuthorsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No authors yet")
                .font(.headline)
            Text("Authors appear here as you add their books.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 300)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A search in Authors without results.
struct NoAuthorsMatchView: View {
    var searchText: String

    var body: some View {
        Text("No authors match \u{201C}\(searchText)\u{201D}")
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Mac's (and the iPad's in landscape) right side before an author is chosen.
struct NoAuthorSelectedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("No Author Selected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose an author to see their books.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
