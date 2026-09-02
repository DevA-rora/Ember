import CryptoKit
import Foundation

/// Stable content hashing used to skip no-op Firestore writes when the
/// Things 3 snapshot hasn't actually changed since the last sync.
enum ContentHash {
    static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
