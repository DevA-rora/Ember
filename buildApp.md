# Build and run Ember on the iOS Simulator

```bash
# 1. Boot simulator (use device ID — name= often fails to resolve)
SIM_ID=$(xcrun simctl list devices available | awk -F'[()]' '/iPhone 13 \(/ {print $2; exit}')
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
open -a Simulator

# 2. Remove the old hello-world build if it is still installed
xcrun simctl uninstall booted com.ember.app 2>/dev/null || true

# 3. Build for that simulator
xcodebuild -project Ember.xcodeproj -scheme Ember \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath build \
  build

# 4. Verify the build before installing (~32 MB with Firebase, not ~40 KB)
test -d build/Build/Products/Debug-iphonesimulator/Ember.app/Firebase_FirebaseAuth.bundle

# 4. Install and launch
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Ember.app
xcrun simctl launch booted com.ember.app
```

You should see the **Ember sign-in screen**, not "hello world".

Quick sanity check that the right build was installed:

```bash
APP=$(xcrun simctl get_app_container booted com.ember.app)
ls "$APP/GoogleService-Info.plist"   # should exist
ls "$APP/Firebase_FirebaseAuth.bundle"  # should exist
du -sh "$APP"                        # should be ~30 MB, not ~40 KB
```

**Why you might see "Hello World":** an old stub build (~40 KB, no Firebase) was still installed. The `name=iPhone 13` destination often fails silently, so `xcodebuild` never produces a new `.app` and `simctl install` reuses the stale one. Uninstall first, build with `id=`, and verify step 4 passes before installing.

## Load Things 3 context

After signing in, load real project data from your Mac:

```bash
# On Mac — same Firebase email/password as the iOS app
./scripts/sync-things-once.sh
```

In the app: menu (person icon) → **Refresh projects** → **Context**. Expect `Source: Things 3`, project titles from Things, and tasks nested under each project.