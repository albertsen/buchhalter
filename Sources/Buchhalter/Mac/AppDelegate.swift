import AppKit

// Mac-only. The app has a single window and one undo stack, so closing the
// window quits it.

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
