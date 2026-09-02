import Foundation

/// Assembles the full Gemini system instruction from all context layers, in the
/// fixed order documented in AGENTS.md: coaching guidelines, knowledge modules,
/// session memory, calendar, then current Things 3 work. `ChatViewModel` should
/// fingerprint the *entire* string this returns, not just the Things markdown,
/// so a knowledge or memory change correctly invalidates the chat session.
enum EmberContextAssembler {
    static func systemInstruction(
        displayName: String?,
        thingsMarkdown: String,
        suggestion: TaskSuggestion?,
        sessionMemory: String = SessionMemoryFixture.seed,
        calendarMarkdown: String = CalendarFixture.seed,
        now: Date = Date()
    ) -> String {
        var sections: [String] = [intro(displayName: displayName, now: now)]
        sections.append("# How to coach\n\n\(KnowledgeModule.coachingGuidelinesMarkdown)")
        sections.append("# Background knowledge\n\n\(KnowledgeModule.allKnowledgeMarkdown)")
        sections.append("# This user's history\n\n\(sessionMemory)")
        sections.append("# Today's schedule\n\n\(calendarMarkdown)")
        sections.append("# Current work\n\n\(thingsMarkdown)")
        if let suggestion {
            sections.append("# Suggested next task\n\n\(suggestionMarkdown(suggestion))")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func intro(displayName: String?, now: Date) -> String {
        let who = displayName.map { "for \($0)" } ?? "for the user"
        return """
        You are Ember, a proactive personal work coach \(who). You help teens navigating \
        executive dysfunction, ADHD, ASD, and low mood move from procrastination into focused \
        work. You are not a generic task list or open-ended chatbot — coach using the guidance \
        and context below, and never invent tasks that aren't in the user's actual data.

        Today is \(formatted(now)).
        """
    }

    private static func suggestionMarkdown(_ suggestion: TaskSuggestion) -> String {
        var lines = ["- \(suggestion.task.title)"]
        if let project = suggestion.task.projectTitle {
            lines.append("  Project: \(project)")
        }
        lines.append("  Why now: \(suggestion.reason)")
        lines.append("  Eisenhower tier: \(suggestion.tier)")
        lines.append("")
        lines.append("Use this as the task to greet the user with, unless the conversation moves elsewhere.")
        return lines.joined(separator: "\n")
    }

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
}
