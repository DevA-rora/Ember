#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Ember Firebase setup"
echo "===================="
echo ""
echo "If 'firebase projects:list' shows no projects, finish this once in the browser:"
echo "  1. https://console.firebase.google.com → Create a project (or Add Firebase to ember-devarora)"
echo "  2. Project settings → Add iOS app → bundle id com.ember.app"
echo "  3. Download GoogleService-Info.plist into Ember/"
echo "  4. Authentication → Sign-in method → Email/Password → Enable"
echo "  5. Build → AI Logic / Gemini → enable for the iOS app"
echo ""

npx -y firebase-tools@latest login:list
npx -y firebase-tools@latest use ember-devarora 2>/dev/null || true
npx -y firebase-tools@latest projects:list

echo ""
echo "Deploying Firestore rules + Auth providers from firebase.json..."
npx -y firebase-tools@latest deploy --only auth,firestore:rules

echo ""
echo "Fetching iOS SDK config (if iOS app is registered)..."
if npx -y firebase-tools@latest apps:sdkconfig IOS --project ember-devarora > Ember/GoogleService-Info.plist 2>/dev/null; then
  echo "Wrote Ember/GoogleService-Info.plist"
else
  echo "Could not fetch plist yet — register the iOS app in Firebase Console first."
fi

echo ""
echo "Done. Next:"
echo "  ./build/DerivedData/Build/Products/Debug/ember-sync login"
echo "  ./build/DerivedData/Build/Products/Debug/ember-sync"
echo "  ./scripts/install-watchpaths.sh"
