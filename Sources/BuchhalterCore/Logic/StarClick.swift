import Foundation

/// What a click on one of the five rating stars does.
public enum StarClick {
    /// A click on star n gives n stars. A second click on the same star makes
    /// it half (n − 0.5), a third whole again, so every half step is two
    /// clicks away at most.
    public static func rating(afterClicking star: Int, current: Double?) -> Double {
        let whole = Double(star)
        return current == whole ? whole - 0.5 : whole
    }
}
