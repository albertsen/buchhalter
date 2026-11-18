import Foundation

/// Turns the sources' texts into the plain text the app stores: no tags, no
/// entities, paragraphs as single empty lines, no runs of spaces.
public enum SynopsisText {
    /// Google Books' description (`b`, `i`, `br`, `p`) and the DNB's blurb
    /// page (one `div`). Block tags and `<br>` become line breaks; every
    /// other tag is dropped. Nil when nothing is left.
    public static func plain(fromHTML html: String) -> String? {
        var text = html
        // The page's head holds no text worth keeping.
        if let range = text.range(of: "</head>", options: .caseInsensitive) {
            text = String(text[range.upperBound...])
        }
        text = replace(#"<\s*br\s*/?\s*>"#, in: text, with: "\n")
        text = replace(#"<\s*/?\s*(p|div|li|ul|ol|h[1-6]|blockquote)\b[^>]*>"#, in: text, with: "\n\n")
        text = replace(#"<[^>]*>"#, in: text, with: "")
        return normalized(decodeEntities(text))
    }

    /// A DNB summary (field 520): without the "Zusammenfassung: " the DNB
    /// puts in front and the "--(Provided by publisher.)" Library of Congress
    /// records end with.
    public static func cleanedSummary(_ summary: String) -> String? {
        var text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Zusammenfassung:", "Summary:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = replace(#"\s*-*\s*\((Provided by publisher|Publisher's description)\.?\)\s*$"#, in: text, with: "")
        return normalized(text)
    }

    /// Collapses spaces within lines and empty lines between paragraphs, and
    /// trims. Nil for an empty text.
    static func normalized(_ text: String) -> String? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { replace(#"[ \t\x{00A0}]+"#, in: $0, with: " ").trimmingCharacters(in: .whitespaces) }
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }
        let result = paragraphs.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "bdquo": "„", "sbquo": "‚", "laquo": "«", "raquo": "»",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semicolon = after.prefix(10).firstIndex(of: ";") {
                let name = String(after[..<semicolon])
                if let decoded = decode(name) {
                    result += decoded
                    rest = after[after.index(after: semicolon)...]
                    continue
                }
            }
            result += "&"
            rest = after
        }
        return result + rest
    }

    private static func decode(_ name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[name]
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
    }
}
