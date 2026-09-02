import Foundation

struct EmberCredentials: Codable, Equatable {
    var email: String
    var password: String
    var apiKey: String
    var projectId: String
}

enum EmberConfig {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ember")
    }

    static var credentialsURL: URL {
        directory.appendingPathComponent("credentials.json")
    }

    static func loadCredentials() throws -> EmberCredentials {
        let data = try Data(contentsOf: credentialsURL)
        return try JSONDecoder().decode(EmberCredentials.self, from: data)
    }

    static func saveCredentials(_ credentials: EmberCredentials) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = credentials
        if values.apiKey.isEmpty || values.projectId.isEmpty, let plist = loadPlist() {
            if values.apiKey.isEmpty { values.apiKey = plist.apiKey }
            if values.projectId.isEmpty { values.projectId = plist.projectId }
        }
        let data = try JSONEncoder().encode(values)
        try data.write(to: credentialsURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path)
    }

    struct FirebasePlist {
        var apiKey: String
        var projectId: String
        var bundleId: String
    }

    static func loadPlist(from url: URL? = nil) -> FirebasePlist? {
        let candidates: [URL] = {
            if let url { return [url] }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            return [
                cwd.appendingPathComponent("Ember/GoogleService-Info.plist"),
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Ember/GoogleService-Info.plist")
            ]
        }()
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let dict = NSDictionary(contentsOf: candidate) else { continue }
            let apiKey = dict["API_KEY"] as? String ?? ""
            let projectId = dict["PROJECT_ID"] as? String ?? ""
            let bundleId = dict["BUNDLE_ID"] as? String ?? ""
            if !apiKey.isEmpty && !projectId.isEmpty {
                return FirebasePlist(apiKey: apiKey, projectId: projectId, bundleId: bundleId)
            }
        }
        return nil
    }
}

struct FirebaseAuthSession {
    var idToken: String
    var localId: String
    var email: String
}

enum FirebaseRESTError: LocalizedError {
    case http(Int, String)
    case decoding(String)
    case missingConfig(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "Firebase HTTP \(code): \(body)"
        case .decoding(let message): return "Firebase decode error: \(message)"
        case .missingConfig(let message): return message
        }
    }
}

enum FirebaseREST {
    static func signIn(credentials: EmberCredentials) async throws -> FirebaseAuthSession {
        guard !credentials.apiKey.isEmpty else {
            throw FirebaseRESTError.missingConfig("Missing API key. Run ember-sync login after GoogleService-Info.plist is present.")
        }
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(credentials.apiKey)")!
        let payload: [String: Any] = [
            "email": credentials.email,
            "password": credentials.password,
            "returnSecureToken": true
        ]
        let json = try await postJSON(url: url, json: payload, bearer: nil)
        guard let idToken = json["idToken"] as? String,
              let localId = json["localId"] as? String else {
            throw FirebaseRESTError.decoding("sign-in response missing idToken/localId")
        }
        return FirebaseAuthSession(
            idToken: idToken,
            localId: localId,
            email: json["email"] as? String ?? credentials.email
        )
    }

    static func upsertSnapshot(
        credentials: EmberCredentials,
        session: FirebaseAuthSession,
        snapshot: ThingsSnapshot
    ) async throws {
        let markdown = ThingsContextFormatter.markdown(from: snapshot)
        let now = ISO8601DateFormatter().string(from: snapshot.generatedAt)
        var writes: [[String: Any]] = []

        writes.append(
            patchWrite(
                name: documentName(projectId: credentials.projectId, path: FirestorePaths.current(uid: session.localId)),
                fields: [
                    "markdown": string(markdown),
                    "generatedAt": timestamp(now),
                    "syncedAt": timestamp(now),
                    "projectCount": integer(snapshot.projects.count),
                    "taskCount": integer(snapshot.tasks.count),
                    "source": string("things3")
                ]
            )
        )
        for project in snapshot.projects {
            writes.append(
                patchWrite(
                    name: documentName(
                        projectId: credentials.projectId,
                        path: FirestorePaths.project(uid: session.localId, uuid: project.uuid)
                    ),
                    fields: projectFields(project)
                )
            )
        }
        for task in snapshot.tasks {
            writes.append(
                patchWrite(
                    name: documentName(
                        projectId: credentials.projectId,
                        path: FirestorePaths.task(uid: session.localId, uuid: task.uuid)
                    ),
                    fields: taskFields(task)
                )
            )
        }

        for chunk in writes.chunked(into: 450) {
            try await commit(projectId: credentials.projectId, token: session.idToken, writes: chunk)
        }
    }

    private static func commit(projectId: String, token: String, writes: [[String: Any]]) async throws {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents:commit")!
        _ = try await postJSON(url: url, json: ["writes": writes], bearer: token)
    }

    private static func documentName(projectId: String, path: String) -> String {
        "projects/\(projectId)/databases/(default)/documents/\(path)"
    }

    private static func patchWrite(name: String, fields: [String: Any]) -> [String: Any] {
        [
            "update": [
                "name": name,
                "fields": fields
            ]
        ]
    }

    private static func projectFields(_ project: ThingsProject) -> [String: Any] {
        var fields: [String: Any] = [
            "uuid": string(project.uuid),
            "title": string(project.title),
            "notes": string(project.notes),
            "status": string(project.status),
            "sortIndex": integer(project.sortIndex)
        ]
        fields["area"] = optionalString(project.area)
        fields["deadline"] = optionalString(project.deadline)
        if let modifiedAt = project.modifiedAt {
            fields["modifiedAt"] = double(modifiedAt)
        }
        return fields
    }

    private static func taskFields(_ task: ThingsTask) -> [String: Any] {
        [
            "uuid": string(task.uuid),
            "title": string(task.title),
            "notes": string(task.notes),
            "status": string(task.status),
            "projectId": optionalString(task.projectId),
            "projectTitle": optionalString(task.projectTitle),
            "heading": optionalString(task.heading),
            "deadline": optionalString(task.deadline),
            "startDate": optionalString(task.startDate),
            "sortIndex": integer(task.sortIndex),
            "start": integer(task.start)
        ]
    }

    private static func string(_ value: String) -> [String: Any] { ["stringValue": value] }
    private static func optionalString(_ value: String?) -> [String: Any] {
        if let value { return ["stringValue": value] }
        return ["nullValue": NSNull()]
    }
    private static func integer(_ value: Int) -> [String: Any] { ["integerValue": "\(value)"] }
    private static func double(_ value: Double) -> [String: Any] { ["doubleValue": value] }
    private static func timestamp(_ iso: String) -> [String: Any] { ["timestampValue": iso] }

    private static func postJSON(url: URL, json: [String: Any], bearer: String?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(status) else {
            throw FirebaseRESTError.http(status, body)
        }
        if data.isEmpty { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
