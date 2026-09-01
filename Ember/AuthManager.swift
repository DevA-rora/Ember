import Foundation
import Observation
import FirebaseAuth

@MainActor
@Observable
final class AuthManager {
    private var auth: Auth { Auth.auth() }

    var user: User?
    var isBusy = false
    var errorMessage: String?

    var isSignedIn: Bool { user != nil }
    var uid: String? { user?.uid }
    var email: String? { user?.email }

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        user = auth.currentUser
        handle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            _ = try await self.auth.signIn(withEmail: email, password: password)
        }
    }

    func signUp(email: String, password: String) async {
        await run {
            _ = try await self.auth.createUser(withEmail: email, password: password)
        }
    }

    func signOut() {
        errorMessage = nil
        do {
            try auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
