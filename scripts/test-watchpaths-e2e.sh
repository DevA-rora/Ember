#!/bin/zsh
set -euo pipefail

# End-to-end WatchPaths / Things 3 / Firebase / app-context test
# Usage: ./scripts/test-watchpaths-e2e.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="${ROOT}/build/DerivedData/Build/Products/Debug/ember-sync"
PLIST="${ROOT}/Ember/GoogleService-Info.plist"
THINGS_DIR="${HOME}/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-TDMSC/Things Database.thingsdatabase"
LOG="${HOME}/Library/Logs/ember-sync.log"
ERR="${HOME}/Library/Logs/ember-sync.err"
CREDS="${HOME}/.config/ember/credentials.json"
PASS=0
FAIL=0

pass() { echo "✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "❌ $1"; FAIL=$((FAIL + 1)); }

api_key() { /usr/libexec/PlistBuddy -c 'Print :API_KEY' "$PLIST"; }
project_id() { /usr/libexec/PlistBuddy -c 'Print :PROJECT_ID' "$PLIST"; }

echo "Ember WatchPaths E2E test"
echo "========================"
echo ""

# --- Build ---
echo "Building ember-sync..."
xcodebuild -project Ember.xcodeproj -scheme EmberSync -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
pass "ember-sync built"

# --- Phase 1: Things database read ---
echo ""
echo "Phase 1: Things 3 database read"
DRY_OUT="$(mktemp)"
if "$BIN" --dry-run > "$DRY_OUT" 2>&1; then
  PROJECT_COUNT=$(grep -E '^Read [0-9]+ open projects' "$DRY_OUT" | sed -E 's/.*Read ([0-9]+) open projects.*/\1/')
  TASK_COUNT=$(grep -E '^Read [0-9]+ open projects' "$DRY_OUT" | sed -E 's/.*and ([0-9]+) open tasks.*/\1/')
  SAMPLE_PROJECT=$(grep -E '^### ' "$DRY_OUT" | head -1 | sed 's/^### //')
  if [[ -n "$PROJECT_COUNT" && "$PROJECT_COUNT" -gt 0 && -n "$SAMPLE_PROJECT" ]]; then
    pass "Read $PROJECT_COUNT projects / $TASK_COUNT tasks from Things 3 (sample: \"$SAMPLE_PROJECT\")"
  else
    fail "Dry-run succeeded but no open projects found"
  fi
else
  fail "Could not read Things 3 database"
  cat "$DRY_OUT"
  exit 1
fi

# --- Phase 2: Credentials + Firebase upsert ---
echo ""
echo "Phase 2: Firebase upsert"
API_KEY="$(api_key)"
PROJECT_ID="$(project_id)"
TEST_EMAIL="ember-e2e-$(date +%s)@example.com"
TEST_PASS="EmberE2ETest$(date +%s)"

mkdir -p "$(dirname "$CREDS")"
SIGNUP=$(curl -sS -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'email':'${TEST_EMAIL}','password':'${TEST_PASS}','returnSecureToken':True}))")")

FIREBASE_UID=$(echo "$SIGNUP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('localId',''))" 2>/dev/null || true)
if [[ -z "$FIREBASE_UID" ]]; then
  fail "Could not create test Firebase user: $SIGNUP"
  exit 1
fi
pass "Created test user $TEST_EMAIL (uid $FIREBASE_UID)"

python3 - <<PY
import json, pathlib
path = pathlib.Path("$CREDS")
path.write_text(json.dumps({
    "email": "$TEST_EMAIL",
    "password": "$TEST_PASS",
    "apiKey": "$API_KEY",
    "projectId": "$PROJECT_ID",
}))
path.chmod(0o600)
PY

if "$BIN" 2>&1 | tee /tmp/ember-sync-upsert.log; then
  pass "ember-sync upserted snapshot to Firestore"
else
  fail "ember-sync upsert failed"
  cat /tmp/ember-sync-upsert.log
  exit 1
fi

