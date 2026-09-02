#!/bin/zsh
set -euo pipefail

# One-shot Things 3 → Firestore sync (no WatchPaths, no test user creation).
# Prerequisite: ember-sync login with the SAME email/password as the iOS app.
#
# Usage: ./scripts/sync-things-once.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "${ROOT}/scripts/lib/ensure-signing-identity.sh"

BIN="${ROOT}/build/DerivedData/Build/Products/Debug/ember-sync"
PLIST="${ROOT}/Ember/GoogleService-Info.plist"
CREDS="${HOME}/.config/ember/credentials.json"

api_key() { /usr/libexec/PlistBuddy -c 'Print :API_KEY' "$PLIST"; }
project_id() { /usr/libexec/PlistBuddy -c 'Print :PROJECT_ID' "$PLIST"; }

echo "Ember one-time Things 3 sync"
echo "==========================="
echo ""

if [[ ! -f "$CREDS" ]]; then
  echo "No credentials at $CREDS"
  echo "Run: build/DerivedData/Build/Products/Debug/ember-sync login"
  echo "Use the same email/password as the iOS simulator app."
  exit 1
fi

echo "Building ember-sync..."
xcodebuild -project Ember.xcodeproj -scheme EmberSync -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
echo "✅ ember-sync built"

ensure_ember_sync_signing_identity
codesign --force --sign "${EMBER_SIGN_IDENTITY}" --identifier com.ember.sync "${BIN}"
echo "✅ ember-sync signed with stable identity '${EMBER_SIGN_IDENTITY}'"
echo ""

echo "Phase 1: Things 3 database read"
DRY_OUT="$(mktemp)"
if ! "$BIN" --dry-run > "$DRY_OUT" 2>&1; then
  echo "❌ Could not read Things 3 database"
  cat "$DRY_OUT"
  rm -f "$DRY_OUT"
  exit 1
fi

PROJECT_COUNT=$(grep -E '^Read [0-9]+ open projects' "$DRY_OUT" | sed -E 's/.*Read ([0-9]+) open projects.*/\1/')
TASK_COUNT=$(grep -E '^Read [0-9]+ open projects' "$DRY_OUT" | sed -E 's/.*and ([0-9]+) open tasks.*/\1/')
SAMPLE_PROJECT=$(grep -E '^### ' "$DRY_OUT" | head -1 | sed 's/^### //')

if [[ -z "$PROJECT_COUNT" || "$PROJECT_COUNT" -eq 0 ]]; then
  echo "❌ Dry-run succeeded but no open projects found"
  cat "$DRY_OUT"
  rm -f "$DRY_OUT"
  exit 1
fi
echo "✅ Read $PROJECT_COUNT projects / $TASK_COUNT tasks from Things 3"
if [[ -n "$SAMPLE_PROJECT" ]]; then
  echo "   Sample project: \"$SAMPLE_PROJECT\""
fi
echo ""

echo "Phase 2: Firestore upsert"
if ! "$BIN" 2>&1 | tee /tmp/ember-sync-once.log; then
  echo "❌ ember-sync upsert failed"
  cat /tmp/ember-sync-once.log
  rm -f "$DRY_OUT"
  exit 1
fi
echo "✅ Upserted snapshot to Firestore"
echo ""

echo "Phase 3: Firestore verification"
API_KEY="$(api_key)"
PROJECT_ID="$(project_id)"
EMAIL=$(python3 -c "import json; print(json.load(open('$CREDS'))['email'])")
PASSWORD=$(python3 -c "import json; print(json.load(open('$CREDS'))['password'])")

ID_TOKEN=$(curl -sS -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'email':'${EMAIL}','password':'${PASSWORD}','returnSecureToken':True}))")" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['idToken'])")

FIREBASE_UID=$(curl -sS -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'email':'${EMAIL}','password':'${PASSWORD}','returnSecureToken':True}))")" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['localId'])")

DOC_FILE="$(mktemp)"
curl -sS \
  "https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${FIREBASE_UID}/things/current" \
  -H "Authorization: Bearer ${ID_TOKEN}" > "$DOC_FILE"

