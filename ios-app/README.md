# ios-app — Hustler native foundation

**Status: Milestone 0 only.** There is no offer analysis, archive import, statement
parsing, quest, or California logic here yet. Those arrive only after separate
authorization for M1 onwards.

- Deployment target: iOS 17.0, iPhone only.
- Xcode project is **generated** from `project.yml` with [XcodeGen]; the
  `.xcodeproj` is not committed.
- The app target owns no arithmetic. All future calculations go in
  `HustlerCore`, a dependency-free SwiftPM library.
- First party only: no backend, no account, no network calls, no paid services.
  ZIPFoundation is approved but deliberately **not** added yet (needed at M3).

## Layout

```
ios-app/
  project.yml                  # XcodeGen spec (source of truth)
  HustlerCore/                 # pure Swift package, no dependencies
    Package.swift
    Sources/HustlerCore/Money.swift
    Tests/HustlerCoreTests/MoneyTests.swift
  Hustler/                     # SwiftUI app target
    App/HustlerApp.swift
    App/RootView.swift
    Resources/Info.plist
  .gitignore                   # generated project + build output
```

## Commands (require a Mac with Xcode 26.x)

```bash
brew install xcodegen
cd ios-app && xcodegen generate --spec project.yml

# Core unit tests (no simulator needed)
swift test --package-path ios-app/HustlerCore

# Build the app for a simulator
xcodebuild build \
  -project ios-app/Hustler.xcodeproj \
  -scheme Hustler \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

CI (`.github/workflows/ios.yml`) runs the same two things on `macos-26`:
`swift test` for the core, and an unsigned simulator build of the app.

## What M0 does and does not prove

| Claim | Status at M0 |
|---|---|
| Source files exist | Yes |
| `HustlerCore` tests compile and pass | Proven by CI only |
| App target compiles for iOS | Proven by CI only |
| Anything installed on a physical iPhone | **No** — needs an Apple signing identity |
| Any financial calculation ported | **No** |

## Open items carried into later milestones

- **B1 (critical, unresolved):** the web app allocates a statement month's full
  total across archive rows while accepted shortcut rows keep their own pay, so a
  mixed month can count more gross than the statement. Documented in
  `docs/native-ios-audit-and-plan.md`; no calculation is implemented or changed
  here. Decision A6 is still open.
- B2–B12 and decisions A6–A13 are documented in the plan and remain open.
- Menu pins, California entries and statement payout counts are not recoverable
  from the web handoff file; migration work is scheduled for M3/M4.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
