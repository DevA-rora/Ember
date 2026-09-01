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
  ember-sync login          Sign in with the same Firebase email/password as the iOS app
  ember-sync --dry-run      Print open projects, notes, and deadlines (no network)
  ember-sync                Upsert the current Things snapshot to Firestore
"""

private func run(arguments: [String]) async throws {
    if arguments.contains("-h") || arguments.contains("--help") {
        print(usage)
        return
    }

    if arguments.first == "login" {
        try await login()
        return
    }

    let dryRun = arguments.contains("--dry-run")
    let snapshot = try ThingsDatabase.loadSnapshot()
    print("Read \(snapshot.projects.count) open projects and \(snapshot.tasks.count) open tasks from Things 3.")

    if dryRun {
        print(ThingsContextFormatter.markdown(from: snapshot))
        return
    }

    let credentials = try EmberConfig.loadCredentials()
    let session = try await FirebaseREST.signIn(credentials: credentials)
    try await FirebaseREST.upsertSnapshot(credentials: credentials, session: session, snapshot: snapshot)
    print("Upserted Things snapshot for uid \(session.localId).")
}

private func login() async throws {
    let plist = EmberConfig.loadPlist()
    let email = prompt("Email")
    let password = prompt("Password", hide: true)
    var apiKey = plist?.apiKey ?? ""
    var projectId = plist?.projectId ?? ""
    if apiKey.isEmpty {
        apiKey = prompt("Firebase API key (from GoogleService-Info.plist)")
    }
    if projectId.isEmpty {
        projectId = prompt("Firebase project id")
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
}

private func prompt(_ label: String, hide: Bool = false) -> String {
    fputs("\(label): ", stdout)
    if hide {
        guard let pointer = getpass("") else { return "" }
        return String(cString: pointer)
    }
    return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}
