import Foundation
import Testing

/// Reads `Resources/Localizable.xcstrings` (through `#filePath`, not a bundle)
/// and fails when a text lacks English or German, a German value still needs
/// review, or a plural lacks `one` or `other`.
struct LocalizationCatalogTests {
    private typealias JSON = [String: Any]

    private func loadStrings() throws -> [String: JSON] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let root = try #require(object as? JSON)
        return try #require(root["strings"] as? [String: JSON])
    }

    private func localization(_ entry: JSON, _ language: String) -> JSON? {
        (entry["localizations"] as? JSON)?[language] as? JSON
    }

    /// Every string unit of a localization, with the plural form it belongs to.
    private func units(_ localization: JSON) -> [(form: String?, unit: JSON)] {
        if let unit = localization["stringUnit"] as? JSON { return [(nil, unit)] }
        guard let plural = (localization["variations"] as? JSON)?["plural"] as? JSON else { return [] }
        return plural.compactMap { form, value in
            ((value as? JSON)?["stringUnit"] as? JSON).map { (form, $0) }
        }
    }

    @Test func everyKeyHasEnglishAndGerman() throws {
        let strings = try loadStrings()
        #expect(!strings.isEmpty)
        for (key, entry) in strings {
            for language in ["en", "de"] {
                let found = localization(entry, language)
                #expect(found != nil, "\(key) has no \(language) value")
                for (_, unit) in units(found ?? [:]) {
                    let value = unit["value"] as? String ?? ""
                    #expect(!value.isEmpty, "\(key) has an empty \(language) value")
                    #expect(unit["state"] as? String == "translated", "\(key) \(language) is \(unit["state"] ?? "?")")
                }
            }
        }
    }

    @Test func pluralsHaveOneAndOtherInBothLanguages() throws {
        let strings = try loadStrings()
        for key in ["%lld books", "%lld pages", "%lld stars"] {
            let entry = try #require(strings[key], "\(key) is missing")
            for language in ["en", "de"] {
                let forms = Set(units(try #require(localization(entry, language))).compactMap(\.form))
                #expect(forms.isSuperset(of: ["one", "other"]), "\(key) \(language) lacks one or other")
            }
        }
        // Any other key with variations must be complete too.
        for (key, entry) in strings {
            for language in ["en", "de"] {
                let found = units(localization(entry, language) ?? [:]).compactMap(\.form)
                if !found.isEmpty { #expect(Set(found).isSuperset(of: ["one", "other"]), "\(key) \(language)") }
            }
        }
    }

    @Test func germanTermsFromTheSpec() throws {
        let strings = try loadStrings()
        let expected: [String: String] = [
            "Library": "Bibliothek", "Reading": "Lese ich", "Want to Read": "Will ich lesen",
            "Read": "Gelesen", "All Books": "Alle Bücher", "Collections": "Sammlungen",
            "New Collection": "Neue Sammlung", "Readings": "Lektüren", "Finish Reading…": "Fertig gelesen…",
            "Abandon": "Lektüre abbrechen", "Abandoned": "Nicht zu Ende gelesen", "Edit": "Bearbeiten",
            "Add to Collection": "Zu Sammlung hinzufügen", "Sort": "Sortieren", "Search": "Suchen",
            "abandonSheet.confirm": "Lektüre abbrechen",
        ]
        for (key, german) in expected {
            let entry = try #require(strings[key], "\(key) is missing")
            let value = units(localization(entry, "de") ?? [:]).first?.unit["value"] as? String
            #expect(value == german, "\(key)")
        }
    }
}
