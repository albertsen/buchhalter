import Testing
@testable import BuchhalterCore

struct CameraChoiceTests {
    private let mac = CameraChoice.Candidate(id: "mac", kind: .builtIn)
    private let phone = CameraChoice.Candidate(id: "phone", kind: .continuity)
    private let usb = CameraChoice.Candidate(id: "usb", kind: .external)

    @Test func noCameraGivesNil() {
        #expect(CameraChoice.pick(from: [], stored: "mac", systemPreferred: "mac") == nil)
    }

    @Test func nothingStoredPicksAnIPhoneFirst() {
        #expect(CameraChoice.pick(from: [mac, usb, phone], stored: nil, systemPreferred: "mac") == "phone")
    }

    @Test func nothingStoredWithoutAnIPhoneFollowsTheSystem() {
        #expect(CameraChoice.pick(from: [mac, usb], stored: nil, systemPreferred: "usb") == "usb")
        #expect(CameraChoice.pick(from: [usb, mac], stored: nil, systemPreferred: nil) == "mac")
        #expect(CameraChoice.pick(from: [usb], stored: nil, systemPreferred: nil) == "usb")
    }

    @Test func theStoredChoiceWinsWhileConnected() {
        #expect(CameraChoice.pick(from: [mac, phone], stored: "mac", systemPreferred: "phone") == "mac")
        #expect(CameraChoice.pick(from: [mac, usb, phone], stored: "usb", systemPreferred: nil) == "usb")
    }

    @Test func aMissingStoredCameraFallsBackToTheBuiltInOne() {
        #expect(CameraChoice.pick(from: [usb, mac], stored: "phone", systemPreferred: "usb") == "mac")
        // No built-in camera: the system's pick, then the first.
        #expect(CameraChoice.pick(from: [phone, usb], stored: "gone", systemPreferred: "usb") == "usb")
        #expect(CameraChoice.pick(from: [phone, usb], stored: "gone", systemPreferred: nil) == "phone")
    }

    @Test func theBackCameraPrefersTheVirtualOnes() {
        #expect(CameraChoice.backCamera(available: [.wide, .dualWide, .triple]) == .triple)
        #expect(CameraChoice.backCamera(available: [.wide, .dualWide]) == .dualWide)
        #expect(CameraChoice.backCamera(available: [.wide]) == .wide)
        #expect(CameraChoice.backCamera(available: []) == nil)
    }
}
