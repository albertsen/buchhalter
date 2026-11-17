import Foundation

/// Which camera the scan sheet uses, decided from what is connected, what the
/// user chose last and what the system prefers. Pure: the camera side maps its
/// devices to candidates.
public enum CameraChoice {
    public enum Kind: Equatable, Sendable {
        /// The Mac's own camera. Fixed focus, so close-ups are blurry.
        case builtIn
        /// An iPhone used as the camera: it focuses close up and reads barcodes reliably.
        case continuity
        /// A USB camera.
        case external
    }

    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var kind: Kind

        public init(id: String, kind: Kind) {
            self.id = id
            self.kind = kind
        }
    }

    /// The id to use, or nil without a camera.
    ///
    /// - The stored choice, when that camera is connected.
    /// - Nothing stored: an iPhone if one is near, else the system's pick.
    /// - The stored camera is gone (the iPhone moved away): the built-in
    ///   camera. The caller keeps the stored id, so the iPhone is picked again
    ///   when it comes back.
    public static func pick(from candidates: [Candidate], stored: String?, systemPreferred: String?) -> String? {
        guard !candidates.isEmpty else { return nil }
        if let stored, candidates.contains(where: { $0.id == stored }) { return stored }
        let preferred = systemPreferred.flatMap { id in candidates.first { $0.id == id }?.id }
        if stored == nil, let phone = candidates.first(where: { $0.kind == .continuity }) { return phone.id }
        if stored != nil, let builtIn = candidates.first(where: { $0.kind == .builtIn }) { return builtIn.id }
        return preferred ?? candidates.first(where: { $0.kind == .builtIn })?.id ?? candidates[0].id
    }

    // MARK: iPhone and iPad

    /// The back cameras of an iPhone or iPad. The virtual ones switch to the
    /// lens that focuses closest (the macro of the ultra wide), which a
    /// barcode a hand's width away needs.
    public enum BackCamera: Equatable, Sendable, CaseIterable {
        case triple, dualWide, wide
    }

    /// The first of triple, dual wide and wide that the device has, as in
    /// Apple's AVCamBarcode sample. The rear camera is never mirrored.
    public static func backCamera(available: [BackCamera]) -> BackCamera? {
        BackCamera.allCases.first { available.contains($0) }
    }
}
