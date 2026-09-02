import Darwin
import Foundation

do {
    try await run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("ember-sync: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private let usage = """
ember-sync — copy open Things 3 projects/tasks into Firestore

Usage:
  ember-sync login [--email ADDRESS]   Sign in (same Firebase account as the iOS app)
  ember-sync --dry-run                 Print open projects, notes, and deadlines (no network)
  ember-sync --suggest                 Print the top ranked task suggestions (no network)
  ember-sync                           Upsert the current Things snapshot to Firestore (skips if unchanged)
  ember-sync --force                   Upsert even if the content hash matches the last sync

Login also accepts environment variables (useful in Cursor/VS Code terminals):
  EMBER_EMAIL=you@example.com EMBER_PASSWORD=secret ember-sync login
"""

private func run(arguments: [String]) async throws {
    if arguments.contains("-h") || arguments.contains("--help") {
        print(usage)
        return
    }

    if arguments.first == "login" {
        try await login(arguments: Array(arguments.dropFirst()))
        return
    }

    print("ember-sync build: \(buildStamp())")

    let dryRun = arguments.contains("--dry-run")
    let suggest = arguments.contains("--suggest")
    let force = arguments.contains("--force")
    let snapshot = try ThingsDatabase.loadSnapshot()
    print("Read \(snapshot.projects.count) open projects and \(snapshot.tasks.count) open tasks from Things 3.")

    if dryRun {
        print(ThingsContextFormatter.markdown(from: snapshot))
        return
    }

    if suggest {
        printSuggestions(from: snapshot)
        return
    }

    let credentials = try EmberConfig.loadCredentials()
    let session = try await FirebaseREST.signIn(credentials: credentials)
    let wrote = try await FirebaseREST.upsertSnapshot(
        credentials: credentials,
        session: session,
        snapshot: snapshot,
        force: force
    )
    if wrote {
        print("Upserted Things snapshot for uid \(session.localId).")
    } else {
        print("No changes since last sync for uid \(session.localId) — skipped write.")
    }
}

private func printSuggestions(from snapshot: ThingsSnapshot) {
    let candidates = TaskSuggester.rankedCandidates(from: snapshot, limit: 5)
    guard !candidates.isEmpty else {
        print("No open (non-Someday) tasks to suggest.")
        return
    }
    print("Top task suggestions:")
    for (index, candidate) in candidates.enumerated() {
        let project = candidate.task.projectTitle.map { " (\($0))" } ?? ""
        print("\(index + 1). [\(candidate.tier)] \(candidate.task.title)\(project) — \(candidate.reason)")
    }
}

/// Identifies which build produced this binary, so a stale `~/.local/bin/ember-sync`
/// copy (installed by install-watchpaths.sh) can be spotted in logs.
private func buildStamp() -> String {
    guard let path = Bundle.main.executablePath ?? CommandLine.arguments.first,
          let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let modified = attrs[.modificationDate] as? Date
    else {
        return "unknown"
    }
    return ISO8601DateFormatter().string(from: modified)
}

private func login(arguments: [String]) async throws {
    let plist = EmberConfig.loadPlist()
    let email = flagValue("email", in: arguments)
        ?? ProcessInfo.processInfo.environment["EMBER_EMAIL"]
        ?? prompt("Email")
    let password = ProcessInfo.processInfo.environment["EMBER_PASSWORD"]
        ?? promptPassword()
    var apiKey = plist?.apiKey ?? ""
    var projectId = plist?.projectId ?? ""
    if apiKey.isEmpty {
        apiKey = prompt("Firebase API key (from GoogleService-Info.plist)")
    }
    if projectId.isEmpty {
        projectId = prompt("Firebase project id")
    }

    guard !email.isEmpty, !password.isEmpty else {
        throw LoginError.missingCredentials
    }

    let credentials = EmberCredentials(
        email: email,
        password: password,
        apiKey: apiKey,
        projectId: projectId
    )
    let session = try await FirebaseREST.signIn(credentials: credentials)
    try EmberConfig.saveCredentials(credentials)
    print("Signed in as \(session.email) (uid \(session.localId)).")
    print("Saved credentials to \(EmberConfig.credentialsURL.path)")
    print("")
    print("Next: upload Things 3 data with")
    print("  ./scripts/sync-things-once.sh")
    print("Sign into the iOS app with the same email, then Refresh projects.")
}

private enum LoginError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        "Email and password are required. Use --email, EMBER_EMAIL/EMBER_PASSWORD, or interactive prompts."
    }
}

private func flagValue(_ name: String, in arguments: [String]) -> String? {
    let flag = "--\(name)"
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }
    let value = arguments[index + 1]
    return value.hasPrefix("--") ? nil : value
}

private func prompt(_ label: String) -> String {
    fputs("\(label): ", stdout)
    fflush(stdout)
    return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// `getpass` often hangs or shows nothing in IDE integrated terminals — fall back to visible `readLine`.
private func promptPassword() -> String {
    fputs("Password (characters hidden; if stuck, use EMBER_PASSWORD=... ember-sync login): ", stdout)
    fflush(stdout)
    if isatty(STDIN_FILENO) != 0, let pointer = getpass("") {
        let value = String(cString: pointer)
        if !value.isEmpty { return value }
    }
    fputs("(typing will be visible) ", stdout)
    fflush(stdout)
    return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}
