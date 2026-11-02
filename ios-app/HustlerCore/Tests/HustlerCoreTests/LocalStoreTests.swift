import XCTest
@testable import HustlerCore

/// Tests for the file layer itself: a temporary directory is the store, so these
/// exercise real reads, real writes and real bytes on disk rather than codecs or
/// stubs. Nothing here touches Application Support.
final class LocalStoreTests: XCTestCase {

    private let fileManager = FileManager.default

    /// A store over a fresh temporary directory, removed when the test ends.
    private func makeStore() throws -> LocalStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-store-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            // Restore permissions first, in case an earlier test narrowed them.
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        return LocalStore(directory: directory)
    }

    private func bytes(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// The directory itself is made read-only, so the atomic write cannot create
    /// its temporary file. Skipped rather than faked when permissions are not
    /// enforced (running as root).
    private func makeDirectoryUnwritable(_ directory: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let probe = directory.appendingPathComponent("permission-probe")
        defer { try? fileManager.removeItem(at: probe) }
        if (try? Data("x".utf8).write(to: probe)) != nil {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            throw XCTSkip("directory permissions are not enforced here (running as root?)")
        }
    }

    // MARK: - Missing files are not failures

    func testMissingFilesReadAsAbsentAndLeaveWritesOpen() throws {
        let store = try makeStore()

        XCTAssertNil(try store.load(MasterLogDocument.self, from: .masterLog))
        XCTAssertNil(try store.load(StatementStoreDocument.self, from: .statements))
        XCTAssertFalse(store.isBlocked(.masterLog))
        XCTAssertFalse(store.isBlocked(.statements))

        // A first run may start empty and save.
        XCTAssertNoThrow(try store.save(MasterLogDocument(text: Fixtures.twoRows), as: .masterLog))
        XCTAssertEqual(store.blockedArtefacts, [])
    }

    // MARK: - Round trips

    func testMasterLogRoundTripThroughTheFileLayer() throws {
        let store = try makeStore()
        let document = MasterLogDocument(text: Fixtures.statementLog([
            Fixtures.archiveLine("2026-09-05 18:00", minutes: "10")
        ]))

        try store.save(document, as: .masterLog)

        XCTAssertTrue(fileManager.fileExists(atPath: store.url(.masterLog).path))
        XCTAssertEqual(try store.load(MasterLogDocument.self, from: .masterLog), document)

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try bytes(store.url(.masterLog))) as? [String: Any]
        )
        XCTAssertEqual(json["schemaVersion"] as? Int, MasterLogDocument.currentVersion)
    }

    func testStatementStoreRoundTripThroughTheFileLayer() throws {
        let store = try makeStore()
        var book = StatementBook(monthly: ["2026-10": StatementMonth(total: 0, miles: 321.4)])
        XCTAssertEqual(book.take([Fixtures.statementCanonical]), 1)

        try store.save(StatementStoreDocument(book: book), as: .statements)
        let loaded = try XCTUnwrap(try store.load(StatementStoreDocument.self, from: .statements))

        XCTAssertEqual(loaded.book, book)
        XCTAssertEqual(loaded.monthly["2026-10"]?.miles, 321.4)
        XCTAssertEqual(loaded.statements["2026-10"]?.total, 1234.56)
    }

    func testLibraryReloadsBothArtefactsAfterRelaunch() throws {
        let store = try makeStore()
        let first = LocalLibrary(store: store)

        try first.saveLog(Fixtures.twoRows)
        try first.addStatement(
            EarningsStatement(month: "2026-10", total: 1234.56, payouts: 123),
            text: Fixtures.statementCanonical
        )

        // A fresh store and library over the same directory stand in for the next
        // app launch; nothing is carried over in memory.
        let relaunched = LocalLibrary(store: LocalStore(directory: store.directory))

        XCTAssertEqual(relaunched.status(of: .masterLog), .loaded)
        XCTAssertEqual(relaunched.status(of: .statements), .loaded)
        XCTAssertEqual(relaunched.log, first.log)
        XCTAssertEqual(relaunched.statements, first.statements)
        XCTAssertEqual(relaunched.log.rowCount, 2)
        XCTAssertEqual(
            relaunched.summaries(rows: MasterLogParser.parse(relaunched.log.text)).first?.total,
            1234.56
        )
    }

    // MARK: - Corrupt and unsupported files are refused, not reset

    func testCorruptJSONIsRejectedAndTheOriginalBytesSurvive() throws {
        let store = try makeStore()
        let corrupt = Data(#"{"schemaVersion":1,"statements":{"#.utf8)
        try corrupt.write(to: store.url(.statements))

        XCTAssertThrowsError(try store.load(StatementStoreDocument.self, from: .statements)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .unreadable(.statements))
        }

        XCTAssertEqual(try bytes(store.url(.statements)), corrupt)
        XCTAssertTrue(store.isBlocked(.statements))
    }

    func testUnsupportedSchemaIsRejectedAndTheOriginalBytesSurvive() throws {
        let store = try makeStore()
        let newer = Data(#"{"schemaVersion":7,"statements":{},"monthly":{}}"#.utf8)
        try newer.write(to: store.url(.statements))

        XCTAssertThrowsError(try store.load(StatementStoreDocument.self, from: .statements)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .unsupportedVersion(.statements, 7))
        }

        XCTAssertEqual(try bytes(store.url(.statements)), newer)
        XCTAssertTrue(store.isBlocked(.statements))
    }

    func testAFailedLoadBlocksLaterWritesToThatSameArtefact() throws {
        let store = try makeStore()
        let corrupt = Data("not json at all".utf8)
        try corrupt.write(to: store.url(.masterLog))

        XCTAssertThrowsError(try store.load(MasterLogDocument.self, from: .masterLog))

        XCTAssertThrowsError(try store.save(MasterLogDocument(text: Fixtures.twoRows), as: .masterLog)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.masterLog))
        }
        XCTAssertEqual(try bytes(store.url(.masterLog)), corrupt, "an unreadable file must never be replaced")
    }

    // MARK: - Explicit recovery

    func testRecoveryKeepsTheUnreadableBytesAndUnblocksTheArtefact() throws {
        let store = try makeStore()
        let corrupt = Data("{\"schemaVersion\":1".utf8)
        try corrupt.write(to: store.url(.statements))
        XCTAssertThrowsError(try store.load(StatementStoreDocument.self, from: .statements))

        let kept = try XCTUnwrap(try store.quarantine(.statements))

        XCTAssertEqual(try bytes(kept), corrupt, "the unreadable file is kept byte for byte")
        XCTAssertEqual(kept.lastPathComponent, "statements.json.unreadable")
        XCTAssertFalse(fileManager.fileExists(atPath: store.url(.statements).path))
        XCTAssertFalse(store.isBlocked(.statements))

        // Now the artefact can be written again, and reads back.
        let document = StatementStoreDocument(book: StatementBook())
        XCTAssertNoThrow(try store.save(document, as: .statements))
        XCTAssertEqual(try store.load(StatementStoreDocument.self, from: .statements), document)
    }

    func testRepeatedRecoveryNeverOverwritesAnEarlierCopy() throws {
        let store = try makeStore()

        try write("first", to: store.url(.masterLog))
        XCTAssertThrowsError(try store.load(MasterLogDocument.self, from: .masterLog))
        let first = try XCTUnwrap(try store.quarantine(.masterLog))

        try write("second", to: store.url(.masterLog))
        XCTAssertThrowsError(try store.load(MasterLogDocument.self, from: .masterLog))
        let second = try XCTUnwrap(try store.quarantine(.masterLog))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try bytes(first), Data("first".utf8))
        XCTAssertEqual(try bytes(second), Data("second".utf8))
    }

    func testRecoveryWithoutAFileJustUnblocks() throws {
        let store = try makeStore()
        try write("not json", to: store.url(.masterLog))
        XCTAssertThrowsError(try store.load(MasterLogDocument.self, from: .masterLog))
        try fileManager.removeItem(at: store.url(.masterLog))

        XCTAssertNil(try store.quarantine(.masterLog))
        XCTAssertFalse(store.isBlocked(.masterLog))
        XCTAssertNoThrow(try store.save(MasterLogDocument(text: Fixtures.twoRows), as: .masterLog))
    }

    // MARK: - Isolation between the two artefacts

    func testOneUnreadableFileDoesNotAffectTheOther() throws {
        let store = try makeStore()
        let corrupt = Data("garbage".utf8)
        try corrupt.write(to: store.url(.statements))

        XCTAssertThrowsError(try store.load(StatementStoreDocument.self, from: .statements))
        XCTAssertTrue(store.isBlocked(.statements))
        XCTAssertFalse(store.isBlocked(.masterLog))

        // The master log still saves and reloads normally.
        let log = MasterLogDocument(text: Fixtures.twoRows)
        XCTAssertNoThrow(try store.save(log, as: .masterLog))
        XCTAssertEqual(try store.load(MasterLogDocument.self, from: .masterLog), log)
        XCTAssertEqual(try bytes(store.url(.statements)), corrupt)
    }

    func testLibraryKeepsStatusPerArtefactAndBlocksOnlyTheBrokenOne() throws {
        let store = try makeStore()
        try write(Fixtures.twoRows, to: store.url(.masterLog))
        try write("garbage", to: store.url(.statements))

        let library = LocalLibrary(store: store)

        XCTAssertEqual(library.status(of: .masterLog), .unavailable(
            LocalStore.Failure.unreadable(.masterLog).localizedDescription
        ))
        XCTAssertTrue(library.isUnavailable(.masterLog))
        XCTAssertTrue(library.isUnavailable(.statements))

        // Saving the broken log is refused...
        XCTAssertThrowsError(try library.saveLog(Fixtures.twoRows)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.masterLog))
        }
        // ...and the log's bytes on disk are still the raw text that was there.
        XCTAssertEqual(try bytes(store.url(.masterLog)), Data(Fixtures.twoRows.utf8))
    }

    func testAnUnreadableStatementStoreBlocksImportsButNotTheLog() throws {
        let store = try makeStore()
        try write("garbage", to: store.url(.statements))
        let library = LocalLibrary(store: store)

        XCTAssertThrowsError(
            try library.addStatement(
                EarningsStatement(month: "2026-10", total: 1234.56, payouts: 123),
                text: Fixtures.statementCanonical
            )
        ) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.statements))
        }
        XCTAssertEqual(library.statements, StatementBook(), "memory must not change on a refused import")

        // The master log is unaffected by the statements failure.
        XCTAssertNoThrow(try library.saveLog(Fixtures.twoRows))
        XCTAssertEqual(library.log.rowCount, 2)
        XCTAssertEqual(try bytes(store.url(.statements)), Data("garbage".utf8))
    }

    func testRecoveryResetsOnlyTheRecoveredArtefact() throws {
        let store = try makeStore()
        let healthy = LocalLibrary(store: store)
        try healthy.saveLog(Fixtures.twoRows)
        try healthy.addStatement(
            EarningsStatement(month: "2026-10", total: 1234.56, payouts: 123),
            text: Fixtures.statementCanonical
        )
        let statementsBefore = healthy.statements

        // Corrupt the master log only.
        try write("garbage", to: store.url(.masterLog))
        let reloaded = LocalLibrary(store: store)
        XCTAssertTrue(reloaded.isUnavailable(.masterLog))
        XCTAssertFalse(reloaded.isUnavailable(.statements))
        XCTAssertEqual(reloaded.statements, statementsBefore)

        let kept = try XCTUnwrap(try reloaded.recover(.masterLog))

        XCTAssertEqual(try bytes(kept), Data("garbage".utf8))
        XCTAssertEqual(reloaded.status(of: .masterLog), .missing)
        XCTAssertEqual(reloaded.log.rowCount, 0)
        XCTAssertEqual(reloaded.statements, statementsBefore, "recovery must not touch the other artefact")
        XCTAssertNoThrow(try reloaded.saveLog(Fixtures.twoRows))
    }

    // MARK: - A failed save changes nothing

    func testAFailedSaveLeavesMemoryUnchanged() throws {
        let store = try makeStore()
        let library = LocalLibrary(store: store)

        // Make the master-log path impossible to write: a directory where the
        // file should be.
        try fileManager.createDirectory(at: store.url(.masterLog), withIntermediateDirectories: false)

        XCTAssertThrowsError(try library.saveLog(Fixtures.twoRows)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .unwritable(.masterLog))
        }

        XCTAssertEqual(library.log.rowCount, 0, "a failed save must not look like a successful one")
        XCTAssertEqual(library.log.text, MasterLog.header)
    }

    func testAFailedSaveDoesNotReplaceTheStoredFile() throws {
        let store = try makeStore()
        let library = LocalLibrary(store: store)
        try library.saveLog(Fixtures.twoRows)

        let before = try bytes(store.url(.masterLog))
        try makeDirectoryUnwritable(store.directory)

        XCTAssertThrowsError(try library.saveLog(Fixtures.statementCanonical)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .unwritable(.masterLog))
        }

        XCTAssertEqual(try bytes(store.url(.masterLog)), before)
        XCTAssertEqual(library.log.rowCount, 2)
    }

    func testAFailedStatementWriteLeavesTheBookAndFileUnchanged() throws {
        let store = try makeStore()
        let library = LocalLibrary(store: store)
        try library.addStatement(
            EarningsStatement(month: "2026-10", total: 1234.56, payouts: 123),
            text: Fixtures.statementCanonical
        )

        let before = try bytes(store.url(.statements))
        let beforeBook = library.statements
        try makeDirectoryUnwritable(store.directory)

        XCTAssertThrowsError(
            try library.addStatement(
                EarningsStatement(month: "2026-11", total: 88, payouts: 0),
                text: Fixtures.statementNoCount
            )
        ) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .unwritable(.statements))
        }

        XCTAssertEqual(
            library.statements,
            beforeBook,
            "the failed import must leave the book exactly as it was"
        )
        XCTAssertNotNil(library.statements.statements["2026-10"], "the stored month is still there")
        XCTAssertNil(library.statements.statements["2026-11"], "the November import must not appear in memory")
        XCTAssertEqual(try bytes(store.url(.statements)), before)
    }

    // MARK: - Normalisation still applies on the way in

    func testSavedLogIsCanonicalisedBeforeItIsStored() throws {
        let store = try makeStore()
        let library = LocalLibrary(store: store)

        let document = try library.saveLog(Fixtures.csvRows)

        XCTAssertTrue(document.text.hasPrefix(MasterLog.header))
        XCTAssertEqual(document.rowCount, 2)
        XCTAssertEqual(try store.load(MasterLogDocument.self, from: .masterLog), document)
    }
}
