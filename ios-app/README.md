# ios-app — Hustler native foundation

**Status: Milestone 5 (statement import in the app).** Verdicts, acceptance
rates, master-log parsing, the Scoreboard totals, calendar bucketing, the
decline float, the zone / hour / month / tax breakdowns, and monthly statement
import + reconciliation are ported into `HustlerCore` with regression tests
pinned to observed web-app behaviour. The statement pipeline is now reachable
from the app, the master log and statements are stored on the device, and
DoorDash `data_archive.zip` import is wired. There is still no settings
persistence, no Supabase/backend, and no signing.

- Deployment target: iOS 17.0, iPhone only.
- The Xcode project is generated from `project.yml` by [XcodeGen]; `.xcodeproj`
  is not committed.
- `HustlerCore` is a dependency-free SwiftPM library: Foundation only, plus
  PDFKit for page-one statement text where that framework exists. No UI, no
  clock, no network. Its one file-system type is `LocalStore`, and every test of
  it runs against a temporary directory.
- `HustlerArchive` is a second target in the same package and the only place a
  third-party dependency appears: **ZIPFoundation 0.9.20** (MIT, no transitive
  dependencies on Apple platforms), pinned exactly. `HustlerCore` does not depend
  on it.

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
| On-device files: blocked writes after a failed load, explicit recovery, commit only after a successful write | `LocalStore`, `LocalLibrary`, `StoreArtefact` | new file-format layer, no web equivalent |
| DoorDash archive ZIP → delivery CSV → archive rows, overlap minutes, estimates, merge | `DeliveryArchiveFile`, `DeliveryCSV`, `ArchiveImporter` | `importZip()`, `loadDeliv()`, `toLog()` |

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
  how many rows and how many archive rows survive normalisation.
- **DoorDash archive** — imports `data_archive.zip`; see the next section.
- **Statement months** — each stored month with its total, payout count, archive
  row count, the sum allocated back to those rows, and a note when accepted live
  pay sits in the same month.

`StatementImporter` classifies submitted text as `parsed`, `emptyText` or
`unreadable` and builds the month summaries from the same `adjust()` port the
analytics use, so the screen cannot disagree with the numbers. The view model
only decides what to say and when to write.

### Persistence safety

`HustlerCore/LocalStore.swift` owns both files — `master-log.json` and
`statements.json` under `Application Support/Hustler/` — plus `LocalLibrary`,
which holds the in-memory state and decides when a change becomes durable. The
rules live at the file layer so no screen can bypass them:

- **Missing file** → a new empty document. A first run is not an error.
- **A file that exists but will not decode** — corrupt, unreadable, or a newer
  `schemaVersion` — marks that artefact *unavailable*, and every later save to it
  throws. It is never treated as an empty document and never overwritten.
- **Recovery is explicit.** The only way out is "keep a copy and start fresh",
  which moves the unreadable file to `master-log.json.unreadable` (suffixed
  further if that name is taken), clears the block and starts that artefact
  empty. Nothing is deleted.
- **The two artefacts are independent.** A bad statements file blocks imports and
  nothing else; a bad log blocks log saves and nothing else.
- **A save is committed to memory only after the write succeeded**, so a failed
  write leaves the previous document in memory and the previous bytes on disk.
- Writes stay atomic and carry complete file protection on Apple platforms.

`LocalStoreTests` exercises this against a real temporary directory: save and
reload both artefacts, reject corrupt and newer-format JSON while preserving the
original bytes, prove a failed load blocks the next write, prove a failed save
changes neither memory nor the file, and prove one artefact's failure leaves the
other working. None of it involves a simulator.

### DoorDash archive import

`data_archive.zip` (Data → History in the web app) is read by `HustlerArchive`,
the only target that links a third-party library.

- **One entry only.** The first member whose name ends in
  `delivery_information.csv` (case-insensitive, nested paths allowed) is read
  into memory. Nothing is extracted to disk, so the archive's
  personal-information files are never written anywhere.
- **Columns**, matched exactly after lowercasing as the web app matches them:
  `order_created_time` and `actual_delivery_time` are required;
  `actual_pickup_time`, `store_name`, `total_item_count` and `order_status` are
  optional. A missing required column is an error, not an empty import.
- **Rows.** A row is skipped when `order_status` contains `cancel`, when the
  delivery time is empty, when a timestamp will not parse, or when delivery is
  not after pickup. The remaining rows become archive rows through the existing
  `csvToPipe()` path, so they are indistinguishable from rows the web app wrote.
- **Minutes.** Each delivery's window starts eight minutes before pickup and ends
  at delivery. Overlapping deliveries share the block's minutes equally, exactly
  as `toLog()` spreads them. Those minutes are the weights statement
  reconciliation later allocates by.
