import XCTest
import GRDB
@testable import WhoopStore

/// A foreign database must not be deleted or replaced. Opening it fails the migrator; Nutry keeps the
/// original, copies it to `.bak-<date>`, and serves an empty in-memory store for this launch.
final class ForeignDatabaseQuarantineTests: XCTestCase {

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("noop-quarantine-\(UUID().uuidString).sqlite").path
    }

    private func tableNames(at path: String) throws -> Set<String> {
        let q = try DatabaseQueue(path: path)
        return try q.read { db in
            try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }

    private func cleanup(_ path: String) {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        for s in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where s.hasPrefix(base) {
            try? fm.removeItem(atPath: (dir as NSString).appendingPathComponent(s))
        }
    }

    func testForeignDatabaseIsKeptAndStoreFallsBackToMemory() async throws {
        let path = tempPath()
        defer { cleanup(path) }

        let raw = try DatabaseQueue(path: path)
        try await raw.write { db in
            try db.execute(sql: "CREATE TABLE device (id TEXT PRIMARY KEY, mac TEXT, name TEXT, firstSeen INTEGER, lastSeen INTEGER)")
            try db.execute(sql: "CREATE TABLE hrSample (deviceId TEXT, ts INTEGER, bpm INTEGER)")
            try db.execute(sql: "INSERT INTO device (id, name) VALUES ('foreign', 'WHOOP')")
        }
        _ = raw
        XCTAssertFalse(try tableNames(at: path).contains("grdb_migrations"),
                       "precondition: a foreign DB has no grdb_migrations")

        let store = try await WhoopStore(path: path)
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("grdb_migrations"), "safe mode still migrates an empty memory store")

        let onDisk = try tableNames(at: path)
        XCTAssertFalse(onDisk.contains("grdb_migrations"), "the original file was not migrated in place over the foreign rows")
        let names = try DatabaseQueue(path: path).read { db in
            try String.fetchAll(db, sql: "SELECT name FROM device")
        }
        XCTAssertEqual(names, ["WHOOP"])

        let dir = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir)
        XCTAssertTrue(siblings.contains { $0.hasPrefix(base + ".bak-") },
                      "a dated copy of the original was written")
        XCTAssertFalse(siblings.contains { $0.hasPrefix(base + ".incompatible-") },
                       "the original was not moved aside")
    }

    func testValidGrdbBackupIsNotQuarantined() async throws {
        let path = tempPath()
        defer { cleanup(path) }

        // A real GRDB store (migrations applied), then reopened.
        do {
            let store = try await WhoopStore(path: path)
            try await store.upsertDevice(id: "mine", mac: nil, name: "WHOOP")
        }
        let store = try await WhoopStore(path: path)
        let reopenedTables = try await store.tableNames()
        XCTAssertTrue(reopenedTables.contains("grdb_migrations"))

        let dir = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir)
        XCTAssertFalse(siblings.contains { $0.hasPrefix(base + ".bak-") },
                       "a valid GRDB DB must not be treated as a failed open")
    }
}
