# ios-app — Hustler native foundation

**Status: Milestone 1.** The offer verdict, acceptance-rate logic and master-log
parsing/serialisation are ported into `HustlerCore` with regression tests pinned
to observed web-app behaviour. There is still **no UI feature port**, no archive
import, no ZIPFoundation, no Supabase/backend, and no signing.

- Deployment target: iOS 17.0, iPhone only.
- The Xcode project is generated from `project.yml` by [XcodeGen]; `.xcodeproj`
  is not committed.
- `HustlerCore` is a dependency-free SwiftPM library: Foundation only, no UI, no
  file system, no clock, no network.

## What is ported (M1)

| Area | Type | Web-app source |
|---|---|---|
| Offer verdict, ramp bars, big-order bars, emergency override, zone gas, blank/garbage minutes | `VerdictEngine`, `VerdictSettings`, `VerdictOffer` | `verdict()`, `ramp()` |
| Acceptance from DoorDash counts, log-implied rate, newest logged rate, precedence | `AcceptanceLogic` | `setAcc`, `LOGRATE`, `LOGACC` |
| Pipe-table normalise, dedupe, archive-count merge, CSV→pipe, row count, ordering | `MasterLog` | `masterLog()`, `mergeLog()`, `csvToPipe()`, `isArchLine()`, `logRows()`, `keyOf` sort |
| Pipe/CSV parsing into rows | `MasterLogParser`, `LogRow` | `parse()` |
| `num()`, `$f()`, `+toFixed(1)` parity including tie rounding | `Money`, `JsNumber` | `num()`, `$f()` |

## What is deliberately NOT ported yet

Scoreboard/`analyze` aggregation, monthly statement reconciliation (where **B1**
lives), decline float, quests, California guarantee, history analytics,
archive/ZIP import, PDF parsing, persistence, handoff, deep links, and every
screen beyond the M0 shell.

**B1 remains open and unchanged.** **B6 is preserved**: 15-column `shortcut` CSVs
still lose Zone and Minutes in `csvToPipe`, exactly as the web app does. Other
documented defects (B2, B3, B5, B9, B10, B11) are untouched; see
`docs/native-ios-audit-and-plan.md` §2.

## Verification without macOS minutes

`tools/local-test.sh` runs the core suite on any Linux box or Mac. It uses an
already-installed toolchain if present, and can fetch a pinned one:

```bash
ios-app/tools/local-test.sh --install      # first run: fetch Swift 6.0.3 into ~/.local
ios-app/tools/local-test.sh                # later runs: just test
ios-app/tools/local-test.sh --filter MoneyTests
```

- Version is pinned by `SWIFT_VERSION` (default `6.0.3`); set `SWIFT_SHA256` to
  verify the archive checksum, which is otherwise only protected by HTTPS.
- Tarball is cached in `~/.cache/hustler`, toolchain in `~/.local/swift-<version>`.
- On macOS it uses the Xcode toolchain and downloads nothing. Needs no root.
- On a bare Ubuntu image, missing shared libraries can be installed with
  `apt-get install -y libcurl4 libxml2 libncurses6 libsqlite3-0`; the GitHub
  `ubuntu-latest` image already has them.

## Parity drift detection

The Swift tests do not encode guesses. `tools/parity/oracle.mjs` loads
`index.html`, runs its own `verdict`, `ramp`, `parse`, `masterLog`, `mergeLog`,
`csvToPipe`, `isArchLine`, `logRows`, `yes`, `took`, `num`, `$f` and `analyze`
inside a stubbed DOM, and records the results in `tools/parity/expectations.json`.

```bash
node ios-app/tools/parity/oracle.mjs            # --check is the default: never writes
node ios-app/tools/parity/oracle.mjs --update   # after an APPROVED change only
node ios-app/tools/parity/drift.mjs             # native tests still assert those values
```

`--check` re-runs the web app and deep-compares against the committed
expectations, so editing a calculation in `index.html` turns the **Parity drift**
job red. That is the point: the port must not silently diverge from the web app.
`--update` is not for turning a failing test green; it is for shipping an
approved change to both sides at once, with the expectations diff reviewed.

`drift.mjs` then checks the native side: every `VerdictCase` is compared field by
field and the id sets must match exactly, every money format string must be
asserted, and acceptance assertions are traced back to the oracle fixture they
came from.

**Stated limits.** `drift.mjs` cannot prove that the hand-maintained fixture text
in `Fixtures.swift` is identical to the copy inside `oracle.mjs`, and it cannot
see assertions its parser does not recognise. Value equality is enforced by
`swift test`, which runs those same fixtures; the fixture text itself is reviewed
by inspection. CI runs the drift job on `ubuntu-latest`, costing no macOS minutes.

## Commands (need a Mac with Xcode 26.x)

```bash
brew install xcodegen
cd ios-app && xcodegen generate --spec project.yml
swift test --package-path ios-app/HustlerCore

xcodebuild build \
  -project ios-app/Hustler.xcodeproj \
  -scheme Hustler \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

CI (`.github/workflows/ios.yml`):

| Job | Runner | What it proves |
|---|---|---|
| Parity drift | `ubuntu-latest` | `index.html` still matches the captured expectations, and the native tests still assert them |
| HustlerCore tests | `macos-26` | The package compiles and every test passes under Xcode's toolchain |
| Build iOS app | `macos-26` | The SwiftUI target compiles for the iOS Simulator SDK, unsigned |

## Verification status

| Claim | Status |
|---|---|
| Source exists | Yes |
| Core tests compile and pass | Proven locally via `tools/local-test.sh` and in CI |
| App compiles for iOS | Proven only by CI |
| Installed on a physical iPhone | **No** — needs an Apple signing identity |

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