- **Estimates, not archive data.** The archive carries no pay or mileage. Payout
  is a documented constant (`$7.00`) and miles are `minutes / 60 × 20 mph`,
  matching the web app's current defaults; both are parameters on
  `ArchiveImporter.prepare`, so a later settings feature can supply configured
  values without changing this code. The archive's own timestamps are truncated
  to 16 characters, read as **UTC** and formatted in `America/Los_Angeles` — the
  web app's literal-`Z` conversion, which shifts wall-clock times back 7–8 hours
  and can move a delivery into the previous day or month. It is preserved
  deliberately and covered by DST and month-boundary tests, but it has **not**
  been checked against a real DoorDash archive.
- **Merge, never replace.** Rows go in through `MasterLog.merge` and its existing
  normalised-line/count-matched key, so re-importing the same archive adds
  nothing, a larger export adds only the new deliveries, and no row from a
  previous export is removed. This is a deliberate, approved divergence from the
  web app's `toLog()`, which deletes every archive row and rebuilds them.
- **Limits.** 64 MiB archive, 1,000 entries, 32 MiB delivery file, all checked
  before extraction. A `zip -e` encrypted archive opens as an `Archive` but
  lists **zero** entries, so zero iterated entries are refused as unreadable
  (encrypted or damaged) rather than reported as a missing delivery file. There
  is no public encryption flag to inspect, so the message names both
  possibilities instead of guessing.
- **Failure safety.** The whole archive is read and converted before anything is
  written, and the merged log is saved through `LocalLibrary`: a failed write
  leaves both memory and the previous file bytes untouched, and an unreadable
  master log blocks archive import until the explicit recovery described above.

Counts, which do not overlap: `rowsInspected = validRows + cancelledSkipped +
missingDeliverySkipped + invalidSkipped + droppedNonPositiveIntervals`, and
`validRows = alreadyPresent + newlyAdded`. `retainedRows` is the log's row count
before the import, and every one of those rows is still there afterwards.

`ArchiveImportTests` covers the ZIP reader on generated fixtures (deflate and
stored), exact pipe-row output, required and optional columns, malformed archives
and CSV, a missing `delivery_information.csv`, duplicate rows inside one archive,
idempotent re-import, superset merges, preserved shortcut and older archive rows,
all three limits, both DST transitions, a month-boundary rollover, overlap
sharing, negative intervals, and a blocked or unwritable master log never being
overwritten.

### Archive conversion: what was actually measured

A one-off harness (not committed, and no change to `expectations.json`) loaded
`index.html` and ran its own `csvRows()`, `loadDeliv()` and `toLog()` in Node on
the same synthetic 16-row delivery file the port was given. **All 11 rows with
parseable timestamps came out byte-identical** — date, time, zone, payout,
miles, items, minutes and placeholders — once both sides went through the same
pipe-table canonicaliser.

The two rows with unparseable timestamps diverge, on purpose:

- `new Date("garbage:00Z")` is **not** `NaN` in V8; it is 2000-01-01. The web app
  therefore keeps that row, its overlap block then spans 2000→2026, and five
  *valid* neighbouring deliveries are given 2,820,548 minutes each (940,182.5
  estimated miles). Safari/JSC may return `NaN` instead and drop the row, so the
  web behaviour here is engine-dependent.
- The port rejects any row whose timestamps do not parse and counts it in
  `invalidSkipped`, so one bad row cannot inflate its neighbours. No web
  expectation was refreshed to make this pass.

Practical consequence of the preserved UTC→Pacific conversion: a delivery the
archive writes as `2026-11-01 06:20` is stored as `2026-10-31 23:20`, so late
evening deliveries land on the previous day and a few land in the previous
month — which is the month statement reconciliation will allocate them under.

## What is deliberately NOT ported yet

Quests, the California pay guarantee, settings persistence,
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
  `apt-get install -y libcurl4 libxml2 libncurses6 libsqlite3-0 zlib1g-dev`;
  `zlib1g-dev` is what ZIPFoundation links against on Linux. The GitHub
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
| Core tests compile and pass | Proven locally via `tools/local-test.sh` (131 tests) and in CI |
| App compiles for iOS | Proven only by CI — the unsigned simulator build |
| Statement import reachable in the app | Wired to the pipeline and compiled by CI; never launched by hand on a simulator or device |
| Archive import reachable in the app | Wired and compiled by CI; never launched by hand, and never run against a real DoorDash archive |
| ZIP reader tested on real bytes | Yes — generated `.zip` fixtures built with ZIPFoundation inside `swift test`, plus one checked-in encrypted `zip -e` archive |
| Oversized / over-entry-count archives rejected | Yes, by test |
| Encrypted archive refused | Yes, by test: zero listed entries are reported as encrypted-or-damaged, and nothing is written |
| Archive conversion matches the web app | Verified for well-formed timestamps: an out-of-tree harness ran `index.html`'s `csvRows`/`loadDeliv`/`toLog` in Node on the same fixture and all 11 valid rows were byte-identical |
| Rows with invalid timestamps | Deliberate divergence, documented above: the port rejects and counts them; the web app (V8) keeps them as 2000-01-01 and corrupts neighbouring minutes |
| Installed on a physical iPhone | **No** — needs an Apple signing identity |

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
