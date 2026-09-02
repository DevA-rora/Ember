import Foundation

/// Where a task falls on the Eisenhower urgent/important matrix, used both for
/// the session-start suggestion and the "Not yet" → Eisenhower redirect flow.
enum EisenhowerTier: Int, Comparable, Hashable, Sendable {
    case urgentImportant = 0
    case important = 1
    case urgent = 2
    case neither = 3

    static func < (lhs: EisenhowerTier, rhs: EisenhowerTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct TaskSuggestion: Equatable, Sendable {
    var task: ThingsTask
    var tier: EisenhowerTier
    /// Human-readable justification, e.g. "Overdue by 2 days" or "Next up in Ember".
    var reason: String
}

/// Deterministic task suggestion logic — no model call, so it's instant, free,
/// and stable across sessions. Uses only fields already synced from Things:
/// `deadline`, `startDate`, `start` (0=Inbox/1=Anytime/2=Someday), `sortIndex`,
/// and the parent project's `deadline`.
enum TaskSuggester {
    /// The single best task to open a session with.
    static func suggest(from snapshot: ThingsSnapshot, now: Date = Date()) -> TaskSuggestion? {
        rankedCandidates(from: snapshot, now: now, limit: 1).first
    }

    /// Full ranking, most urgent/important first. Powers `ember-sync --suggest`
    /// and (later) the Eisenhower task-pick flow.
    static func rankedCandidates(
        from snapshot: ThingsSnapshot,
        now: Date = Date(),
        limit: Int = 5
    ) -> [TaskSuggestion] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let projectDeadlines = Dictionary(uniqueKeysWithValues: snapshot.projects.compactMap { project in
            date(from: project.deadline, calendar: calendar).map { (project.uuid, $0) }
        })

        let ranked = snapshot.tasks
            .compactMap { task in scoredCandidate(for: task, today: today, calendar: calendar, projectDeadlines: projectDeadlines) }
            .sorted(by: isRankedBefore)

        return Array(ranked.prefix(limit)).map(\.suggestion)
    }

    /// Groups every open (non-Someday) task by Eisenhower tier, for the
    /// "Not yet" → "pick something else" redirect.
    static func tiered(from snapshot: ThingsSnapshot, now: Date = Date()) -> [EisenhowerTier: [TaskSuggestion]] {
        Dictionary(grouping: rankedCandidates(from: snapshot, now: now, limit: Int.max), by: \.tier)
    }

    // MARK: - Scoring

    private struct ScoredCandidate {
        let suggestion: TaskSuggestion
        let deadlineDays: Int
        let isInbox: Bool
        let sortIndex: Int
    }

    private static func scoredCandidate(
        for task: ThingsTask,
        today: Date,
        calendar: Calendar,
        projectDeadlines: [String: Date]
    ) -> ScoredCandidate? {
        guard task.start != 2 else { return nil } // exclude Someday

        let ownDeadline = date(from: task.deadline, calendar: calendar)
        let projectDeadline = task.projectId.flatMap { projectDeadlines[$0] }
        let usesProjectDeadline = ownDeadline == nil && projectDeadline != nil
        let effectiveDeadline = ownDeadline ?? projectDeadline
        let deadlineDays = effectiveDeadline.map { daysBetween(today, $0, calendar: calendar) }
        let startDate = date(from: task.startDate, calendar: calendar)
        let hasProject = !(task.projectId?.isEmpty ?? true)

        let tier = tier(deadlineDays: deadlineDays, startDate: startDate, today: today, calendar: calendar, hasProject: hasProject)
        let reasonText = reason(
            task: task,
            deadlineDays: deadlineDays,
            usesProjectDeadline: usesProjectDeadline,
            startDate: startDate,
            today: today,
            calendar: calendar
        )

        return ScoredCandidate(
            suggestion: TaskSuggestion(task: task, tier: tier, reason: reasonText),
            deadlineDays: deadlineDays ?? .max,
            isInbox: task.isInbox,
            sortIndex: task.sortIndex
        )
    }

    private static func isRankedBefore(_ lhs: ScoredCandidate, _ rhs: ScoredCandidate) -> Bool {
        if lhs.suggestion.tier != rhs.suggestion.tier { return lhs.suggestion.tier < rhs.suggestion.tier }
        if lhs.deadlineDays != rhs.deadlineDays { return lhs.deadlineDays < rhs.deadlineDays }
        if lhs.isInbox != rhs.isInbox { return !lhs.isInbox } // prefer Anytime over Inbox
        return lhs.sortIndex < rhs.sortIndex
    }

    private static func tier(
        deadlineDays: Int?,
        startDate: Date?,
        today: Date,
        calendar: Calendar,
        hasProject: Bool
    ) -> EisenhowerTier {
        if let deadlineDays, deadlineDays <= 3 {
            return .urgentImportant
        }
        if let startDate, calendar.isDate(startDate, inSameDayAs: today) {
            return hasProject ? .urgentImportant : .urgent
        }
        return hasProject ? .important : .neither
    }

    private static func reason(
        task: ThingsTask,
        deadlineDays: Int?,
        usesProjectDeadline: Bool,
        startDate: Date?,
        today: Date,
        calendar: Calendar
    ) -> String {
        if let days = deadlineDays {
            let subject = usesProjectDeadline ? (task.projectTitle.map { "\($0) is" } ?? "The project is") : "This is"
            if days < 0 { return "\(subject) overdue by \(abs(days)) day\(abs(days) == 1 ? "" : "s")" }
            if days == 0 { return "\(subject) due today" }
            return "\(subject) due in \(days) day\(days == 1 ? "" : "s")"
        }
        if let startDate, calendar.isDate(startDate, inSameDayAs: today) {
            return "Scheduled for today"
        }
        if let projectTitle = task.projectTitle {
            return "Next up in \(projectTitle)"
        }
        return "Sitting in your Anytime list"
    }

    // MARK: - Date helpers

    /// Parses Things' `YYYY-MM-DD` strings via raw components (not a `DateFormatter`
    /// with a timezone) so the day never shifts relative to the packed value.
    private static func date(from string: String?, calendar: Calendar) -> Date? {
        guard let string else { return nil }
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    private static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
