import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        if let app = FirebaseApp.app() {
            print("Firebase configured: project=\(app.options.projectID ?? "unknown")")
        } else {
            print("Firebase configure failed: no default app")
        }

        return true
    }
}

@main
struct EmberApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var authManager: AuthManager

    init() {
        // AppDelegate.didFinishLaunching runs before this init, so Firebase is ready.
        _authManager = State(initialValue: AuthManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
        }
    }
}
