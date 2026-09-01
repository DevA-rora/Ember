# Ember

Firebase-backed Things 3 context for a personal chat app.

## Status

| Piece | State |
|-------|--------|
| iOS app (Auth + chat + AI context) | Code complete — build after freeing disk space |
| `ember-sync` CLI (Things → Firestore) | **Built** — `--dry-run` reads 14 projects / 388 tasks |
| Firestore DB + security rules | Deployed on GCP project `ember-devarora` |
| Firebase Auth / iOS app / AI Logic | **Blocked** — GCP project is not yet a Firebase project |

## One-time Firebase setup (required)

CLI login works (`npx -y firebase-tools@latest login`), but `firebase projects:list` is empty because **`ember-devarora` was created as GCP-only**. Finish in the browser:

1. [Firebase Console](https://console.firebase.google.com) → **Create a project** (or **Add Firebase** to existing `ember-devarora`)
2. Add **iOS app** with bundle id `com.ember.app`
3. Download **`GoogleService-Info.plist`** → replace `Ember/GoogleService-Info.plist`
4. **Authentication** → Email/Password → Enable
5. **AI Logic** → enable Gemini for the iOS app

Then from the repo:

```bash
./scripts/setup-firebase.sh
```

## Mac sync (WatchPaths)

```bash
# Build CLI (or use existing build output)
xcodebuild -project Ember.xcodeproj -scheme EmberSync -derivedDataPath build/DerivedData build

build/DerivedData/Build/Products/Debug/ember-sync login
build/DerivedData/Build/Products/Debug/ember-sync          # one-shot upsert
build/DerivedData/Build/Products/Debug/ember-sync --dry-run

./scripts/install-watchpaths.sh   # launchd WatchPaths agent
```

## iOS app

See [buildApp.md](buildApp.md).
