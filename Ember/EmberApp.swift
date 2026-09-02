import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {}

@main
struct EmberApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var authManager: AuthManager

    init() {
        // Must run before AuthManager — AppDelegate.didFinishLaunching is too late.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        if let app = FirebaseApp.app() {
            print("Firebase configured: project=\(app.options.projectID ?? "unknown")")
        }
        _authManager = State(initialValue: AuthManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
        }
    }
}
