import Foundation
import SQLite3

enum ThingsDatabaseError: LocalizedError {
    case notFound(String)
    case copyFailed(String)
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path): return "Things 3 database not found at \(path)"
        case .copyFailed(let message): return "Could not copy Things database: \(message)"
        case .openFailed(let message): return "Could not open Things database: \(message)"
        case .queryFailed(let message): return "Things query failed: \(message)"
        }
    }
}

enum ThingsDatabase {
    static func defaultDatabaseURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let group = home
            .appendingPathComponent("Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac")
        let candidates = [
            group.appendingPathComponent("ThingsData-TDMSC/Things Database.thingsdatabase/main.sqlite"),
            group.appendingPathComponent("Things Database.thingsdatabase/main.sqlite")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    static func loadSnapshot(from databaseURL: URL = defaultDatabaseURL()) throws -> ThingsSnapshot {
        let copied = try copyForReading(databaseURL)
        defer { try? FileManager.default.removeItem(at: copied.deletingLastPathComponent()) }
        return try readSnapshot(at: copied)
    }

    private static func copyForReading(_ source: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw ThingsDatabaseError.notFound(source.path)
        }
        let dir = fm.temporaryDirectory.appendingPathComponent("ember-things-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("main.sqlite")
            try fm.copyItem(at: source, to: dest)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: source.path + suffix)
                if fm.fileExists(atPath: sidecar.path) {
                    try fm.copyItem(at: sidecar, to: URL(fileURLWithPath: dest.path + suffix))
                }
            }
            return dest
        } catch {
            throw ThingsDatabaseError.copyFailed(error.localizedDescription)
        }
    }

    private static func readSnapshot(at sqliteURL: URL) throws -> ThingsSnapshot {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(sqliteURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw ThingsDatabaseError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
          t.uuid,
          t.title,
          t.notes,
          t.type,
          t.status,
          t.deadline,
          t.startDate,
          t.project,
          t.heading,
          t.userModificationDate,
          area.title AS areaTitle,
          project.title AS projectTitle,
          heading.title AS headingTitle
        FROM TMTask t
        LEFT JOIN TMArea area ON t.area = area.uuid
        LEFT JOIN TMTask project ON t.project = project.uuid
        LEFT JOIN TMTask heading ON t.heading = heading.uuid
        WHERE t.trashed = 0
          AND t.status = 0
          AND t.type IN (0, 1)
        ORDER BY t."index" ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ThingsDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var projects: [ThingsProject] = []
        var tasks: [ThingsTask] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let uuid = columnText(statement, 0)
            let title = columnText(statement, 1)
            let notes = columnText(statement, 2)
            let type = Int(sqlite3_column_int(statement, 3))
            let status = ThingsStatus(rawValue: Int(sqlite3_column_int(statement, 4))) ?? .incomplete
            let deadline = ThingsDate.decodePacked(sqlite3_column_int64(statement, 5))
            let startDate = ThingsDate.decodePacked(sqlite3_column_int64(statement, 6))
            let projectId = columnText(statement, 7)
            let modified = sqlite3_column_double(statement, 9)
            let areaTitle = columnText(statement, 10)
            let projectTitle = columnText(statement, 11)
            let headingTitle = columnText(statement, 12)

            if type == ThingsItemType.project.rawValue {
                projects.append(
                    ThingsProject(
                        uuid: uuid,
                        title: title.isEmpty ? "(untitled project)" : title,
                        notes: notes,
                        area: areaTitle.isEmpty ? nil : areaTitle,
                        deadline: deadline,
                        status: status.label,
                        modifiedAt: modified == 0 ? nil : modified
                    )
                )
            } else if type == ThingsItemType.toDo.rawValue {
                tasks.append(
                    ThingsTask(
                        uuid: uuid,
                        title: title.isEmpty ? "(untitled task)" : title,
                        notes: notes,
                        projectId: projectId.isEmpty ? nil : projectId,
                        projectTitle: projectTitle.isEmpty ? nil : projectTitle,
                        heading: headingTitle.isEmpty ? nil : headingTitle,
                        deadline: deadline,
                        startDate: startDate,
                        status: status.label
                    )
                )
            }
        }

        return ThingsSnapshot(projects: projects, tasks: tasks, generatedAt: Date())
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }
}
