import Foundation

/// What the scan sheet is doing, as a value type: the camera side only feeds it
/// barcode payloads with their boxes and the time, and carries out the
/// effects it returns (a sound, opening Add Book, filling a field). No
/// AVFoundation, no Vision, no clock of its own, so the timings are tested
/// without a camera.
///
/// A read counts after two frames with the same payload within 0.5 s, because
/// a blurry built-in camera misreads single frames now and then.
public struct ScanSession: Equatable, Sendable {
    public struct Detection: Equatable, Sendable {
        public var payload: String
        /// Normalized, origin bottom left, in the camera image (Vision's convention).
        public var box: CGRect

        public init(payload: String, box: CGRect) {
            self.payload = payload
            self.box = box
        }
    }

    public enum Mode: Equatable, Sendable {
        /// The scan sheet of the toolbar and the menu: a read opens Add Book.
        case addBooks
        /// Scanning into the ISBN field of an open editor: a read fills the field.
        case fillISBN
    }

    public enum Event: Sendable {
        case detections([Detection], at: Date)
        case tick(Date)
        /// Add Book opens over the scan sheet and the camera stops.
        case pause
        /// Add Book closed: look again. The same book can be scanned again.
        case resume
        /// "Scan Another" in the duplicate banner.
        case dismissDuplicate
        /// "Add Anyway" in the duplicate banner.
        case addAnyway
    }

    public enum Effect: Equatable, Sendable {
        case playSound
        case openEditor(ISBN)
        case fillField(ISBN)
    }

    public enum State: Equatable, Sendable {
        case looking
        /// An ISBN was read; the sound played and Add Book opens after `openDelay`.
        case found(ISBN, box: CGRect)
        /// The ISBN is already in the library; the banner offers what to do.
        case duplicate(DuplicateIndex.Entry, ISBN)
        case paused
    }

    /// The amber hint for a barcode that is not an ISBN.
    public struct Hint: Equatable, Sendable {
        public var payload: String
        public var display: String
        public var box: CGRect
        public var until: Date
    }

    public static let confirmationWindow: TimeInterval = 0.5
    public static let openDelay: TimeInterval = 0.5
    public static let hintDuration: TimeInterval = 4
    /// A barcode seen again within this gap counts as still in view.
    static let continuityGap: TimeInterval = 1

    public let mode: Mode
    public private(set) var state: State = .looking
    public private(set) var hint: Hint?

    /// First sighting of each payload still waiting for its second frame. Several
    /// barcodes can be in one frame (the ISBN and a price code), so one slot would starve.
    private var candidates: [String: Date] = [:]
    private var foundAt: Date?
    /// The last non-ISBN barcode shown as a hint and when it was last in view,
    /// so a code held in front of the camera shows its hint once, not again each time it expires.
    private var lastHinted: Sighting?

    private struct Sighting: Equatable, Sendable {
        var payload: String
        var seen: Date
    }

    public init(mode: Mode = .addBooks) {
        self.mode = mode
    }

    /// Applies an event. `duplicate` finds a library book for an ISBN-13; it
    /// is asked when Add Book would open, with the books as they are then
    /// (a round adds books while the sheet stays open).
    public mutating func handle(
        _ event: Event, duplicate: (String) -> DuplicateIndex.Entry? = { _ in nil }
    ) -> [Effect] {
        switch event {
        case .detections(let detections, let now):
            return handle(detections, at: now)
        case .tick(let now):
            return tick(now, duplicate: duplicate)
        case .pause:
            state = .paused
            reset()
            return []
        case .resume:
            if state == .paused {
                state = .looking
                reset()
            }
            return []
        case .dismissDuplicate:
            if case .duplicate = state {
                state = .looking
                reset()
            }
            return []
        case .addAnyway:
            guard case .duplicate(_, let isbn) = state else { return [] }
            state = .paused
            reset()
            return [.openEditor(isbn)]
        }
    }

    private mutating func reset() {
        candidates = [:]
        foundAt = nil
        hint = nil
        lastHinted = nil
    }

    // MARK: Detections

    private mutating func handle(_ detections: [Detection], at now: Date) -> [Effect] {
        expireHint(now)
        switch state {
        case .paused, .duplicate:
            return []
        case .found(let isbn, _):
            // The green frame follows the barcode until Add Book opens.
            if let seen = detections.first(where: { BarcodeReading.classify($0.payload) == .isbn(isbn) }) {
                state = .found(isbn, box: seen.box)
            }
            return []
        case .looking:
            break
        }

        candidates = candidates.filter { now.timeIntervalSince($0.value) <= Self.confirmationWindow }
        var confirmedISBN: (ISBN, CGRect)?
        var confirmedOther: (String, String, CGRect)?
        for detection in detections {
            let reading = BarcodeReading.classify(detection.payload)
            if case .ignored = reading { continue }
            // A code that was away for a while is a new appearance, not the old one still in view.
            if let last = lastHinted, last.payload == detection.payload {
                lastHinted = now.timeIntervalSince(last.seen) <= Self.continuityGap ? Sighting(payload: last.payload, seen: now) : nil
            }
            if hint?.payload == detection.payload { hint?.box = detection.box }
            // Two frames within the window confirm; a first or a late one starts the count.
            guard let first = candidates[detection.payload], now.timeIntervalSince(first) <= Self.confirmationWindow,
                  first < now
            else {
                candidates[detection.payload] = now
                continue
            }
            switch reading {
            case .isbn(let isbn): confirmedISBN = confirmedISBN ?? (isbn, detection.box)
            case .notISBN(let display): confirmedOther = confirmedOther ?? (detection.payload, display, detection.box)
            case .ignored: break
            }
        }

        if let (isbn, box) = confirmedISBN {
            candidates = [:]
            hint = nil
            lastHinted = nil
            state = .found(isbn, box: box)
            foundAt = now
            return mode == .fillISBN ? [.playSound, .fillField(isbn)] : [.playSound]
        }
        if let (payload, display, box) = confirmedOther { showHint(payload, display: display, box: box, at: now) }
        return []
    }

    private mutating func showHint(_ payload: String, display: String, box: CGRect, at now: Date) {
        // Its hint is showing: the timer keeps running.
        if hint?.payload == payload {
            lastHinted = Sighting(payload: payload, seen: now)
            return
        }
        // Its hint just ran out while the code is still in view: stay quiet.
        if let last = lastHinted, last.payload == payload, now.timeIntervalSince(last.seen) <= Self.continuityGap {
            return
        }
        hint = Hint(payload: payload, display: display, box: box, until: now.addingTimeInterval(Self.hintDuration))
        lastHinted = Sighting(payload: payload, seen: now)
    }

    // MARK: Time

    private mutating func tick(_ now: Date, duplicate: (String) -> DuplicateIndex.Entry?) -> [Effect] {
        expireHint(now)
        guard mode == .addBooks, case .found(let isbn, _) = state, let foundAt,
              now.timeIntervalSince(foundAt) >= Self.openDelay
        else { return [] }
        self.foundAt = nil
        if let entry = duplicate(isbn.isbn13) {
            state = .duplicate(entry, isbn)
            return []
        }
        state = .paused
        return [.openEditor(isbn)]
    }

    private mutating func expireHint(_ now: Date) {
        if let current = hint, now >= current.until { hint = nil }
    }
}
