# Hustler Native iOS — Audit and Build Plan

> **Build status updated 2026-11-03** against the code at `aeb5b62` (merge of
> PR #42). The original audit's source inventory, calculations, risks,
> migration decisions and verification plan remain the baseline; this file
> records what the code now does.

| Item | Current state |
|---|---|
| Repository | [0321-ops-COS/Hustler](https://github.com/0321-ops-COS/Hustler) |
| Branch checked | `freebuff/f042ca7c`; the S4-1 work merged from `freebuff/76a5641d` |
| Code checked | `105129f`, 2026-11-03 |
| Web app | Unchanged: `index.html`, `sw.js` and `manifest.webmanifest` |
| Merge/deploy | Merged through PR #44 (merge commit `105129f`, 2026-11-03); no deployment. `origin/main` is `105129f` and contains the whole authorized branch |

A row is **done** only when the native screen exists and a core test covers its
logic. Everything else is **partial**, with the missing piece named. Test counts
are test functions in the named file, not total assertions.

## Status by web section

| Web feature | Native screen | Core type | Tests | Status | What is left |
|---|---|---|---|---|---|
| `#dash` Start card, master tile, decline float, quests, day/week/month/year block, tiles, followed-the-call ring card and archive note, California card, verdict matrix, zone/hour/month/tax panels | `HomeView`, `AnalyticsPanels`, `CaliforniaCardView` | `HomeStartCard`, `HomeMasterTile`, `HomeFloat`, `Quests`, `HomeFollowCard`, `HomePeriodBoard`, `HomeTiles`, `CAPayGuarantee`, `CAWeekEntry`, `CAGuaranteeViewModel`, `VerdictMatrix`, `Analytics` | HomeHeaderCardsTests (12), HomeFloatTests (9), QuestsTests (6), HomeFollowCardTests (7), HomePeriodBoardTests (4), HomeTilesTests (8), CAPayGuaranteeTests (8), CAEntriesTests (7), VerdictMatrixTests (3), AnalyticsTests (9) | done | — |
| `#calc` six-field offer check, log-rate helper, verdict card | `CheckView` | `CheckModel` | CheckModelTests (9) | done | — |
| `#whatif` replay of the whole log under typed numbers | `WhatIfView` | `WhatIf` | WhatIfTests (5) | done | — |
| `#data` offers log, monthly statements, DoorDash archive, master file, Delete data | `DataView` | `OffersImporter`, `DataPageCopy`, `DataDeleteAction`, `DataWipe`, `StatementImporter`, `ArchiveImporter` | OffersImportTests (5), DataPageTests (6), StatementImportTests (17), ArchiveImportTests (31), LocalStoreTests (18) | partial | Five delete actions, not six: `data-wipe="files"` (Delete saved original files) has no button, because the app never keeps the uploaded file. |
| `#log` scope control, master-log editor, Analyze and save, Clear for today, demo, Paste copied rows, column check | `LogView` | `LogPageModel`, `LogCheck`, `LogScope` | LogPageTests (5), LogScopeTests (11), MasterLogCodecTests (12) | done | — (the web's hint text linking to Data is not reproduced; no control is missing) |
| `#earn` statement tiles, month table, day bars, notes | `EarningsView` | `EarningsPage` | EarningsPageTests (4) | done | — |
| `#hist` archive tiles, month/hour/weekday/store tables | `HistoryView` | `HistoryPage`, `HistoryViewModel`, `ArchiveRow`, `HistoryCopy` | HistoryTests (4) | done | — |
| `#sync` Handoff card: export, import, Copy AI brief | `HandoffView` | `HandoffFile`, `HandoffImportPlan`, `AIBrief` | HandoffFileTests (6), AIBriefTests (5) | partial | The Cloud sync card and the Shortcut link-up card are absent, and nothing handles an incoming URL. The web app's app-icon card is unnecessary (the icon ships in the bundle). |
| `#settings` Shortcut card, numeric fields, Rebuild archive rows, Pages | `SettingsView` | `AppSettings`, `SettingsStore`, `PagePins`, `SettingsField`, `SettingsEdit`, `AppPage`, `ShortcutRoute`, `ArchiveRebuild` | AppSettingsTests (5), SettingsEditingTests (4), ArchiveRebuildTests (5) | partial | The Testing card ("Send a test offer", "Test cloud connection") is absent. The numeric `DEF` fields are editable here and saved to `settings.json`; the web app keeps its `#fields` editor hidden, so the native tab exposes more than the web page. |
| Nav tab bar and `PGS` / `applyPins()` page switches | `RootView` | `AppScreen`, `NavigationPlan` | NavigationTests (6) | done | — |

## Deliberately not ported

Every item below is **not planned** until a backend decision is made. The app is
device-only: no account, no network, no paid service.

| Item | Web source | Why |
|---|---|---|
| Cloud sync: sign-in, account storage, Sync now / Sign out | `#cloudCard`, `sb_*`, sync handlers | No backend decision yet. Settings, log and statements live in Application Support only. |
| Pulling offers from the shortcut over the network | `pullOffers()`, the `visibilitychange` poll, `#pullOffers` | No backend decision yet. The surviving path is the shortcut copying its row and "Paste copied rows" in Log. |
| Incoming deep links | `CFG.appUrl`, link entry into the app | No backend decision yet. Nothing in the app handles `onOpenURL`. |
| Test offer and cloud test buttons | `#tstLink`, `#tstCloud` | Both test the backend link that does not exist; a device-only build has nothing to test. |
| Deleting saved original files | `data-wipe="files"` | No backend decision yet. Originals were kept in an account folder on the web; the native import reads the picked file and writes only JSON documents, so there is nothing to delete (see `DataPage.swift`). |

## Preserved defects

- **B1**: statement reconciliation re-prices archive rows only, so accepted
  shortcut pay in the same month is added on top of the statement total. Pinned
  by `StatementReconcilerTests.b1_shortcut_ignored`.
- **B6**: 15-column `shortcut` CSVs still lose Zone and Minutes in
  `csvToPipe`. Pinned by `MasterLogCodecTests`.
- **B11**: with no acceptance data the float still reports a number from the
  default 89% instead of asking for a rate. Pinned by `DeclineFloatTests`.

The other B-numbered defects named in the original audit (B2, B3, B5, B9, B10)
are **unknown** here: that audit document is not in this repository, so neither
their definitions nor their current status can be checked from the code.

## Remaining work

| Item | Gate |
|---|---|
| Settings Testing card; cloud sync; pull offers; deep links | Blocked on a backend decision, not on native work |
| Device install | Signing and install on the user's iPhone; separate approval, no signing material in this public repository |

## Verification run for this update

- `ios-app/tools/local-test.sh`: **281 tests, 0 failures** (Xcode toolchain on
  macOS, 2026-11-03). The 7 new functions are `HomeFollowCardTests`.
- `node ios-app/tools/parity/drift.mjs`: **no drift**, exit 0; all eleven checks
  passed (verdict 16, money 9, acceptance 3, period keys 10, scoreboard 2, period
  totals 16, float 27, analytics 3 zones / 5 hours / 3 months / 1 tax panel,
  statements 19 parsed + 7 rejected, allocations 9, store 3).
- Not verified: the SwiftUI target was not compiled here (the script tests the
  package only); no simulator or device run, no signing, no real DoorDash
  statement or archive.

## Handoff / verification rules

- Work only on the branch you are given; never merge to `main` or deploy from a task branch. Any merge happens through the repository owner's PR.
- Keep the existing web app unchanged unless a future milestone explicitly authorizes a web change.
- Work only within the approved milestone. No unrelated cleanup or dependency/service spend.
- Run applicable tests and parity drift checks. Report actual command results; do not infer success from source existing.
- Commit and push only completed, verified work to the authorized branch.
- Final handoff must state summary, exact commit SHA and branch, files changed, tests/results, known issues/incomplete work, and GitHub Actions URL when available.
- Stop and report blockers rather than silently choosing unresolved migration behaviour.
