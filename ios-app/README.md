# ios-app — Hustler native foundation

**Status: Milestone 5 (statement import in the app).** Verdicts, acceptance
rates, master-log parsing, the Scoreboard totals, calendar bucketing, the
decline float, the zone / hour / month / tax breakdowns, and monthly statement
import + reconciliation are ported into `HustlerCore` with regression tests
pinned to observed web-app behaviour. The statement pipeline is now reachable
from the app, and the master log and statements are stored on the device. There
is still no archive ZIP import, no settings persistence, no Supabase/backend,
and no signing.

- Deployment target: iOS 17.0, iPhone only.
- The Xcode project is generated from `project.yml` by [XcodeGen]; `.xcodeproj`
  is not committed.
- `HustlerCore` is a dependency-free SwiftPM library: Foundation only, plus
  PDFKit for page-one statement text where that framework exists. No UI, no file
  system, no clock, no network.

## What is ported

| Area | Type | Web-app source |
|---|---|---|
| Offer verdict, ramp bars, big-order bars, emergency override, zone gas, blank/garbage minutes | `VerdictEngine`, `VerdictSettings`, `VerdictOffer` | `verdict()`, `ramp()` |
| Acceptance from DoorDash counts, log-implied rate, newest logged rate, precedence | `AcceptanceLogic` | `setAcc`, `LOGRATE`, `LOGACC` |
| Pipe-table normalise, dedupe, archive-count merge, CSV→pipe, row count, ordering | `MasterLog` | `masterLog()`, `mergeLog()`, `csvToPipe()`, `isArchLine()`, `logRows()`, `keyOf` sort |
| Pipe/CSV parsing into rows | `MasterLogParser`, `LogRow` | `parse()` |
| `num()`, `$f()`, `+toFixed(1)` parity including tie rounding | `Money`, `JsNumber` | `num()`, `$f()` |
| Scoreboard tiles: gross, net, net $/hr, net $/mile, offers, miles, hours, acceptance, followed-verdict | `Scoreboard`, `ScoreboardTotals` | `analyze()` |
| Day / week / month / year buckets (weeks start Monday) and per-period totals | `PeriodGrouping`, `PeriodTotals` | `keyOf()`, `renderGame()` |
| Decline float: declines left, declined in the last 100, the four message states | `DeclineFloat` | `renderFloat()` |
| Zone, hour and month breakdowns (orders, net $/hr, net $/mi, miles, mileage deduction) | `Analytics.zones`, `Analytics.hours`, `Analytics.months` | `analyze()` |
| Tax estimate: gross, business miles, mileage deduction, taxable | `Analytics.taxEstimate`, `TaxEstimate` | `analyze()` |
| Statement parsing, the statement store and the `settings.monthly` write-through | `StatementParser`, `EarningsStatement`, `StatementBook`, `StatementMonth` | `stmParse()`, `takeStm()` |
| Page-one PDF text (PDFKit, no OCR) and the paste path | `StatementPDFText`, `StatementParser` | `pdfText()` |
| Statement allocation by minutes in whole cents, mileage split | `StatementReconciler` | `adjust()` |
| Import classification, month summaries, versioned store documents | `StatementImporter`, `StatementMonthSummary`, `StatementStoreDocument`, `MasterLogDocument` | new file-format layer, no web equivalent |

Two populations are kept apart on purpose, because the web app measures them
differently: **money, miles and hours** cover accepted rows only, while
**acceptance** and the followed-verdict percentage cover non-archive rows only.

### Tax estimate

