import Foundation
import Testing

/// Reads `Resources/Localizable.xcstrings` and `Resources/InfoPlist.xcstrings`
/// (through `#filePath`, not a bundle) and fails when a text lacks English or German, a German value still needs
/// review, or a plural lacks `one` or `other`.
struct LocalizationCatalogTests {
    private typealias JSON = [String: Any]

    private func loadStrings(_ file: String = "Localizable") throws -> [String: JSON] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/\(file).xcstrings")
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

    @Test(arguments: ["Localizable", "InfoPlist"])
    func everyKeyHasEnglishAndGerman(file: String) throws {
        let strings = try loadStrings(file)
        #expect(!strings.isEmpty)
        for (key, entry) in strings {
            for language in ["en", "de"] {
                let found = localization(entry, language)
                #expect(found != nil, "\(file): \(key) has no \(language) value")
                for (_, unit) in units(found ?? [:]) {
                    let value = unit["value"] as? String ?? ""
                    #expect(!value.isEmpty, "\(file): \(key) has an empty \(language) value")
                    #expect(unit["state"] as? String == "translated", "\(file): \(key) \(language) is \(unit["state"] ?? "?")")
                }
            }
        }
    }

    /// The camera access prompt comes from `InfoPlist.strings`, which `make app`
    /// compiles from this catalog, and Info.plist carries the English fallback.
    @Test func theCameraPromptHasTheSpecsTexts() throws {
        let entry = try #require(try loadStrings("InfoPlist")["NSCameraUsageDescription"])
        let english = units(localization(entry, "en") ?? [:]).first?.unit["value"] as? String
        let german = units(localization(entry, "de") ?? [:]).first?.unit["value"] as? String
        #expect(english == "Buchhalter uses the camera to read the barcode on the back of a book.")
        #expect(german == "Buchhalter verwendet die Kamera, um den Barcode auf der Rückseite eines Buchs zu lesen.")
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Info.plist")
        let info = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? JSON)
        #expect(info["NSCameraUsageDescription"] as? String == english)
        #expect(info["NSCameraUseContinuityCameraDeviceType"] as? Bool == true)
    }

    @Test func pluralsHaveOneAndOtherInBothLanguages() throws {
        let strings = try loadStrings()
        for key in ["%lld books", "%lld pages", "%lld stars", "Added in this round: %lld"] {
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

    /// The sentences with two counts keep their plurals in `substitutions`,
    /// which `units` does not read. Each one needs `one` and `other` in both languages.
    @Test func substitutionPluralsHaveOneAndOtherInBothLanguages() throws {
        let strings = try loadStrings()
        var checked = 0
        for (key, entry) in strings {
            for language in ["en", "de"] {
                guard let substitutions = localization(entry, language)?["substitutions"] as? JSON else { continue }
                for (name, value) in substitutions {
                    let plural = ((value as? JSON)?["variations"] as? JSON)?["plural"] as? JSON
                    let forms = Set(plural?.keys.map { $0 } ?? [])
                    #expect(forms.isSuperset(of: ["one", "other"]), "\(key) \(language) \(name)")
                    for (form, variation) in plural ?? [:] {
                        let unit = (variation as? JSON)?["stringUnit"] as? JSON
                        #expect(unit?["state"] as? String == "translated", "\(key) \(language) \(name) \(form)")
                        let text = unit?["value"] as? String ?? ""
                        #expect(text.isEmpty == false, "\(key) \(language) \(name) \(form)")
                    }
                    checked += 1
                }
                // Every %#@name@ in the text has its substitution.
                let text = (localization(entry, language)?["stringUnit"] as? JSON)?["value"] as? String ?? ""
                for name in substitutions.keys {
                    #expect(text.contains("%#@\(name)@"), "\(key) \(language) does not use \(name)")
                }
            }
        }
        #expect(checked >= 4, "the two-count banner sentences use substitutions")
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
            // Book lookup
            "Complete": "Vervollständigen", "Looking up…": "Wird gesucht…", "Stop": "Stopp",
            "Choose an edition": "Ausgabe wählen", "Use This Edition": "Diese Ausgabe übernehmen",
            "Use": "Übernehmen", "Use DNB cover": "DNB-Cover übernehmen", "Undo": "Widerrufen",
            "Try Again": "Erneut versuchen", "Use Open Library cover": "Open-Library-Cover übernehmen",
            "Cancel": "Abbrechen", "Save": "Speichern", "Edit Book": "Buch bearbeiten",
            // Google Books and Settings
            "Book Lookup": "Buchsuche", "Sources": "Quellen", "Needs a key": "Schlüssel nötig",
            "Set up": "Eingerichtet", "API Key": "API-Schlüssel", "Paste your key": "Schlüssel einfügen",
            "Save Key": "Schlüssel sichern", "Checking…": "Wird geprüft…", "Save Anyway": "Trotzdem sichern",
            "Change…": "Ändern…", "Remove": "Entfernen", "How to get a key…": "So bekommst du einen Schlüssel…",
            "Get a Google Books Key": "Google-Books-Schlüssel bekommen",
            "Open Google Cloud Console": "Google Cloud Console öffnen", "Done": "Fertig",
            "No cover found": "Kein Coverbild gefunden", "Open Settings…": "Einstellungen öffnen…",
            "Use Google Books cover": "Google-Books-Cover übernehmen",
            "Turn on a source in Settings": "Schalte in den Einstellungen eine Quelle ein",
            "Can't reach any book source": "Keine Buchquelle erreichbar",
            "Google Books: %@": "Google Books: %@",
            "Searching Google Books for “%@” by %@…": "Suche in Google Books nach „%1$@“ von %2$@…",
            // Barcode scanning
            "Scan Barcode…": "Barcode scannen…", "Scan Barcode": "Barcode scannen", "Camera": "Kamera",
            "Looking for a barcode…": "Suche nach einem Barcode…",
            "Scan several books in a row": "Mehrere Bücher nacheinander scannen",
            "Type ISBN Instead": "ISBN eingeben", "Add and Scan Next": "Hinzufügen und nächstes scannen",
            "Already in your library: %@": "Schon in deiner Bibliothek: %@",
            "Show Book": "Buch zeigen", "Add Anyway": "Trotzdem hinzufügen", "Scan Another": "Nächstes scannen",
            "Buchhalter can't use the camera": "Buchhalter kann die Kamera nicht verwenden",
            "No camera found": "Keine Kamera gefunden", "Open System Settings…": "Systemeinstellungen öffnen…",
            "This barcode isn't an ISBN (%@). Look for the one that starts with 978 or 979.":
                "Dieser Barcode ist keine ISBN (%@). Such den, der mit 978 oder 979 beginnt.",
            // iCloud sync
            "iCloud": "iCloud", "iCloud Sync": "iCloud-Synchronisierung", "Up to date": "Aktuell",
            "Syncing with iCloud…": "Wird mit iCloud synchronisiert…", "Last synced": "Zuletzt synchronisiert",
            "Not yet": "Noch nicht", "In iCloud": "In iCloud",
            "Copy before the first sync": "Kopie vor der ersten Synchronisierung",
            "Show in Finder": "Im Finder zeigen", "Show Copy in Finder": "Kopie im Finder zeigen",
            "Manage Storage…": "Speicher verwalten…",
            "Your Library Now Syncs with iCloud": "Deine Bibliothek wird jetzt mit iCloud synchronisiert",
            "iCloud sync isn't working": "iCloud-Synchronisierung funktioniert nicht",
            "Uploading your library to iCloud…": "Deine Bibliothek wird in die iCloud geladen…",
            "Getting your library from iCloud…": "Deine Bibliothek kommt aus der iCloud…",
            "Sign in to iCloud to sync. Until then the library stays on this Mac only.":
                "Melde dich bei iCloud an, um zu synchronisieren. Bis dahin bleibt die Bibliothek nur auf diesem Mac.",
            "iCloud is turned off for Buchhalter. The library stays on this Mac only and is not protected if the Mac is lost.":
                "iCloud ist für Buchhalter ausgeschaltet. Die Bibliothek bleibt nur auf diesem Mac und ist nicht geschützt, wenn der Mac verloren geht.",
            "Your iCloud storage is full. New changes stay on this Mac and sync once there is space.":
                "Dein iCloud-Speicher ist voll. Neue Änderungen bleiben auf diesem Mac und werden synchronisiert, sobald Platz ist.",
            "iCloud sync stopped: %@. Your changes are kept on this Mac. Buchhalter tries again at the next launch.":
                "Die iCloud-Synchronisierung wurde angehalten: %@. Deine Änderungen bleiben auf diesem Mac. Buchhalter versucht es beim nächsten Start erneut.",
            "Before the library first went to iCloud, Buchhalter kept a copy of it on this Mac, from %@.":
                "Bevor die Bibliothek zum ersten Mal in die iCloud ging, hat Buchhalter eine Kopie davon auf diesem Mac behalten, vom %@.",
        ]
        for (key, german) in expected {
            let entry = try #require(strings[key], "\(key) is missing")
            let value = units(localization(entry, "de") ?? [:]).first?.unit["value"] as? String
            #expect(value == german, "\(key)")
        }
    }
}
