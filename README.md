# Buchhalter

Keeps track of the books I read: the ones I want to read, the ones I'm reading, and the ones I finished, with dates, ratings and notes, grouped into my own collections.

Book data and covers come from the Deutsche Nationalbibliothek and Open Library. Later: barcode scanning, and an AI assistant that researches recommendations and adds them to my lists.

Native SwiftUI app with SwiftData, in English and German. macOS first; an app for iPhone and iPad follows and syncs through iCloud. No third-party dependencies.

```
make app      # build/Buchhalter.app
make install  # also copies it to /Applications
swift test    # BuchhalterCore unit tests
```

Requirements: Xcode 27 with the macOS 27 SDK.

Status: the library feature is built (books, readings, collections, sort, search, undo), and book lookup.

## Documentation

- [AGENTS.md](AGENTS.md): project summary, rules and the spec (design first) → plan → implement workflow
- [docs/dev/architecture.md](docs/dev/architecture.md): architecture
- `specs/planned/`, `specs/done/`: feature specs (with design links) and plans
