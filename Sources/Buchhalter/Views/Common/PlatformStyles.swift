import SwiftUI

// Styles that exist on the Mac only, with the closest iOS look. Shared views
// call these instead of `.link` and `.checkbox`.

extension View {
    /// A button drawn as a link: `.link` on the Mac, a borderless tinted button on iOS.
    func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }

    /// A toggle drawn as a checkbox on the Mac and as a switch on iOS.
    func checkboxToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.switch)
        #endif
    }

    /// ⌫ on a selected row deletes on the Mac; iOS deletes by swipe and menu.
    func deleteCommand(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onDeleteCommand(perform: action)
        #else
        self
        #endif
    }

    /// A sheet's fixed width on the Mac. On iOS the sheet takes the screen's
    /// width; `half` makes it a half sheet that can grow (Finish Reading).
    func sheetWidth(_ width: CGFloat, half: Bool = false) -> some View {
        #if os(macOS)
        frame(width: width)
        #else
        frame(maxWidth: .infinity)
            .presentationDetents(half ? [.medium, .large] : [.large])
        #endif
    }

    /// A Settings pane: the Mac window's fixed width, the screen's on iOS.
    func paneWidth(_ width: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        #else
        frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}
