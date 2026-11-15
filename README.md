# Buchhalter

Keeps track of the books I read: the ones I want to read, the ones I'm reading, and the ones I finished, with dates, ratings and notes.

Native SwiftUI app with SwiftData. macOS first; an iOS app follows and syncs through iCloud. No third-party dependencies.

```
make app      # build/Buchhalter.app
make install  # also copies it to /Applications
swift test    # BuchhalterCore unit tests
```

Requirements: Xcode 27 with the macOS 27 SDK.

Status: no code yet. The first feature sets up the package and the app shell.

## Documentation

- [AGENTS.md](AGENTS.md): project summary, rules and the spec (design first) → plan → implement workflow
- [docs/dev/architecture.md](docs/dev/architecture.md): architecture
- `specs/planned/`, `specs/done/`: feature specs (with design links) and plans
