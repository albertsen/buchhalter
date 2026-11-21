# Persistence and sync

The store, where it lives, and how it syncs through the private CloudKit database of `iCloud.de.juergenalbertsen.buchhalter`. Overview: [architecture.md](architecture.md).

## Store

- **Mac:** the app is sandboxed, so the store is `~/Library/Containers/de.juergenalbertsen.buchhalter/Data/Library/Application Support/Buchhalter/library.store` (plus `-wal`, `-shm` and `.library_SUPPORT` with the covers).
- **iOS:** `library.store` in the app's own Application Support folder, `Buchhalter/`.
- `$BUCHHALTER_HOME` replaces the folder, for a separate store, and turns sync off.
- `LibraryContainer.make(at:cloudKitContainer:)` sets `cloudKitDatabase` to `.private(<id>)` or `.none`. `.none` is passed explicitly, because the default `.automatic` turns sync on in an app with the iCloud entitlement. Tests use in-memory containers, which never sync.
- A store that cannot be opened is never deleted, moved or recreated. The Mac shows an alert with the path and the error, logs it to stderr and quits; iOS shows a screen with the path and the error.

## Sync on or off

- **Mac:** sync is on when the binary carries the iCloud entitlement and `$BUCHHALTER_HOME` is not set (`SyncConfiguration`). At launch the app logs `library: <path>` and `sync: <container id>` or `sync: off` to stderr.
- **iOS:** sync is on unless `$BUCHHALTER_HOME` is set or the app runs in the simulator: simulator builds are unsigned, and `CKContainer` stops an app without the iCloud entitlement. The `remote-notification` background mode with `aps-environment` lets CloudKit's silent pushes bring changes in while the app is in the background.
- A store that did not exist starts the first download.

## The library from before sync (Mac)

The unsandboxed app kept the library in `~/Library/Application Support/Buchhalter/` (`LibraryLocation.legacyFolder`, from the real home through `getpwuid`). On a launch where that store exists, `legacyCopyDate` is not set and the container's store holds no books, `LegacyLibraryMigration` copies the store files into a staging folder next to the target and renames it into place (`LegacyLibrary.copy`), sets `legacyCopyDate` and logs `library: copied from <path>`.

- The old folder is only read, through a read-only temporary-exception entitlement. If the sandbox denies the read, an `NSOpenPanel` asks for the folder; a cancel leaves everything as it was, so the next launch asks again.
- After the copy, the view-state keys in `LegacyLibrary.carriedDefaultsKeys` are copied from `~/Library/Preferences/local.buchhalter.plist` where unset, and `libraryListOrder` becomes the `sidebarOrder` row.
- `SyncNoticeSheet` then tells once how many books go to iCloud. Settings → iCloud shows the old folder ("Show in Finder") while it exists.

## CloudKit schema

The production schema is deployed by hand. `make cloudkit-schema` builds `build/BuchhalterSchema.app` for the Development environment. Run as `build/BuchhalterSchema.app/Contents/MacOS/Buchhalter -initializeCloudKitSchema YES` (`open` swallows stderr), `CloudKitSchemaInitializer` calls `initializeCloudKitSchema()` on a scratch store, prints `cloudkit-schema: ok (<id>)` and quits. Then "Deploy Schema Changes…" in the CloudKit Console (icloud.developer.apple.com) copies the record types (`CD_Book`, `CD_Author`, `CD_Authorship`, `CD_Reading`, `CD_Collection`, `CD_ListSettings`) to Production. Neither `cktool` nor CKToolJS can deploy to Production. The V3 fields (`CD_synopsis`, `CD_synopsisSourceRaw` on `CD_Book`) were deployed on 2026-11-18, before the first V3 build reached the library. A build on SchemaV2 (an older device) ignores them and keeps them when it edits a book.

## Status

SwiftData has no sync status API. `CloudSyncMonitor` (shared) observes `NSPersistentCloudKitContainer.eventChangedNotification` and `CKAccountChanged`, asks `CKContainer.accountStatus()`, maps errors (`notAuthenticated`; `quotaExceeded`, also inside `partialFailure`; anything else) and feeds `SyncState`, a pure reducer in the core that yields the Settings status, the sidebar line, the last sync date and the problem.

- "iCloud turned off for Buchhalter" is not an account status: it is an available account plus a `notAuthenticated` event error.
- A first upload or first download ends after 20 s without a new event of its kind (`SyncState.quietPeriod`); CloudKit gives no completion signal.
- `iCloudLastSynced` and `iCloudFirstTransfer` in the defaults keep the line across a relaunch.
- "In iCloud" shows the local book count and `LibraryLocation.storeBytes`; CloudKit reports no per-app usage.
- The buttons (Open System Settings…, Manage Storage…, Show in Finder) are closures in `\.syncActions`, from `SyncActionsModifier` on the Mac and `PhoneSyncActionsModifier` on iOS.

## Sync duplicates

Two devices can create the same author, collection or list setting. `Library.mergeSyncDuplicates()` merges them without undo, 3 s after launch and 2 s after the last successful import, and logs `sync: merged <n> duplicates`: authors by `AuthorName.matchKey` (smallest id survives, a corrected sort name is kept), collections by folded name (earliest `createdAt`, then smallest id; the survivor gets every book), `ListSettings` by key (newest). Books are never merged. The same task then runs `Library.adoptGlobalSort()`, which turns the old global sort row into each list's sort (an older app on another device can still write it) and logs `sync: gave every list the global sort`.

Remote changes never pass through `Library.change`, so they are never on the undo stack.

## Decisions

- **Sync, no export and no backup.** The user decided on 2026-11-15 to rely on iCloud, the way Health or Notes do. Sync protects against losing a device, not against a mistake: a deletion reaches iCloud within seconds. Accepted.
- **CloudKit Production for every build.** The library is the one every build reads, so it never moves between environments. Only `make cloudkit-schema` uses Development, with a scratch store.
- **The old library is copied, never moved.** A copy leaves `~/Library/Application Support/Buchhalter/` as a fallback, which mattered because the first launch was the first time the real store opened through CloudKit.
- **The sidebar order is a `ListSettings` row,** not a schema change or `NSUbiquitousKeyValueStore`: a new attribute would migrate the real library for one string, KVS would add an entitlement and a second sync path.
- **Sync status is a pure reducer in the core,** so the states are tested without CloudKit. `CloudSyncMonitor` only maps CloudKit and Core Data types onto it.
- **Duplicates are merged by a deterministic rule, books never.** Two devices merging at once pick the same survivor. Two books with the same ISBN may be two copies the user owns.
