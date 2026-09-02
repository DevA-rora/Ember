import Foundation

/// Loads bundled coaching markdown for Gemini system instructions.
enum KnowledgeModule: String, CaseIterable {
    case coachingGuidelines = "coaching-guidelines"
    case executiveDysfunction = "executive-dysfunction"
    case adhdStrategies = "adhd-strategies"
    case asdRoutines = "asd-routines"
    case psychologyBasics = "psychology-basics"
    case teenLowEnergy = "teen-low-energy"

    var resourceName: String { rawValue }
    var resourceSubdirectory: String? {
        switch self {
        case .coachingGuidelines:
            return "Context"
        default:
            return "Context/knowledge"
        }
    }

    func load(from bundle: Bundle = .main) -> String {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "md",
            subdirectory: resourceSubdirectory
        ) else {
            assertionFailure(
                "KnowledgeModule: \(resourceName).md is not bundled — check project.yml Context folder reference."
            )
            return "# \(resourceName)\n\n(Missing bundled context file.)"
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("KnowledgeModule: \(resourceName).md exists but could not be read as UTF-8.")
            return ""
        }
        return contents
    }

    static var coachingGuidelinesMarkdown: String {
        KnowledgeModule.coachingGuidelines.load()
    }

    static var allKnowledgeMarkdown: String {
        allCases
            .filter { $0 != .coachingGuidelines }
            .map { "## \($0.resourceName)\n\n\($0.load())" }
            .joined(separator: "\n\n")
    }
}
