# Ember

Firebase-backed Things 3 context for a personal chat app.

See [AGENTS.md](AGENTS.md) for product vision, architecture, and implementation status.

## Setup: Firebase config (first time / new clone)

`Ember/GoogleService-Info.plist` is **not committed** (it contains a project API key) — copy the
example and fill it in, or regenerate it from Firebase:

```bash
cp Ember/GoogleService-Info.plist.example Ember/GoogleService-Info.plist
# then either edit it by hand with values from
# https://console.firebase.google.com/project/ember-284cd/settings/general
# or regenerate directly:
npx -y firebase-tools@latest apps:sdkconfig IOS --project ember-284cd > Ember/GoogleService-Info.plist
```

## Status

| Piece | State |
|-------|--------|
| iOS app (Auth + chat + AI context) | **Built** — see [buildApp.md](buildApp.md) |
| `ember-sync` CLI (Things → Firestore) | **Built** — `--dry-run` reads 14 projects / 388 tasks |
| Firestore DB + security rules | Deployed on Firebase project `ember-284cd` |
| Firebase Auth / iOS app / AI Logic | **Active** on `ember-284cd` |

## One-time Things 3 sync (load real context)

Push your Things 3 database to Firestore once, then verify in the iOS app. **Use the same Firebase email/password on Mac and iOS.**

```bash
# 1. Login (once) — same credentials as the iOS app
build/DerivedData/Build/Products/Debug/ember-sync login

# If the terminal hangs after Email, use env vars instead (common in Cursor):
EMBER_EMAIL=you@example.com EMBER_PASSWORD=yourpassword build/DerivedData/Build/Products/Debug/ember-sync login

# 2. One-shot sync + verification
./scripts/sync-things-once.sh
```

In the iOS simulator: sign in → menu → **Refresh projects** → tap **Context**. You should see `source: Things 3`, real project titles, and tasks grouped under each project.

## Mac sync (WatchPaths, optional)

For automatic sync when Things changes, use WatchPaths:

```bash
xcodebuild -project Ember.xcodeproj -scheme EmberSync -derivedDataPath build/DerivedData build

build/DerivedData/Build/Products/Debug/ember-sync login
build/DerivedData/Build/Products/Debug/ember-sync          # one-shot upsert
build/DerivedData/Build/Products/Debug/ember-sync --dry-run

./scripts/install-watchpaths.sh   # launchd WatchPaths agent
```

## iOS app

See [buildApp.md](buildApp.md).