parse_field() {
  local file="$1" field="$2"
  python3 - "$file" "$field" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
fields = doc.get("fields", {})
name = sys.argv[2]
if name in ("source", "markdown"):
    print(fields.get(name, {}).get("stringValue", ""))
elif name in ("projectCount", "taskCount"):
    print(fields.get(name, {}).get("integerValue", ""))
elif name == "syncedAt":
    print(fields.get(name, {}).get("timestampValue", ""))
PY
}

SOURCE=$(parse_field "$DOC_FILE" source)
FS_PROJECTS=$(parse_field "$DOC_FILE" projectCount)
FS_TASKS=$(parse_field "$DOC_FILE" taskCount)
SYNCED_AT=$(parse_field "$DOC_FILE" syncedAt)
MARKDOWN=$(parse_field "$DOC_FILE" markdown | head -c 500)

FAIL=0
if [[ "$SOURCE" == "things3" ]]; then
  echo "✅ Firestore source=things3"
else
  echo "❌ Expected source=things3, got '$SOURCE'"
  FAIL=1
fi

if [[ "$FS_PROJECTS" == "$PROJECT_COUNT" ]]; then
  echo "✅ projectCount=$FS_PROJECTS matches Things 3"
else
  echo "❌ projectCount mismatch: Firestore=$FS_PROJECTS Things=$PROJECT_COUNT"
  FAIL=1
fi

if [[ "$FS_TASKS" == "$TASK_COUNT" ]]; then
  echo "✅ taskCount=$FS_TASKS matches Things 3"
else
  echo "❌ taskCount mismatch: Firestore=$FS_TASKS Things=$TASK_COUNT"
  FAIL=1
fi

if [[ -n "$SAMPLE_PROJECT" ]] && echo "$MARKDOWN" | grep -q "$SAMPLE_PROJECT"; then
  echo "✅ Markdown contains sample project \"$SAMPLE_PROJECT\""
else
  echo "❌ Markdown missing sample project"
  FAIL=1
fi

SUBCOLLECTION_COUNTS=$(python3 - "$PROJECT_ID" "$FIREBASE_UID" "$ID_TOKEN" <<'PY'
import json, sys, urllib.request, urllib.parse

project_id, uid, token = sys.argv[1:4]

def count_collection(path):
    total = 0
    page_token = None
    while True:
        url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents/{path}?pageSize=300"
        if page_token:
            url += "&pageToken=" + urllib.parse.quote(page_token)
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        data = json.loads(urllib.request.urlopen(req).read().decode())
        total += len(data.get("documents", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    return total

projects = count_collection(f"users/{uid}/things/current/projects")
tasks = count_collection(f"users/{uid}/things/current/tasks")
print(f"{projects} {tasks}")
PY
)
FS_SUBCOLLECTION_PROJECTS="${SUBCOLLECTION_COUNTS%% *}"
FS_SUBCOLLECTION_TASKS="${SUBCOLLECTION_COUNTS##* }"

if [[ "$FS_SUBCOLLECTION_PROJECTS" == "$FS_PROJECTS" ]]; then
  echo "✅ projects subcollection has $FS_SUBCOLLECTION_PROJECTS docs (matches projectCount)"
else
  echo "❌ projects subcollection mismatch: docs=$FS_SUBCOLLECTION_PROJECTS projectCount=$FS_PROJECTS"
  FAIL=1
fi

if [[ "$FS_SUBCOLLECTION_TASKS" == "$FS_TASKS" ]]; then
  echo "✅ tasks subcollection has $FS_SUBCOLLECTION_TASKS docs (matches taskCount)"
else
  echo "❌ tasks subcollection mismatch: docs=$FS_SUBCOLLECTION_TASKS taskCount=$FS_TASKS"
  FAIL=1
fi

echo ""
echo "==========================="
if [[ "$FAIL" -eq 0 ]]; then
  echo "Sync complete."
  echo ""
  echo "IMPORTANT — account must match the iOS app:"
  echo "  email: $EMAIL"
  echo "  uid:   $FIREBASE_UID"
  echo ""
  echo "In the iOS app: Context → compare UID with the value above."
  echo "If they differ, run: ember-sync login (use your iOS email/password), then re-run this script."
  echo "Then in the app: Refresh projects → Context (expect Source: Things 3)."
  echo "  synced: $SYNCED_AT"
else
  echo "Verification failed."
fi

rm -f "$DRY_OUT" "$DOC_FILE"
exit "$FAIL"
