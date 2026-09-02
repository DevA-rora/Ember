import Foundation

/// Firestore document at `users/{uid}/profile/current`. Small and additive by
/// design — later fields (text size, theme, for the status bar) get added here.
struct UserProfile: Codable, Equatable, Sendable {
    var displayName: String
}
