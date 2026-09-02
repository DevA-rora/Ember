#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/lib/ensure-signing-identity.sh"
HOME_DIR="${HOME}"
BIN_DIR="${HOME_DIR}/.local/bin"
BIN="${BIN_DIR}/ember-sync"
PLIST_SRC="${ROOT}/launchd/com.ember.things-sync.plist"
PLIST_DST="${HOME_DIR}/Library/LaunchAgents/com.ember.things-sync.plist"
THINGS_DIR="${HOME_DIR}/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-TDMSC/Things Database.thingsdatabase"

mkdir -p "${BIN_DIR}"
mkdir -p "${HOME_DIR}/Library/LaunchAgents"
mkdir -p "${HOME_DIR}/Library/Logs"

echo "Building ember-sync..."
xcodebuild -project "${ROOT}/Ember.xcodeproj" -scheme EmberSync -configuration Release -derivedDataPath "${ROOT}/build/DerivedData" build

PRODUCT="$(find "${ROOT}/build/DerivedData" -name ember-sync -type f | head -n 1)"
if [[ -z "${PRODUCT}" ]]; then
  echo "ember-sync binary not found after build" >&2
  exit 1
fi
cp "${PRODUCT}" "${BIN}"
chmod +x "${BIN}"

ensure_ember_sync_signing_identity
echo "Signing ember-sync with '${EMBER_SIGN_IDENTITY}' (stable identity — avoids repeated"
echo "'access data from other apps' prompts across rebuilds)..."
codesign --force --sign "${EMBER_SIGN_IDENTITY}" --identifier com.ember.sync "${BIN}"
codesign -dvvv "${BIN}" 2>&1 | grep -E "Identifier|Authority" || true

sed \
  -e "s|__EMBER_SYNC_BIN__|${BIN}|g" \
  -e "s|__EMBER_REPO__|${ROOT}|g" \
  -e "s|__THINGS_DATABASE_DIR__|${THINGS_DIR}|g" \
  -e "s|__HOME__|${HOME_DIR}|g" \
  "${PLIST_SRC}" > "${PLIST_DST}"

launchctl bootout "gui/$(id -u)/com.ember.things-sync" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_DST}"
launchctl enable "gui/$(id -u)/com.ember.things-sync"
launchctl kickstart -k "gui/$(id -u)/com.ember.things-sync"

echo "Installed WatchPaths agent."
echo "Binary: ${BIN}"
echo "Plist:  ${PLIST_DST}"
echo "Log:    ${HOME_DIR}/Library/Logs/ember-sync.log"
echo "Sign in first with: ${BIN} login"
echo ""
echo "If macOS still prompts \"ember-sync would like to access data from other apps\","
echo "grant it once and for all via:"
echo "  System Settings → Privacy & Security → Full Disk Access → \"+\" → add ${BIN}"
echo "(Full Disk Access is a persistent grant; the AppData popup's 'Allow' is not"
echo "reliably persisted for background/launchd-triggered runs.)"