The tax panel is a **flat mileage deduction estimate from your own log**, not tax
advice and not a filing calculation. Its existing assumptions are carried over
unchanged: miles come from accepted rows only, the rate is a single flat
dollars-per-mile setting (`taxRate`, default 0.70 in the app's `DEF`) rather than
the current IRS rate, and no other expenses, self-employment tax, brackets or
credits are modelled. Reconciliation below rewrites archive payouts in each
statement month, which those totals then include.

### Statements and B1

Statement text comes from page one of a PDF (`StatementPDFText`, PDFKit, no OCR)
or from pasted text; both feed `StatementParser`, which keeps the web app's three
regular expressions unchanged. Parsed months go into `StatementBook`, which also
writes the web app's `settings.monthly` map (`month → [total, miles]`): it keeps
an existing miles figure on re-import and writes nothing at all when no text
parses (the caller then offers the paste box).

`StatementReconciler.allocate` is `adjust()` ported exactly. Each statement
month's total is spread over that month's **archive** rows in whole cents by
minutes, with a largest-remainder pass so the parts add up to the statement total
exactly; ties stay in log order, as JavaScript's stable sort does. Miles are
re-split by the same proportions only when the statement carries a mileage
figure. `Net` and `Hourly` cells are left alone, so the scoreboard recomputes net
from the adjusted payout.

**B1 is ported as it exists in the web app, not fixed.** Only archive rows are
re-priced, so logged shortcut pay in the same month is added on top of the
statement total: statement $1,000 + shortcut $250 → $1,250 of month gross. There
is no subtraction of shortcut pay and no clamp; `StatementReconcilerTests` pins
that with a characterization test (`b1_shortcut_ignored`). Any fix is a separate,
approved change with before/after numbers.

All of this stays on the device: no network, no account, no backend. The master
log and the statement store are written to Application Support by the app layer
(see below); `HustlerCore` itself performs no file I/O.

### Statement import in the app

`Hustler/Features/Statements/` is the first screen wired to this pipeline,
reachable from the app shell:

- **Choose a statement PDF** — `.pdf` via `fileImporter`, read inside a
  security-scoped resource, page one through `StatementPDFText`. A PDF with no
  page-one text (a scan) is reported as such; it is never retried or OCR'd.
- **Paste the statement text** — the same parser, no PDF involved.
- **Master log** — the pipe table is pasted and saved as text; the screen shows
  how many rows and how many archive rows survive normalisation. There is no
  archive ZIP import yet, so archive rows have to arrive as log text (the web
  app's own log export already is pipe-table text).
- **Statement months** — each stored month with its total, payout count, archive
  row count, the sum allocated back to those rows, and a note when accepted live
  pay sits in the same month.

`StatementImporter` classifies submitted text as `parsed`, `emptyText` or
`unreadable` and builds the month summaries from the same `adjust()` port the
analytics use, so the screen cannot disagree with the numbers. The view model
only decides what to say and when to write.

`Hustler/Platform/LocalStore.swift` writes `master-log.json` and
`statements.json` under `Application Support/Hustler/`, atomically and with
complete file protection. Both documents carry `schemaVersion: 1`; a file with a
version the app does not know throws instead of being overwritten, and the screen
says so rather than silently replacing earnings history.

## What is deliberately NOT ported yet

Quests, the California pay guarantee, archive/ZIP import, settings persistence,
handoff, deep links, and every screen beyond the app shell and Statements. The
only persisted artefacts are the master log and the statements; there is no
settings file yet, so nothing outside the statement summary reads a stored
setting.

The period *slicing* the Scoreboard does around "now" (last 10 days, 8 weeks,
12 months) and the insertion of an empty current period are presentation and
clock concerns; the core returns buckets and lets the UI decide.

**B1 remains open and unchanged.** **B6 is preserved**: 15-column `shortcut` CSVs
still lose Zone and Minutes in `csvToPipe`, exactly as the web app does.
**B11 is preserved**: with no acceptance data the float still reports a number
from the default 89% instead of asking for a rate — `DeclineFloatTests` pins
that behaviour so any future fix is a deliberate change. Other documented
defects (B2, B3, B5, B9, B10) are untouched; see
`docs/native-ios-audit-and-plan.md` §2.

## Verification without macOS minutes

`tools/local-test.sh` runs the core suite on any Linux box or Mac:

```bash
ios-app/tools/local-test.sh --install      # first run: fetch Swift 6.0.3 into ~/.local
ios-app/tools/local-test.sh                # later runs: just test
ios-app/tools/local-test.sh --filter ScoreboardTests
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
`index.html`, runs its own functions inside a stubbed DOM, and records the
results in `tools/parity/expectations.json`.

```bash
node ios-app/tools/parity/oracle.mjs            # --check is the default: never writes
node ios-app/tools/parity/oracle.mjs --update   # after an APPROVED change only
node ios-app/tools/parity/drift.mjs             # native tests still assert those values
```

The Scoreboard, period tables and float card are only reachable through
rendering functions that read the wall clock, so the oracle stubs `Date` to a
fixed Thursday (2026-10-29) and **parses the HTML those functions produce**. The
expected values are therefore what the app displays, not a reimplementation of
its formulas.

`drift.mjs` then checks the native side: `VerdictCase`, `PeriodCase`,
`StatCase`, `PeriodTotalsCase` and `FloatCase` rows are compared field by field
and the id/key sets must match exactly; the zone, hour, month and tax tables are
compared as ordered sequences, so their sort order is part of the expectation;
statement parse results, allocation arrays and import snapshots are compared by
id and field. A placeholder bucket that `renderGame` inserts for a period with no
takings has no native equivalent and is skipped (`taken === 0` identifies it).

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
| Core tests compile and pass | Proven locally via `tools/local-test.sh` (84 tests) and in CI |
| App compiles for iOS | Proven only by CI — the unsigned simulator build |
| Statement import reachable in the app | Wired to the pipeline and compiled by CI; never launched by hand on a simulator or device |
| Installed on a physical iPhone | **No** — needs an Apple signing identity |

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
