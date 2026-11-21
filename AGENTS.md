# Buchhalter

A personal app for keeping track of the books the user reads: what they own or want to read, what they are reading now, and what they finished, when, and what they thought of it. The user groups books into their own collections ("Read in 2026", "Classics to Read") and browses them by author. SwiftUI and SwiftData, Swift 6 toolchain, Swift Package Manager. A macOS 27 app and one iOS 27 app for iPhone and iPad, which share the data through iCloud (CloudKit). The UI is in English and German. Book lookup (Complete in Add and Edit Book, Find Cover and Find Synopsis, from the Deutsche Nationalbibliothek, Open Library and Google Books with the user's own key; sources and their order are chosen in Settings) is built. Barcode scanning (the Mac's camera, a USB scanner into the ISBN field, the iPhone's and iPad's back camera) is built. Built for one user. No key ships with the app: the Google Books key is entered in Settings. The Mac app is sandboxed, signed with the team's development certificate and syncs through iCloud; the iOS app is a development build with automatic signing.

Read this before changing anything:

- [docs/dev/architecture.md](docs/dev/architecture.md): apps and signing, targets, layout, data model, data flow, localization, build and test, decisions.

Then read the area doc for what you change: [ui.md](docs/dev/ui.md), [sync.md](docs/dev/sync.md), [lookup.md](docs/dev/lookup.md), [scanning.md](docs/dev/scanning.md).

The docs describe the current code only, never planned work. Specs under `specs/done/` are history: they describe each feature as planned and may be partly outdated. When you change behavior, update the doc in the same change.

## Quick facts

| | |
|---|---|
| Toolchain | Xcode 27.2, Swift 6.4.2, macOS 27 SDK, iOS 27.2 SDK |
| Build | `make app` → `build/Buchhalter.app` (sandboxed, signed with "Apple Development" and the provisioning profile in `~/Library/Developer/Buchhalter/`, CloudKit Production). `make cloudkit-schema` → `build/BuchhalterSchema.app` (CloudKit Development, only for initializing the schema; the user deploys it in the CloudKit Console). `make install` → `/Applications/Buchhalter.app`. `make strings` syncs new texts into `Resources/Localizable.xcstrings`. `make isbn-ranges` refreshes the ISBN range table. `make cli` → `build/buchhalter-cli` (`find-covers` fills missing covers; the user runs it, with Buchhalter closed). `make ios` → `build/ios/Buchhalter.app` from `iOS/Buchhalter.xcodeproj` for `DEVICE` (default `jaPhone`), automatic signing, CloudKit Production. `make ios-install [DEVICE=jaPad]` installs it on the device. `make ios-sim` → an unsigned simulator build |
| Test | `swift test` (`BuchhalterCore` only) |
| Run | The user runs `open build/Buchhalter.app` (real library) and the iOS app on their devices; `make ios-install` only when the user asks. In the simulator agents may run Debug builds (`-debugSeed YES`, `-debugScreen …`), whose store is never the library |
| Bundle id | `de.juergenalbertsen.buchhalter`, iCloud container `iCloud.de.juergenalbertsen.buchhalter`, team `3PT9KVM9AJ` |
| Library | `~/Library/Containers/de.juergenalbertsen.buchhalter/Data/Library/Application Support/Buchhalter/` (SwiftData store, synced). `$BUCHHALTER_HOME` overrides the folder and turns sync off. `~/Library/Application Support/Buchhalter/` holds the library from before sync, copied once on the first launch |
| Branch | `main`, remote `origin` on GitHub |

## Rules

- Logic that can run without a display goes into `BuchhalterCore` (Foundation and SwiftData only) and gets unit tests. Views stay thin: they read with `@Query` and call core functions to change data.
- Keep the data model CloudKit-compatible from the first commit (see architecture.md, Data model). A schema change goes through a new `VersionedSchema` and the migration plan, never by editing a shipped schema.
- Every user-visible text exists in English and German, from the first feature on: window and menu titles, labels, buttons, placeholders, alerts, error messages, empty states, accessibility labels. Texts live in String Catalogs (see architecture.md, Localization), never as concatenated strings. Dates, numbers and plurals go through the locale-aware formatters and the catalog's plural rules. A feature is not done while a text is missing in either language.
- Shared views (`Sources/Buchhalter/App`, `Sources/Buchhalter/Views`) compile for both apps: AppKit or UIKit only inside `#if os`. Mac-only code (menus, `Settings`, AppKit bridges) sits in `Sources/Buchhalter/Mac/`, iOS-only code in `iOS/Buchhalter/`; a shared file uses `#if os(macOS)` / `#if os(iOS)` only for a line or two. Build both after a shared change: `make app` and `make ios-sim`.
- Never delete, move or modify the user's real library (the container folder above, and the old one in `~/Library/Application Support/Buchhalter/`), and never its iCloud data. Tests use in-memory containers. When you run the app from an agent, set `BUCHHALTER_HOME` to a scratch folder.
- No third-party dependencies without asking.
- Network services (book lookup) sit behind protocols in `BuchhalterCore` with fakes; tests never hit the network. API keys live in the Keychain only, never in the store, files, logs or the repo.
- Match the surrounding code: `///` doc comments that explain why, short `// MARK:` sections, no force unwraps, `@MainActor` for everything that touches the UI or the main `ModelContext`.

## How the user works

- **Spec-driven workflow, design first.** A new feature goes through `/dev-spec <name>`, `/dev-plan <name>`, `/dev-implement <name>` and `/dev-archive <name>`, in order (skills in `~/dev/agent-skills/skills/`). `specs/planned/` holds open work. Small fixes are often asked for in chat, without a design or spec.
  - All designs live in one canvas, [Buchhalter design](https://claude.ai/artifact/KWjhfRAqkfyM8d4sYB3ggT), with one titled section per feature ("Library window", "Book Lookup"). A new feature adds a section there, never a new artifact, in the visual language of the existing screens.
  - Designs and specs use the English texts. The spec gives the German text next to each English one where the wording matters (menu items, buttons, status names); the design leaves room for German, which runs about a third longer.
- **Testing at the screen.** The user tests every UI change by hand, on their real library, so the data they enter while testing stays. Build and stop with one line: "The app is ready for testing." (or "The apps are ready for testing."). No test steps, no commands. Never start the app for testing, and never with a scratch `BUCHHALTER_HOME` for them. Feedback comes back terse ("fix").
- **Research before trying.** On an obstacle (SwiftData, CloudKit, SwiftUI behavior), read Apple's documentation, release notes and known issues first and form a hypothesis before changing code. No trial and error.
- **Commits** only when asked, one per feature or change, with conventional commit messages: `feat: Add reading list`, `fix: …`, `docs: …`, `build: …`, `chore: …` (type lowercase, summary capitalized, imperative), with a body that explains why. The user is the sole author: **no `Co-Authored-By` line**, no tool attribution. Commit on `main`, no feature branches. Push only when the user asks.
- **Prose** in docs and specs: plain, short sentences, concrete values (paths, numbers, commands) rather than adjectives.
