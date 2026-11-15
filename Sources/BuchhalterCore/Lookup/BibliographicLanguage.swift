import Foundation

/// Library catalogs name languages with ISO 639-2 codes ("ger", "jpn"). The
/// draft stores two letters ("de", "ja"). Foundation converts the terminology
/// codes but not the 20 bibliographic ones that differ from them.
public enum BibliographicLanguage {
    private static let bibliographicToTerminology: [String: String] = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho",
        "cze": "ces", "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu",
        "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa",
        "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]

    /// "ger" gives "de", "jpn" gives "ja". Nil for a code that has no
    /// two-letter form ("xxx", "mul"). Never returns three letters.
    public static func alpha2(_ code: String) -> String? {
        let lowered = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard lowered.count == 2 || lowered.count == 3 else { return nil }
        let terminology = bibliographicToTerminology[lowered] ?? lowered
        guard let result = Locale.LanguageCode(terminology).identifier(.alpha2), result.count == 2 else {
            return nil
        }
        return result
    }
}
