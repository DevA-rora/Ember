import Foundation

enum ThingsItemType: Int, Codable, Sendable {
    case toDo = 0
    case project = 1
    case heading = 2
}

enum ThingsStatus: Int, Codable, Sendable {
    case incomplete = 0
    case canceled = 2
    case completed = 3

    var label: String {
        switch self {
        case .incomplete: return "open"
        case .canceled: return "canceled"
        case .completed: return "completed"
        }
    }
}

struct ThingsProject: Codable, Equatable, Identifiable, Sendable {
    var uuid: String
    var title: String
    var notes: String
    var area: String?
    var deadline: String?
    var status: String
    var modifiedAt: TimeInterval?
    var sortIndex: Int = 0

    var id: String { uuid }
}

struct ThingsTask: Codable, Equatable, Identifiable, Sendable {
    var uuid: String
    var title: String
    var notes: String
    var projectId: String?
    var projectTitle: String?
    var heading: String?
    var deadline: String?
    var startDate: String?
    var status: String
    /// Things `TMTask.index` — manual order within project/inbox.
    var sortIndex: Int = 0
    /// Things `TMTask.start`: 0=Inbox, 1=Anytime, 2=Someday.
    var start: Int = 1

    var id: String { uuid }
    var isInbox: Bool { start == 0 }
}

struct ThingsSnapshot: Equatable, Sendable {
    var projects: [ThingsProject]
    var tasks: [ThingsTask]
    var generatedAt: Date
}

struct ThingsMeta: Codable, Equatable, Sendable {
    var syncedAt: Date
    var projectCount: Int
    var taskCount: Int
    var source: String
    /// SHA-256 of the markdown at last sync. Optional for backward compatibility
    /// with documents written before change detection existed.
    var contentHash: String?
}

struct ThingsContextDocument: Codable, Equatable, Sendable {
    var markdown: String
    var generatedAt: Date
    var syncedAt: Date
    var projectCount: Int
    var taskCount: Int
    var source: String
    /// SHA-256 of `markdown`. Used to skip no-op Firestore writes.
    var contentHash: String?
}

enum ThingsDate {
    /// Things stores `startDate` / `deadline` as bit-packed integers:
    /// 12-bit year, 4-bit month, 5-bit day, 7-bit padding.
    static func decodePacked(_ packed: Int64) -> String? {
        guard packed != 0 else { return nil }
        let year = Int(packed >> 16)
        let month = Int((packed >> 12) & 0xF)
        let day = Int((packed >> 7) & 0x1F)
        guard year >= 2000, year <= 2100, (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum FirestorePaths {
    /// Parent document. Subcollections `projects` and `tasks` hang off this document
    /// because Firestore cannot nest collections under collections.
    static func current(uid: String) -> String { "users/\(uid)/things/current" }
    static func project(uid: String, uuid: String) -> String { "users/\(uid)/things/current/projects/\(uuid)" }
    static func task(uid: String, uuid: String) -> String { "users/\(uid)/things/current/tasks/\(uuid)" }
    static func projectsCollection(uid: String) -> String { "users/\(uid)/things/current/projects" }
    static func tasksCollection(uid: String) -> String { "users/\(uid)/things/current/tasks" }
    static func profile(uid: String) -> String { "users/\(uid)/profile/current" }
}

enum SeedFixture {
    static let project = ThingsProject(
        uuid: "seed-ember-project",
        title: "Ember",
        notes: "First-step fixture used to prove Firebase Auth, Firestore, and AI Logic before live Things 3 sync.",
        area: "Development",
        deadline: "2026-09-07",
        status: ThingsStatus.incomplete.label,
        modifiedAt: nil,
        sortIndex: 0
    )

    static let task = ThingsTask(
        uuid: "seed-ember-task",
        title: "Ship WatchPaths sync",
        notes: "WatchPaths should upsert the Things 3 SQL database into Firestore whenever it changes.",
        projectId: project.uuid,
        projectTitle: project.title,
        heading: "Firebase",
        deadline: "2026-09-07",
        startDate: nil,
        status: ThingsStatus.incomplete.label,
        sortIndex: 0,
        start: 1
    )

    static var snapshot: ThingsSnapshot {
        ThingsSnapshot(projects: [project], tasks: [task], generatedAt: Date())
    }
}