# --- Phase 3: Verify Firestore (what the iOS app reads) ---
echo ""
echo "Phase 3: Firestore verification (app data layer)"
ID_TOKEN=$(curl -sS -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'email':'${TEST_EMAIL}','password':'${TEST_PASS}','returnSecureToken':True}))")" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['idToken'])")

fetch_firestore_doc() {
  local token="$1" uid="$2" outfile="$3"
  curl -sS \
    "https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}/things/current" \
    -H "Authorization: Bearer ${token}" > "$outfile"
}

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

DOC_FILE="$(mktemp)"
fetch_firestore_doc "$ID_TOKEN" "$FIREBASE_UID" "$DOC_FILE"

SOURCE=$(parse_field "$DOC_FILE" source)
FS_PROJECTS=$(parse_field "$DOC_FILE" projectCount)
MARKDOWN=$(parse_field "$DOC_FILE" markdown | head -c 500)

if [[ "$SOURCE" == "things3" ]]; then
  pass "Firestore current doc source=things3"
else
  fail "Expected source=things3, got '$SOURCE'"
fi

if [[ "$FS_PROJECTS" == "$PROJECT_COUNT" ]]; then
  pass "Firestore projectCount ($FS_PROJECTS) matches Things 3 ($PROJECT_COUNT)"
else
  fail "projectCount mismatch: Firestore=$FS_PROJECTS Things=$PROJECT_COUNT"
fi

if echo "$MARKDOWN" | grep -q "$SAMPLE_PROJECT"; then
  pass "Firestore markdown contains sample project \"$SAMPLE_PROJECT\" (app would show this)"
else
  fail "Firestore markdown missing sample project \"$SAMPLE_PROJECT\""
fi

# --- Phase 4: WatchPaths launchd trigger ---
echo ""
echo "Phase 4: WatchPaths launchd"
: > "$LOG"
: > "$ERR"

"${ROOT}/scripts/install-watchpaths.sh" 2>&1 | tail -5
pass "WatchPaths LaunchAgent installed"

BEFORE_SYNCED=$(parse_field "$DOC_FILE" syncedAt)

echo "Touching Things database to trigger WatchPaths..."
touch "${THINGS_DIR}/main.sqlite" "${THINGS_DIR}/main.sqlite-wal" 2>/dev/null || touch "${THINGS_DIR}/main.sqlite"

echo "Waiting 20s for ThrottleInterval (15s)..."
sleep 20

if grep -q "Upserted Things snapshot" "$LOG" 2>/dev/null; then
  pass "WatchPaths triggered ember-sync (see $LOG)"
else
  echo "--- ember-sync.log ---"
  tail -20 "$LOG" 2>/dev/null || true
  echo "--- ember-sync.err ---"
  tail -20 "$ERR" 2>/dev/null || true
  fail "WatchPaths did not produce a successful sync in $LOG"
fi

DOC2_FILE="$(mktemp)"
fetch_firestore_doc "$ID_TOKEN" "$FIREBASE_UID" "$DOC2_FILE"
AFTER_SYNCED=$(parse_field "$DOC2_FILE" syncedAt)

if [[ -n "$AFTER_SYNCED" && "$AFTER_SYNCED" != "$BEFORE_SYNCED" ]]; then
  pass "syncedAt updated after WatchPaths trigger ($BEFORE_SYNCED → $AFTER_SYNCED)"
else
  fail "syncedAt did not update after WatchPaths (before=$BEFORE_SYNCED after=$AFTER_SYNCED)"
fi

# --- Summary ---
echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
echo ""
echo "To see this in the iOS app, sign in with:"
echo "  Email:    $TEST_EMAIL"
echo "  Password: $TEST_PASS"
echo ""
echo "Open Context in the app — you should see $PROJECT_COUNT projects from Things 3,"
echo "not the seeded \"Ember\" fixture."
echo ""

rm -f "$DRY_OUT" "$DOC_FILE" "$DOC2_FILE"
[[ "$FAIL" -eq 0 ]]
