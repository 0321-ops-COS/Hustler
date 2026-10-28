# ios-app — Hustler native foundation

**Status: Milestone 1.** The offer verdict, acceptance-rate logic, and master-log
parsing/serialisation are ported into `HustlerCore` with regression tests pinned
to observed web-app behaviour. There is still **no UI feature port**, no archive
import, no ZIPFoundation, no Supabase/backend, and no signing.

- Deployment target: iOS 17.0, iPhone only.
- Xcode project is generated from `project.yml` with [XcodeGen]; `.xcodeproj`
  is not committed.
- `HustlerCore` is a dependency-free SwiftPM library: Foundation only, no UI, no
  file system, no clock, no network.

## What is ported (M1)

| Area | Type | Source in the web app |
|---|---|---|
| Offer verdict, ramp bars, big-order bars, emergency override, zone gas, blank/garbage minutes | `VerdictEngine`, `VerdictSettings`, `VerdictOffer` | `verdict()`, `ramp()`, `index.html:429` |
| Acceptance from DoorDash counts, log-implied rate, newest logged rate, precedence | `AcceptanceLogic` | `setAcc`, `LOGRATE`, `LOGACC`, `index.html:372-560` |
| Pipe-table normalise, dedupe, archive-count merge, CSV→pipe, row count, ordering | `MasterLog` | `masterLog()`, `mergeLog()`, `csvToPipe()`, `isArchLine()`, `logRows()`, `keyOf` sort, `index.html:560-688` |
| Pipe/CSV parsing into rows | `MasterLogParser`, `LogRow` | `parse()`, `index.html:348` |
| `num()`, `$f()` and `+toFixed(1)` parity, including tie rounding | `Money`, `JsNumber` | `index.html:236-237` |

## What is deliberately NOT ported yet

Scoreboard/`analyze` aggregation, monthly statement reconciliation (`adjust`,
which is where **B1** lives), decline float, quests, California guarantee,
history analytics, archive/ZIP import, PDF parsing, persistence, handoff,
deep links, and all screens beyond the M0 shell.

**B1 remains open and unchanged:** the web app allocates a statement month's full
total across archive rows while accepted shortcut rows keep their own pay, so a
mixed month can count more gross than the statement. No statement logic exists in
this port, so nothing here can change that behaviour.

Known financial-impacting defects kept as-is (documented, not fixed): B1, B2, B3,
B5, B6, B9, B10, B11. See `docs/native-ios-audit-and-plan.md` §2.

## Regression tests vs. the web app

Expectations are not hand-written. `tools/parity/oracle.mjs` loads `index.html`,
executes its own functions in a stubbed DOM, and writes
`tools/parity/expectations.json`. The Swift tests assert those observed values:

- veto/verdict matrix: 16 cases across ramp ends, clamping, big orders,
  emergency, zero miles, blank and negative minutes, zone gas, exact-bar equality
- `toFixed` tie cases (`0.125 → $0.13`, `1.005 → $1.00`, `2.675 → $2.67`)
- normalise/merge/CSV conversion exact strings, including two preserved quirks:
  `masterLog` drops row-numbered lines that `parse` accepts, and 15-column
  `shortcut` CSVs lose Zone/Minutes (B6)
- `LOGACC`/`LOGRATE` values from `analyze()` over the same fixtures

Re-run the oracle (Node 20+, reads `index.html`, writes nothing to it):

```bash
node ios-app/tools/parity/oracle.mjs
```

## Commands (require a Mac with Xcode 26.x)

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

CI (`.github/workflows/ios.yml`) runs `swift test` and the unsigned simulator
build on `macos-26`. A failing run writes a short diagnostic to the job summary.

## Verification status

| Claim | Status |
|---|---|
| Source exists | Yes |
| Core tests compile and pass | Proven only by CI |
| App compiles for iOS | Proven only by CI |
| Installed on a physical iPhone | **No** — needs an Apple signing identity |

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
