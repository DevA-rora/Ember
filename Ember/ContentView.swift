import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        if auth.isSignedIn {
            ChatView()
        } else {
            AuthView()
        }
    }
}
