import Foundation

/// Synthetic fixtures, identical to the inputs in
/// `ios-app/tools/parity/oracle.mjs`. No real earnings data.
enum Fixtures {

    /// Copied literally from the web app's `HDRM`, so the test does not compare
    /// the constant against itself.
    static let headerLiteral = "| Date | Payout | Miles | Items | Per Mile | Net | Hourly | Verdict | Acceptance rate | Choice | Slack | Zone | Minutes | Source |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"

    static let empty = ""

    static let headerOnly = headerLiteral

    static let firstShortcutRow = "| 2026-10-27 14:46 | 26.50 | 9.1 | 6 | 2.91 | 22.42 | 30.06 | TAKE IT | 80.00 | Accept | 15.25 |"

    static let secondShortcutRow = "| 2026-10-27 15:10 | 4.25 | 6.2 | 2 | 0.69 | -0.31 | -1.20 | SKIP | 89.00 | Declined | 0 |"

    static let twoRows = firstShortcutRow + "\n" + secondShortcutRow

    static let rowNumbered = "| 1 | 2026-10-26 09:00 | 12.00 | 4.0 | 3 | 3.00 | 9.06 | 27.18 | TAKE IT | 89 | Accept | 20 |"

    static let duplicatedRows = firstShortcutRow + "\n" + firstShortcutRow

    static let archiveRow = "| 2026-10-25 18:00 | 7.00 | 5.0 | 2 | 1.40 | 5.10 | 20.40 |  |  | Accepted |  | Temecula | 30 | archive |"
    static let archiveRowLater = "| 2026-10-25 19:30 | 7.00 | 5.0 | 2 | 1.40 | 5.10 | 20.40 |  |  | Accepted |  | Temecula | 30 | archive |"

    static let archiveDupes = archiveRow + "\n" + archiveRow

    static let csvRows = "date,time,zone,payout,miles,items,minutes,verdict,choice\n"
        + "2026-10-24,12:10,Murrieta,8.50,3.2,2,18,Accept,Accepted\n"
        + "2026-10-24,12:40,Murrieta,4.00,5.1,1,22,Decline,Declined"

    static let moneyCells = "| 2026-10-23 11:00 | $1,234.50 | 9.1 | 2 | 135.66 | 1,200.00 | 100.00 | TAKE IT | 89.00 | Accept | 5 |"

    static let malformed = "| 2026-10-22 10:00 | n/a | 3 | 1 | 1 | 1 | 1 | TAKE IT | 89 | Accept | 0 |\n"
        + "| not-a-date | 5 | 3 | 1 | 1 | 1 | 1 | SKIP | 89 | Accept | 0 |"

    static let derivedMinutes = "| 2026-10-21 12:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT | 89 | Accept | 0 |"

    static let rateOlderAndNewest = "| 2026-10-20 10:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT | 92.00 | Accept | 0 |\n"
        + "| 2026-10-27 10:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT | 87.50 | Accept | 0 |"

    static let rateBlankNewest = "| 2026-10-26 10:00 | 9.00 | 4.0 | 2 | 2.25 | 6.66 | 20.00 | TAKE IT | 91.00 | Accept | 0 |\n"
        + "| 2026-10-27 10:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT |  | Accept | 0 |"

    static let rateArchiveNewest = "| 2026-10-26 10:00 | 9.00 | 4.0 | 2 | 2.25 | 6.66 | 20.00 | TAKE IT | 91.00 | Accept | 0 |\n"
        + archiveRowLater

    static let csvLinePlain = "2026-10-27,14:46,Murrieta,26.50,9.1,6,30,TAKE IT,Accept"
    static let csvLineShortcut = "2026-10-27,14:46,Murrieta,26.50,9.1,6,30,TAKE IT,Accept,shortcut,2.91,22.42,30.06,x,15.25"
    static let csvLineInvalid = "not,a,valid,row"
}
