import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

@MainActor
@Observable
final class ThingsContextStore {
    private var db: Firestore { Firestore.firestore() }

    var markdown: String = ""
    var projects: [ThingsProject] = []
    var tasks: [ThingsTask] = []
    var meta: ThingsMeta?
    var isLoading = false
    var errorMessage: String?
    var usedSeedData = false

    func refresh(uid: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await seedIfNeeded(uid: uid)
            async let currentDoc = db.document(FirestorePaths.current(uid: uid)).getDocument(source: .server)
            async let projectDocs = fetchAllDocuments(
                from: db.collection(FirestorePaths.projectsCollection(uid: uid))
            )
            async let taskDocs = fetchAllDocuments(
                from: db.collection(FirestorePaths.tasksCollection(uid: uid))
            )

            let (currentSnap, projectSnapshots, taskSnapshots) = try await (currentDoc, projectDocs, taskDocs)

            if let loaded = try? currentSnap.data(as: ThingsContextDocument.self) {
                markdown = loaded.markdown
                meta = ThingsMeta(
                    syncedAt: loaded.syncedAt,
                    projectCount: loaded.projectCount,
                    taskCount: loaded.taskCount,
                    source: loaded.source
                )
            } else {
                markdown = ""
                meta = nil
            }

            projects = projectSnapshots
                .compactMap { try? $0.data(as: ThingsProject.self) }
                .sorted { $0.sortIndex < $1.sortIndex }
            tasks = taskSnapshots
                .compactMap { try? $0.data(as: ThingsTask.self) }
                .sorted { $0.sortIndex < $1.sortIndex }

            if let loaded = try? currentSnap.data(as: ThingsContextDocument.self) {
                usedSeedData = loaded.source == "seed"
            } else {
                usedSeedData = false
            }

            if markdown.isEmpty {
                markdown = ThingsContextFormatter.markdown(
                    from: ThingsSnapshot(projects: projects, tasks: tasks, generatedAt: Date())
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func seedIfNeeded(uid: String) async throws {
        let currentRef = db.document(FirestorePaths.current(uid: uid))
        let existing = try await currentRef.getDocument()
        if existing.exists {
            usedSeedData = (existing.data()?["source"] as? String) == "seed"
            return
        }

        let snapshot = SeedFixture.snapshot
        let markdown = ThingsContextFormatter.markdown(from: snapshot)
        let now = Date()
        let record = ThingsContextDocument(
            markdown: markdown,
            generatedAt: now,
            syncedAt: now,
            projectCount: snapshot.projects.count,
            taskCount: snapshot.tasks.count,
            source: "seed"
        )
        try currentRef.setData(from: record)
        if let project = snapshot.projects.first {
            try db.document(FirestorePaths.project(uid: uid, uuid: project.uuid)).setData(from: project)
        }
        if let task = snapshot.tasks.first {
            try db.document(FirestorePaths.task(uid: uid, uuid: task.uuid)).setData(from: task)
        }
        usedSeedData = true
    }

    private func fetchAllDocuments(from collection: CollectionReference) async throws -> [QueryDocumentSnapshot] {
        let pageSize = 500
        var documents: [QueryDocumentSnapshot] = []
        var last: QueryDocumentSnapshot?
        while true {
            var query: Query = collection.order(by: FieldPath.documentID()).limit(to: pageSize)
            if let last { query = query.start(afterDocument: last) }
            let snapshot = try await query.getDocuments(source: .server)
            documents.append(contentsOf: snapshot.documents)
            if snapshot.documents.count < pageSize { break }
            last = snapshot.documents.last
        }
        return documents
    }
}

private extension DocumentReference {
    func setData<T: Encodable>(from value: T) throws {
        try setData(from: value, encoder: Firestore.Encoder())
    }
}
