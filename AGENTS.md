# Buchhalter

A personal app for keeping track of the books the user reads: what they own or want to read, what they are reading now, and what they finished, when, and what they thought of it. SwiftUI and SwiftData, Swift 6 toolchain, Swift Package Manager. macOS 27 first; an iOS 27 app follows and shares the data through iCloud (CloudKit). A personal tool for one user: no App Store, no distribution.

Read this before changing anything:

- [docs/dev/architecture.md](docs/dev/architecture.md): targets, layout, data model, persistence and sync, data flow, UI structure, the phases from macOS to iOS, and the reasons behind the decisions.

The architecture doc describes the current code and the intended direction. Specs under `specs/done/` are history: they describe each feature as planned and may be partly outdated. When you change behavior, update the doc in the same change.

## Quick facts

| | |
|---|---|
| Status | No code yet. The first spec sets up the package and the app shell |
| Toolchain | Xcode 27.2, Swift 6.4.2, macOS 27 SDK |
| Build | `make app` → `build/Buchhalter.app` (ad-hoc signed). `make install` → `/Applications/Buchhalter.app` |
| Test | `swift test` (`BuchhalterCore` only) |
| Run | `open build/Buchhalter.app` |
| Bundle id | `local.buchhalter` until iCloud sync arrives (see architecture.md, Phases) |
| Library | `~/Library/Application Support/Buchhalter/` (SwiftData store). `$BUCHHALTER_HOME` overrides the folder |
| Branch | `main`, no remote yet |

## Rules

- Logic that can run without a display goes into `BuchhalterCore` (Foundation and SwiftData only) and gets unit tests. Views stay thin: they read with `@Query` and call core functions to change data.
- Keep the data model CloudKit-compatible from the first commit (see architecture.md, Data model). A schema change goes through a new `VersionedSchema` and the migration plan, never by editing a shipped schema.
- Write views so they can run on iOS: no AppKit in shared views. Mac-only code (menus, `Settings`, AppKit bridges) sits in clearly marked Mac-only files.
- Never delete, move or modify the user's real library in `~/Library/Application Support/Buchhalter/`. Tests use in-memory containers. When you run the app from an agent, set `BUCHHALTER_HOME` to a scratch folder.
- No third-party dependencies without asking.
- Match the surrounding code: `///` doc comments that explain why, short `// MARK:` sections, no force unwraps, `@MainActor` for everything that touches the UI or the main `ModelContext`.

## How the user works

- **Spec-driven workflow, design first.** Every new feature goes through these steps, in order:
  1. `/dev:spec <name>` starts with a visual mockup of the feature as a Claude design artifact: the screens, their states (empty, loading, error, filled) and the interactions. The user iterates on it until it is right. Then it interviews the user and writes `specs/planned/<name>/spec.md`: the design link and the experience only (what the user sees and does), no architecture or code. The first design sets the app's visual language; later designs reuse it.
  2. `/dev:plan <name>` audits the code, researches frameworks against the installed versions, and writes `specs/planned/<name>/plan.md`: architecture decisions, components, interactions, changes by file, testing. Conceptual; snippets are directional and never compiled.
  3. `/dev:implement <name>` hands spec and plan to a Sonnet sub-agent that writes the code, builds and tests. The design artifact linked in the spec is the reference for the look.
  4. `/dev:archive <name>` updates the docs and moves the finished spec to `specs/done/<name>/`.

  The skills are in `~/dev/agent-skills/commands/dev/`. `specs/planned/` holds open work. Small fixes are often asked for directly in chat, without a design or spec.
- **Manual testing at the screen.** The user checks every UI change by hand. Feedback comes back terse ("1 yes 2 no", "run again", "fix"). When they say "run again", start the app yourself in the background with a scratch `BUCHHALTER_HOME` and read the log after they quit.
- **Research before trying.** On an obstacle (SwiftData, CloudKit, SwiftUI behavior), read Apple's documentation, release notes and known issues first and form a hypothesis before changing code. No trial and error.
- **Commits** only when asked, one per feature or change, with conventional commit messages: `feat: Add reading list`, `fix: …`, `docs: …`, `build: …`, `chore: …` (type lowercase, summary capitalized, imperative), with a body that explains why. The user is the sole author: **no `Co-Authored-By` line**, no tool attribution. Commit on `main`, no feature branches. Push only when the user asks.
- **Prose** in docs and specs: plain, short sentences, concrete values (paths, numbers, commands) rather than adjectives.
- Confirm before destructive actions. Finding something deletable is not permission to delete it.
