import SwiftUI

// Mac-only: the window's navigation subtitle (the book count under the list name).

extension View {
    func librarySubtitle(_ text: String) -> some View {
        navigationSubtitle(text)
    }
}
