# Hustler Native iOS — Audit and Build Plan

> **Build status updated 2026-10-28.** This file tracks implementation progress after the original audit supplied as `hustler-native-ios-audit.zip`. The original audit's source inventory, calculations, risks, migration decisions, and verification plan remain the baseline; this status update records what has actually been completed on the authorized feature branch.

| Item | Current state |
|---|---|
| Repository | [0321-ops-COS/Hustler](https://github.com/0321-ops-COS/Hustler) |
| Authorized branch | `freebuff/ce4b8907c250c30103d8993e` |
| Latest reported milestone commit | [`6b8141fe29edb649fecd43e66a38ea2a5d5eb35d`](https://github.com/0321-ops-COS/Hustler/commit/6b8141fe29edb649fecd43e66a38ea2a5d5eb35d) |
| Web app | Preserved; no changes to `index.html`, `sw.js`, or `manifest.webmanifest` in M3 |
| Merge/deploy | No merge to main and no deployment authorized or performed |

## Completed

### M0 — Native foundation / toolchain

Foundation exists under `ios-app/`, with an XcodeGen project spec and a Foundation-only Swift Package named `HustlerCore`. The app target is iOS 17+, iPhone-only. The project is generated rather than committing an `.xcodeproj`.

### M1 — Verdict and money parity

The native core ports the offer verdict/ramp rules, acceptance logic, master-log normalization/merge and parsing, and JavaScript-compatible money formatting. Regression cases pin observed web behaviour.

### M2 — Scoreboard, periods, and decline float

The native core ports Scoreboard totals, day/week/month/year grouping (Monday week starts), and decline-float states. The oracle compares rendered web-app outputs against native expectations.

### M3 — Read-only analytics — complete

Commit `6b8141fe29edb649fecd43e66a38ea2a5d5eb35d` adds the four remaining read-only analytics panels:
- Zone breakdown: order count, net per active hour, net per mile; descending net/hour with stable tie ordering.
- Hour breakdown: ascending hour buckets and the web app's 12-hour labels.
- Month breakdown: newest month first, including miles and mileage deduction.
- Tax estimate: accepted-row gross, business miles, flat configured mileage deduction, and taxable amount.

The parity fixture exercises multiple explicit zones, multiple hours and months, a row with no time, an archive row with a blank Net cell, and a declined row. The oracle captures the web app's rendered tables; drift checks compare analytics sequences in order. Existing financial code and the web app were left untouched in M3.

### Verification reported for M3

- Local `tools/local-test.sh`: **56 tests, 0 failures** (Swift 6.0.3 on Linux).
- Oracle drift: **no drift**; all eight sections passed, including analytics (3 zones, 5 hours, 3 months, 1 tax panel).
- GitHub Actions on the M3 commit: **Parity drift**, **HustlerCore tests**, and **Build iOS app** all passed. Supabase Preview was skipped as a pre-existing check.
- Not proven: a simulator run by a human, physical-device install, signing, or use on an actual shift.

## Current build boundary

M3 completes the read-only analytics port. The next substantial milestone is **B1: monthly statement import and reconciliation**. It changes how statement totals are allocated across log rows and is not yet ported. The audit identifies relevant existing web behaviour in `adjust(statements)`, `stmParse()`, and `takeStm()`; the native implementation must preserve that behaviour with golden tests before any UI is added.

**Build is paused at the B1 decision gate.** The handoff notes explicitly say B1 must start with a decision, not code. Do not implement statement reconciliation until its migration choices are confirmed. In particular, confirm:
1. Whether the native app should retain the master log as canonical pipe-table text (audit recommendation D1).
2. Whether statement reconciliation must reproduce the web app's allocation/remainder behaviour exactly, including its edge cases.
3. Whether the native app should support PDFKit page-one parsing with a paste-text fallback and no OCR (D4).
4. Whether statement data remains local-only, consistent with the no-paid-services/no-backend constraint (D5).

No real DoorDash archives, statements, or personal data belong in the repository.

## Remaining roadmap

| Milestone | Scope | Gate / notes |
|---|---|---|
| B1 / M4 | Statement import, month reconciliation, allocation parity tests | **Blocked pending the decisions above. No code started.** |
| Next | Archive / ZIP import and history | After B1; reproduce dedupe and time-zone quirks with fixtures. |
| Later | Quests, California pay guarantee, persistence, handoff/deep links, and remaining screens | Keep each as a separately scoped milestone. No backend or paid service by default. |
| Device install | Signing and install on the user's iPhone | Separate approval required; no signing material in this public repository. |

## Handoff / verification rules

- Work only on `freebuff/ce4b8907c250c30103d8993e`; never merge to `main` or deploy without explicit authorization.
- Keep the existing web app unchanged unless a future milestone explicitly authorizes a web change.
- Work only within the approved milestone. No unrelated cleanup or dependency/service spend.
- Run applicable tests and parity drift checks. Report actual command results; do not infer success from source existing.
- Commit and push only completed, verified work to the authorized branch.
- Final handoff must state summary, exact commit SHA and branch, files changed, tests/results, known issues/incomplete work, and GitHub Actions URL when available.
- Stop and report blockers rather than silently choosing unresolved migration behaviour.
