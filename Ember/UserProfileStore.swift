import Foundation
import Observation
import FirebaseFirestore

@MainActor
@Observable
final class UserProfileStore {
    private var db: Firestore { Firestore.firestore() }

    var displayName: String?
    var isLoading = false
    var errorMessage: String?

    /// True once we've checked Firestore and found no name yet — used to
    /// gate the first-run name prompt without flashing it during the initial load.
    var hasCheckedProfile = false

    func load(uid: String) async {
        isLoading = true
        defer {
            isLoading = false
            hasCheckedProfile = true
        }
        do {
            let snapshot = try await db.document(FirestorePaths.profile(uid: uid)).getDocument(source: .server)
            displayName = (try? snapshot.data(as: UserProfile.self))?.displayName
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(displayName: String, uid: String) async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try db.document(FirestorePaths.profile(uid: uid))
                .setData(from: UserProfile(displayName: trimmed), encoder: Firestore.Encoder())
            self.displayName = trimmed
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
