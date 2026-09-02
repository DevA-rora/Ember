import Foundation

enum ThingsContextFormatter {
    static func markdown(from snapshot: ThingsSnapshot) -> String {
        var lines: [String] = []
        lines.append("# Current Things 3 work")
        lines.append("")
        lines.append("Generated: \(iso(snapshot.generatedAt))")
        lines.append("Open projects: \(snapshot.projects.count). Open tasks: \(snapshot.tasks.count).")
        lines.append("Use this as the source of truth for what the user is working on, including titles, notes, and deadlines.")
        lines.append("")

        let tasksByProject = Dictionary(grouping: snapshot.tasks.filter { $0.projectId != nil }) { $0.projectId! }
        let inbox = snapshot.tasks.filter(\.isInbox).sorted(by: sortByIndex)
        let anytime = snapshot.tasks.filter { $0.start == 1 && ($0.projectId == nil || $0.projectId?.isEmpty == true) }
            .sorted(by: sortByIndex)
        let someday = snapshot.tasks.filter { $0.start == 2 && ($0.projectId == nil || $0.projectId?.isEmpty == true) }
            .sorted(by: sortByIndex)
        let projectById = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.uuid, $0) })

        if !snapshot.projects.isEmpty {
            lines.append("## Projects")
            for project in snapshot.projects.sorted(by: sortProjectsByIndex) {
                lines.append("")
                lines.append("### \(project.title)")
                if let deadline = project.deadline {
                    lines.append("- Deadline: \(deadline)")
                }
                if let area = project.area, !area.isEmpty {
                    lines.append("- Area: \(area)")
                }
                let notes = clipped(project.notes)
                if !notes.isEmpty {
                    lines.append("- Notes: \(notes)")
                }
                let nested = (tasksByProject[project.uuid] ?? []).sorted(by: sortByIndex)
                if nested.isEmpty {
                    lines.append("- Tasks: none open")
                } else {
                    lines.append("- Tasks:")
                    for task in nested {
                        lines.append(contentsOf: taskBullet(task, indent: 2))
                    }
                }
            }
        }

        let orphanProjectIds = Set(tasksByProject.keys).subtracting(projectById.keys)
        if !orphanProjectIds.isEmpty {
            lines.append("")
            lines.append("## Tasks in missing projects")
            for projectId in orphanProjectIds.sorted() {
                for task in (tasksByProject[projectId] ?? []).sorted(by: sortByIndex) {
                    lines.append(contentsOf: taskBullet(task, indent: 0))
                }
            }
        }

        if !inbox.isEmpty {
            lines.append("")
            lines.append("## Inbox")
            for task in inbox {
                lines.append(contentsOf: taskBullet(task, indent: 0))
            }
        }

        if !anytime.isEmpty {
            lines.append("")
            lines.append("## Anytime")
            for task in anytime {
                lines.append(contentsOf: taskBullet(task, indent: 0))
            }
        }

        if !someday.isEmpty {
            lines.append("")
            lines.append("## Someday")
            for task in someday {
                lines.append(contentsOf: taskBullet(task, indent: 0))
            }
        }

        let upcoming = (snapshot.projects.compactMap { project -> (String, String, String)? in
            guard let deadline = project.deadline else { return nil }
            return ("project", project.title, deadline)
        } + snapshot.tasks.compactMap { task -> (String, String, String)? in
            guard let deadline = task.deadline else { return nil }
            return ("task", task.title, deadline)
        }).sorted { $0.2 < $1.2 }

        if !upcoming.isEmpty {
            lines.append("")
            lines.append("## Upcoming deadlines")
            for item in upcoming {
                lines.append("- \(item.2) — \(item.0): \(item.1)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func taskBullet(_ task: ThingsTask, indent: Int) -> [String] {
        let pad = String(repeating: "  ", count: indent)
        var lines = ["\(pad)- \(task.title)"]
        if let deadline = task.deadline {
            lines.append("\(pad)  Deadline: \(deadline)")
        }
        if let heading = task.heading, !heading.isEmpty {
            lines.append("\(pad)  Heading: \(heading)")
        }
        let notes = clipped(task.notes)
        if !notes.isEmpty {
            lines.append("\(pad)  Notes: \(notes)")
        }
        return lines
    }

    private static func sortProjectsByIndex(_ lhs: ThingsProject, _ rhs: ThingsProject) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    private static func sortByIndex(_ lhs: ThingsTask, _ rhs: ThingsTask) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    private static func clipped(_ text: String, limit: Int = 400) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
