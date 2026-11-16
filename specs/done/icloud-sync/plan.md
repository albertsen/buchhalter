# iCloud Sync — Plan

## Current State (audited 2026-11-16)

Built on what `architecture.md` describes (Targets, Persistence and sync, Data flow, Undo). Details that matter here:

- `LibraryContainer.make(at:)` builds one `ModelConfiguration(schema:url:)` from `SchemaV2` and `LibraryMigrationPlan` (V1 → V2 custom stage). No CloudKit option yet.
- `LibraryLocation.folder()` returns `$BUCHHALTER_HOME` or `.applicationSupportDirectory/Buchhalter`. In a sandboxed process that directory resolves inside the container, so the default path moves by itself; the old folder needs its own lookup of the real home.
- `BuchhalterApp.init` resolves the URL, logs `library: <path>`, opens the container, shows `StoreFailureAlert` on failure.
- Undo: `Library.change` diffs before/after snapshots and `apply` writes only fields that differ between a record pair (`LibrarySnapshot.swift`). Remote changes never pass through `change`, so they are never on the undo stack. The spec's undo rule mostly holds already; tests must prove it against a second context.
- `existingAuthors()` already resolves duplicates by `AuthorName.matchKey`, the first by `id.uuidString` winning. `ListSettings` readers take the newest `updatedAt`.
- The sidebar order is `@AppStorage("libraryListOrder")` in `SidebarView`, parsed by `LibraryListOrder(raw:)`.
- `KeychainSecretStore` (target `BuchhalterKeychain`, shared with the CLI) uses the file-based login keychain, service `Buchhalter Google Books`, account `api-key`.
- `Makefile`: `make app` copies the SwiftPM binary into `build/Buchhalter.app` and signs ad-hoc (`codesign --force --sign -`). `Resources/Info.plist` holds `CFBundleIdentifier` `local.buchhalter`.
- The real library: `~/Library/Application Support/Buchhalter/`, 50 MB (`library.store`, `-wal`, `-shm`, plus SwiftData's hidden external storage folder for covers).
- Toolchain: Xcode 27.2 (27B52), Swift 6.4.2, macOS 27 SDK.
- Signing (set up 2026-11-16): identity "Apple Development: Jürgen Albertsen (U4QMFKCJC7)". Profile "Buchhalter Development" (macOS App Development, expires 2027-11-16) at `~/Library/Developer/Buchhalter/Buchhalter_Development.provisionprofile`. It allows `icloud-container-environment` `Production` and `Development`, the container, `aps-environment` `development` only, and `keychain-access-groups` `3PT9KVM9AJ.*`.
- Identifiers (user's choice, 2026-11-16): bundle id `de.juergenalbertsen.buchhalter`, container `iCloud.de.juergenalbertsen.buchhalter`. Team id `3PT9KVM9AJ` (enrolled 2026-11-16).

## Research

Valid for Xcode 27.2 / macOS 27 SDK; the implementer checks each API in the SDK headers before use.

- **SwiftData sync** runs on `NSPersistentCloudKitContainer` under the hood. `ModelConfiguration(…, cloudKitDatabase: .private("iCloud.…"))` turns it on; `.none` keeps a store local. Requirements as in architecture.md, Data model (CloudKit rules); the model already meets them. ([Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices))
- **Status:** SwiftData has no sync status API. `NSPersistentCloudKitContainer.eventChangedNotification` is posted for SwiftData stores too; the event (`userInfo[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]`) has `type` (setup, import, export), `startDate`, `endDate`, `succeeded`, `error`. There is no "everything synced" signal. ([forum 763876](https://developer.apple.com/forums/thread/763876), [forum 776219](https://developer.apple.com/forums/thread/776219))
- **Quota:** forum reports say a full iCloud is not always reported through these events ([forum activity 1610080](https://developer.apple.com/forums/activities/1610080)). The storage-full message appears only when an event's error carries `CKError.quotaExceeded`, directly or inside `partialFailure`.
- **Account:** `CKContainer(identifier:).accountStatus()` and `Notification.Name.CKAccountChanged`. Sync resumes by itself after sign-in.
- **Schema:** CloudKit's production schema must be deployed from development in the CloudKit Console ("Deploy Schema Changes"). SwiftData can't initialize it directly. The documented workaround is an `NSPersistentCloudKitContainer` over `NSManagedObjectModel.makeManagedObjectModel(for:)` with the synced types, then `initializeCloudKitSchema()`, in a development-environment build only. Production schemas are additive only. ([Apple sample](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [fatbobman](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/))
- **Environment:** the entitlement `com.apple.developer.icloud-container-environment` (`Production` or `Development`, case-sensitive) chooses the environment. A development profile lists both values. ([forum 707098](https://developer.apple.com/forums/thread/707098), [TN2415](https://developer.apple.com/library/ios/technotes/tn2415/_index.html))
- **Profile type:** a macOS 26 report says a sandboxed app with a Team Store profile is denied `mach-lookup com.apple.cloudd`, while a development profile works ([forum 835400](https://developer.apple.com/forums/thread/835400)). Use a macOS App Development profile.
- **Sandbox:** a sandboxed app reads outside its container only through entitlements (`com.apple.security.temporary-exception.files.home-relative-path.read-only`) or a user-selected file (`com.apple.security.files.user-selected.read-only` with `NSOpenPanel`). Temporary exceptions are not accepted on the Mac App Store.
- **Keychain:** the data protection keychain (`kSecUseDataProtectionKeychain`) needs `keychain-access-groups`; without `kSecAttrAccessGroup` an item goes into the first listed group. The file-based item from the ad-hoc app trusts the old signature, so the signed app's first read may prompt once.

## Decisions

1. **SwiftPM and `make` stay; no Xcode project yet** (user, 2026-11-16). `make app` embeds a macOS App Development profile and signs with "Apple Development" and an entitlements file. Alternative: the Xcode project from Decision 2 in architecture.md now. It is deferred to the iPhone and iPad spec, which needs it anyway; update Decision 2 at archive.
2. **Production environment for `make app`** (user). `make cloudkit-schema` builds a second bundle with `Development`, used only to initialize the schema with a scratch store.
3. **No schema change.** The sidebar order goes into a `ListSettings` row with `key` `sidebarOrder` and `LibraryListOrder.raw` in `sortLevelsRaw`, newest wins like the `sort` row. Alternative: SchemaV3 with a new attribute, or `NSUbiquitousKeyValueStore`. A schema change would migrate the real library and add a CloudKit record field for one string, and KVS would add an entitlement and a second sync path. Same reasoning as Decision 16. The field's name no longer fits; document it at the row's key.
4. **Sync is chosen when the container is built:** `LibraryContainer.make(at:cloudKitContainer:)` with `nil` for `.none`. The app passes `iCloud.de.juergenalbertsen.buchhalter` unless `BUCHHALTER_HOME` is set. Tests use `inMemory()` (no CloudKit). This is what keeps scratch stores from syncing.
5. **The old library is copied, never touched.** Before the container opens, `LegacyLibrary` copies `library.store`, `-wal`, `-shm` and the external storage folder from `~/Library/Application Support/Buchhalter/` into the container folder. Copy into a temporary folder next to the target, then rename, so a crash leaves no half library. It reads the source with a read-only temporary exception for `Library/Application Support/Buchhalter/` and `Library/Preferences/local.buchhalter.plist`. If the read is denied, `NSOpenPanel` asks for the folder (user-selected read-only). Alternative: Apple's container migration manifest, which moves files, against the spec. The exception is fine for development signing and is removed before an App Store build, when no other user has an old library.
6. **Copy rule:** copy when the legacy store exists, `legacyCopyDate` is not set, and the target store is missing or holds no books. On panel cancel, nothing is set, so the next launch asks again. After the copy, set `legacyCopyDate` (defaults) and log `library: copied from <path>`.
7. **Defaults carry over once:** after the copy, read `local.buchhalter.plist` with `PropertyListSerialization` and copy `lookupSources`, `googleBooksKeyState`, `selectedList`, `selectedBook`, `openBook`, `sidebarWidth`, `listWidth`, `WindowFrame main` and `NSWindow Frame main` into the standard defaults where unset. `libraryListOrder` goes into the `sidebarOrder` row.
8. **Keychain:** in the app, `KeychainSecretStore` uses the data protection keychain. When the item is missing there, it reads the legacy file-based item once and saves it to the data protection keychain, keeping the legacy item, which the CLI still uses. If the legacy read fails, there is no key and the spec's fallback applies. The CLI keeps the file-based store. One type with a mode, not two copies.
9. **Sync status is a pure reducer in core.** `SyncState` takes account changes and events (core enums, no CloudKit import) and yields the status box, the problem, the sidebar line and the last sync date. A Mac and iOS app-target observer (`CloudSyncMonitor`) maps CloudKit and Core Data types onto it. This follows architecture.md Decision 8: logic testable without the network.
10. **A first transfer ends after 20 s of quiet:** after the last export (upload) or import (download) event ended successfully, with no new event of that type starting. There is no completion signal, and everyday syncs never show the sidebar line. First upload starts with the legacy copy; first download starts when a new store was created without a legacy copy and the account is available.
11. **Duplicates are merged after each successful import and once at launch,** without undo. Authors by `AuthorName.matchKey`, survivor the smallest `id.uuidString` (as `existingAuthors`). Collections by folded name, survivor the earliest `createdAt`, then the smallest id. The rule is deterministic, so two devices merging at once converge. Books are never merged (spec).
12. **The counts are local:** "In iCloud" shows the local book count and the size of the store files plus the external storage folder. CloudKit gives no per-app usage. Once "Up to date", local and iCloud agree.

## Components

### Core

- **`LibraryContainer`**: `make(at:cloudKitContainer: String?)`. The configuration gets `cloudKitDatabase: .private(id)` or `.none`. `schema` is unchanged.
- **`LibraryLocation`**: adds `legacyFolder(home:)`, `<real home>/Library/Application Support/Buchhalter`. The real home comes from `getpwuid(getuid())`, since `NSHomeDirectory()` is the container in a sandbox. Never creates it.
- **`LegacyLibrary`** (new, `Store/`): `needsCopy(legacy:target:hasBooks:copyDate:) -> Bool` and `copy(from:to:) throws`, which copies the three files and the hidden external storage folder through a temporary folder and a rename. It opens the source read-only and never writes, renames or deletes it. `defaultsToCarryOver(_ plist: [String: Any]) -> [String: Any]` holds the key list from Decision 7.
- **`SyncState`** (new, `Sync/`): a value type with directional inputs `account(AccountStatus)`, `eventStarted(kind)`, `eventEnded(kind, success, SyncError?, at:)`, `quietPeriodPassed(kind)`, `firstUploadBegan`, `firstDownloadBegan`. Outputs: `box` (`.upToDate(lastSynced: Date?)`, `.syncing(firstTransfer: Bool)`, `.problem(SyncProblem)`), `sidebarLine` (`nil`, `.uploading`, `.downloading`, `.problem`) and `lastSynced`. `SyncProblem`: `.notSignedIn`, `.turnedOffForApp`, `.storageFull`, `.failed(message)`. A successful event after a problem clears it. Texts live in `SyncMessages` (English keys, German in the catalog), like `LookupMessages`.
- **`Library.mergeSyncDuplicates()`** (new, `Store/SyncDuplicateOperations.swift`) runs through `withoutUndo`. Authors: re-point each loser's authorships to the survivor. Keep a sort name that differs from `AuthorName.guessSortName(name)` (user-corrected), else the survivor's. Delete the losers. Collections: the survivor gets the union of books and keeps its note and `sortIndex`; delete the losers (their `settings` cascade). `ListSettings` with the same key: delete all but the newest. Returns a count for the log line.
- **`Library.setLibraryListOrder(_:)` / `libraryListOrder(among:)`**: the `sidebarOrder` row, newest wins, without undo, like `setSortLevels`.

### App (shared, iOS-ready: CloudKit, Core Data and SwiftUI only)

- **`CloudSyncMonitor`** (`App/`, `@Observable @MainActor`): owns a `SyncState`. It observes `eventChangedNotification` and `CKAccountChanged` and calls `accountStatus()` at launch and on change. It maps `CKError` codes (`.notAuthenticated` → `.notSignedIn`, `.quotaExceeded` including inside `.partialFailure` → `.storageFull`, others → `.failed(localizedDescription)`). It schedules the quiet-period task and calls `mergeSyncDuplicates` after successful imports. `lastSynced` is persisted in defaults (`iCloudLastSynced`), and so are the first-transfer flags (`iCloudFirstTransfer`), so a relaunch mid-upload keeps the sidebar line. Nil container (scratch store): the status is `.off` and nothing shows.
- **`ICloudSettingsPane`** (`Views/Settings/`): the iCloud tab. A status box or problem message from `SyncState.box`, the copy section when `legacyCopyDate` is set and the legacy folder exists, and the closing note. Buttons call closures, so the Mac file supplies `NSWorkspace`.
- **`SidebarSyncLine`** (`Views/Sidebar/`): shown when `sidebarLine != nil`. Click → the Settings tab `iCloud` (`@AppStorage("settingsTab")` plus `openSettings`).
- **`SyncNoticeSheet`** (`Views/Sheets/`): the one-time sheet. Shown when `legacyCopyDate` is set and `syncNoticeShown` is false; OK sets it.
- **`SidebarView`**: reads the order through `@Query` of `ListSettings` and `libraryListOrder(among:)`, writes through `setLibraryListOrder`. `@AppStorage("libraryListOrder")` goes.
- **`BuchhalterApp.init`**: real store → `LegacyLibrary` check and copy (panel fallback through the Mac-only `LegacyFolderPanel`) → `LibraryContainer.make(at:cloudKitContainer:)` → log `library: <path>` and `sync: iCloud.de.juergenalbertsen.buchhalter` or `sync: off` → create `CloudSyncMonitor`. Then the defaults carry-over and the one-time list order write, after the container exists.

### Mac-only

- **`SettingsView`**: second `Tab("iCloud", systemImage: "icloud")`, selection bound to `settingsTab`.
- **`SyncSystemSettings`**: opens the Apple Account settings and the iCloud storage settings (`x-apple.systempreferences:` URLs; the implementer checks which identifiers macOS 27 accepts) and reveals the legacy folder in the Finder.
- **`LegacyFolderPanel`**: the `NSOpenPanel` fallback, directory `legacyFolder`, folders only.
- **`CloudKitSchemaInitializer`**: active only with the launch argument `-initializeCloudKitSchema YES`. It builds an `NSPersistentCloudKitContainer` over `makeManagedObjectModel(for: SchemaV2.models)` on a store in `FileManager.temporaryDirectory`, loads synchronously, calls `initializeCloudKitSchema()`, logs `cloudkit-schema: ok` or the error to stderr, and quits. It never opens the real library.

### Keychain

- **`KeychainSecretStore`**: `init(mode: .dataProtection(migratingLegacy: true) | .fileBased)`. The app uses the first, `buchhalter-cli` the second. Queries add `kSecUseDataProtectionKeychain: true` in that mode, with no explicit access group.

### Build

- **`Resources/Buchhalter.entitlements`** (template, `TEAM_ID` substituted by `make`): `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.device.camera` (barcode scanning), `com.apple.security.files.user-selected.read-only`, the temporary exception (two paths, Decision 5), `com.apple.developer.icloud-services` `[CloudKit]`, `com.apple.developer.icloud-container-identifiers` `[iCloud.de.juergenalbertsen.buchhalter]`, `com.apple.developer.icloud-container-environment` `Production`, `com.apple.developer.aps-environment` `development` (the only value the development profile allows; the CloudKit environment is set separately), `keychain-access-groups` `[$(TEAM_ID).de.juergenalbertsen.buchhalter]`, `com.apple.application-identifier` and `com.apple.developer.team-identifier`.
- **`Makefile`**: variables `BUNDLE_ID`, `CONTAINER_ID`, `TEAM_ID := 3PT9KVM9AJ`, `SIGN_ID := Apple Development`, `PROFILE ?= $(HOME)/Library/Developer/Buchhalter/Buchhalter_Development.provisionprofile` (outside the repo). `app` copies the profile to `Contents/embedded.provisionprofile`, generates the entitlements and runs `codesign --force --options runtime --entitlements … --sign "$(SIGN_ID)"`. `cloudkit-schema` does the same into `build/BuchhalterSchema.app` with `Development`.

## Interactions

**First launch of the signed app (real library):**

```
BuchhalterApp.init (main)
  legacy = LibraryLocation.legacyFolder(home: realHome)
  target = LibraryLocation.folder()                 // inside the container now
  LegacyLibrary.needsCopy(...) → copy(from: legacy, to: target)
      read denied → LegacyFolderPanel → copy(from: picked) | cancel → empty library
  LibraryContainer.make(at: store, cloudKitContainer: CONTAINER_ID)
  defaults carry-over, sidebarOrder row, legacyCopyDate, iCloudFirstTransfer = upload
  CloudSyncMonitor.start()   → account status, events
RootView appears → SyncNoticeSheet (once)
SwiftData exports in batches → events → SyncState → box "Syncing…", sidebar line
last export ends + 20 s quiet → firstTransfer cleared → box "Up to date", line hidden
```

**Remote change arrives:** SwiftData imports → `@Query` views update (architecture.md, Data flow) → the import event ends successfully → the monitor calls `mergeSyncDuplicates()` on the main context → it saves. That export happens like any other.

**Undo:** unchanged path (`Library.change`). The registered diff holds only the action's fields, so `apply` leaves fields another device changed. An object deleted remotely is skipped when changed; `apply` must not crash on it (test).

**Problems:** the account becomes `.noAccount` → `.problem(.notSignedIn)` → the box shows amber, the sidebar line shows. Signing in → `CKAccountChanged` → available → the next successful event clears it.

**Schema setup (once, user):** `make cloudkit-schema` → `open build/BuchhalterSchema.app --args -initializeCloudKitSchema YES` → stderr `cloudkit-schema: ok` → CloudKit Console: Deploy Schema Changes → `make app`.

## Changes by file

| File | | Change |
|---|---|---|
| `Sources/BuchhalterCore/Store/LibraryContainer.swift` | changed | `cloudKitContainer` parameter |
| `Sources/BuchhalterCore/Store/LibraryLocation.swift` | changed | `legacyFolder(home:)` |
| `Sources/BuchhalterCore/Store/LegacyLibrary.swift` | new | copy rule, copy, defaults key list |
| `Sources/BuchhalterCore/Store/SyncDuplicateOperations.swift` | new | `mergeSyncDuplicates()` |
| `Sources/BuchhalterCore/Store/ListSettingsOperations.swift` | changed | `sidebarOrder` row read and write |
| `Sources/BuchhalterCore/Logic/LibraryListOrder.swift` | changed | doc: stored in the library now |
| `Sources/BuchhalterCore/Sync/SyncState.swift`, `SyncMessages.swift` | new | reducer, enums, texts |
| `Sources/BuchhalterKeychain/KeychainSecretStore.swift` | changed | mode, data protection, legacy carry-over |
| `Sources/BuchhalterCLI/…` (where the store is made) | changed | `.fileBased` mode only |
| `Sources/Buchhalter/App/BuchhalterApp.swift` | changed | copy, container with CloudKit, monitor, log lines |
| `Sources/Buchhalter/App/CloudSyncMonitor.swift` | new | events, account, quiet period, merge trigger |
| `Sources/Buchhalter/Views/Settings/ICloudSettingsPane.swift` | new | iCloud tab |
| `Sources/Buchhalter/Views/Sidebar/SidebarSyncLine.swift` | new | sidebar line |
| `Sources/Buchhalter/Views/Sidebar/SidebarView.swift` | changed | order from the store, sync line |
| `Sources/Buchhalter/Views/Sheets/SyncNoticeSheet.swift` | new | one-time sheet |
| `Sources/Buchhalter/Views/RootView` (where sheets attach) | changed | present the notice |
| `Sources/Buchhalter/Mac/SettingsView.swift` | changed | iCloud tab, tab selection |
| `Sources/Buchhalter/Mac/SyncSystemSettings.swift`, `LegacyFolderPanel.swift`, `CloudKitSchemaInitializer.swift` | new | Mac-only pieces |
| `Resources/Info.plist` | changed | `CFBundleIdentifier` `de.juergenalbertsen.buchhalter` |
| `Resources/Buchhalter.entitlements` | new | template |
| `Resources/Localizable.xcstrings` | changed | every new text, English and German from the spec |
| `Makefile` | changed | signing variables, profile, `cloudkit-schema` |
| `.gitignore` | changed | `*.provisionprofile` |
| `Tests/BuchhalterCoreTests/…` | new | see Testing |

## Testing

Unit tests (`swift test`, in-memory containers and temporary folders only):

- `LegacyLibraryTests`: the copy brings the store, `-wal`, `-shm` and the external storage folder; the source's files, sizes and modification dates are unchanged afterwards; the rule copies into a missing or bookless target and skips once `legacyCopyDate` is set or the target has books; an interrupted copy leaves no target store; the defaults list carries the nine keys and nothing else.
- `SyncStateTests`: every transition. Events while signed out; `.quotaExceeded` → storage full; another error → failed with its message; success clears a problem; the first upload ends only after the quiet period; everyday events never set the sidebar line; `lastSynced` is the last successful end date.
- `SyncDuplicateTests`: two "Thomas Mann" authors from two contexts become one, the books keep their author order, and a corrected sort name wins. Two "Read in 2027" collections become one with the union of books and the earlier note and place. Two books with one ISBN stay two. Running the merge twice changes nothing. The survivor is the same whichever context runs it.
- `UndoSyncTests`: change the title through `Library.change`, change the publisher of the same book in a second `ModelContext` and save, undo → the title reverts and the publisher stays. A book deleted in the second context, then undo of an edit → no crash, no new book.
- `ListSettingsTests`: the `sidebarOrder` row round-trips, newest wins, a damaged value falls back as `LibraryListOrder(raw:)` does.
- `LocalizationCatalogTests` covers the new keys; add the spec's German terms to its term check.

Build: `make test`, `make strings`, `make app` (once `TEAM_ID` and the profile exist).

Manual checks (the user, real library, after the setup steps):

1. `make app`, quit any running Buchhalter, open the app: all books, readings and covers are there; the sheet appears with the right count; Show Copy in Finder opens `~/Library/Application Support/Buchhalter/`; the folder's files are unchanged (`ls -la` before and after).
2. Settings → iCloud: "Syncing with iCloud…" with the first-upload line, then "Up to date"; the sidebar line during the upload; click opens the tab.
3. Quit during the upload, relaunch: it continues; CloudKit Console (production, private database, the user's account) shows `CD_Book` records with the book count.
4. Settings → Book Lookup: sources and order as before; Google Books works (one prompt at most, then none on the next `make app`).
5. Sign out of iCloud (or test with a second macOS user on the same Apple Account, if at hand): the amber message and the sidebar line; adding a book still works; after sign-in it syncs without a relaunch.
6. Drag a built-in list: the order survives a relaunch (and reaches a second device, if at hand).
7. German: `open build/Buchhalter.app --args -AppleLanguages '(de)' -AppleLocale de_DE`: tab, messages, line and sheet in German.

## Permissions

| Action | Status |
|---|---|
| `swift build`, `swift test`, `make test`, `make strings`, `make app`, `make cloudkit-schema` | allowed (`.claude/settings.json`) |
| Apple Developer portal: App ID with iCloud, container `iCloud.de.juergenalbertsen.buchhalter`, register this Mac, macOS App Development profile saved to `~/Library/Developer/Buchhalter/` | the user does it |
| Install the "Apple Development" certificate | the user does it |
| `open build/BuchhalterSchema.app --args -initializeCloudKitSchema YES`, then "Deploy Schema Changes" in the CloudKit Console | the user does it |
| Starting `build/Buchhalter.app` on the real library | the user does it; agents only build |

The implementer pauses before each step the user does, and before the first `make app` that needs `TEAM_ID`.

## Risks and open points

- **Irreversible:** the first launch uploads the library to production. The production schema is additive only after deployment. Get the schema right in the development step.
- **Migration plan with CloudKit:** the real store is already V2, so no stage runs, but a CloudKit-configured container with a migration plan has to open it. Test with a copy of the real library under `BUCHHALTER_HOME`, with sync off, before the first real launch. A store opened with `.none` is not the CloudKit path, so the user's first launch is the real test. That is why the old folder stays untouched.
- **"iCloud turned off for Buchhalter"** may not differ from "not signed in" in `CKAccountStatus` on macOS 27. If it doesn't, show `.notSignedIn` and note it at archive.
- **Storage full** may only arrive as a generic error (Research). Then the red message shows.
- **The 20 s quiet period** is a heuristic: a slow upload with long gaps can end the first-transfer line early. Only the line is affected; the box shows "Syncing…" for each event.
- **The temporary exception** must go before an App Store build. Add that to architecture.md, Open points, at archive.
- **The keychain prompt** for the legacy item may appear once on the first read. If the sandbox denies the legacy item outright, the user pastes the key again (spec fallback).
- **`buchhalter-cli`** keeps working on the old folder, which is no longer the library. Adapting it is out of scope.
- **Left to the implementer:** the exact `x-apple.systempreferences:` identifiers, the file layout under `Sync/`, and how the notice sheet attaches to the existing sheet routing in `RootView`/`WindowModel`.
