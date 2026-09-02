#!/bin/zsh
# Shared helper: ensure a stable, self-signed code-signing identity exists in the
# login keychain for signing ember-sync. Sourced by install-watchpaths.sh and
# sync-things-once.sh — do not execute directly.
#
# Why: macOS TCC (kTCCServiceSystemPolicyAppData, the "would like to access data
# from other apps" prompt) keys its trust decision to a binary's code-signing
# Designated Requirement. ember-sync was ad-hoc/linker-signed (no stable
# identity), so every rebuild looked like a brand-new app and re-triggered the
# prompt. Signing with the same local certificate on every build keeps the
# Designated Requirement constant across rebuilds.
#
# Exports: EMBER_SIGN_IDENTITY — the keychain identity name to pass to `codesign --sign`.

EMBER_SIGN_IDENTITY="EmberSyncSigning"

ensure_ember_sync_signing_identity() {
  local keychain="${HOME}/Library/Keychains/login.keychain-db"

  if security find-identity -v -p codesigning "$keychain" 2>/dev/null | grep -q "$EMBER_SIGN_IDENTITY"; then
    return 0
  fi

  echo "Creating local code-signing certificate '${EMBER_SIGN_IDENTITY}' (one-time)..."

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local key="${tmp_dir}/ember-sync.key"
  local crt="${tmp_dir}/ember-sync.crt"
  local p12="${tmp_dir}/ember-sync.p12"
  local p12_pass
  p12_pass="$(openssl rand -base64 24)"

  openssl req -x509 -newkey rsa:2048 -keyout "$key" -out "$crt" \
    -days 3650 -nodes -subj "/CN=${EMBER_SIGN_IDENTITY}" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "basicConstraints=critical,CA:FALSE" 2>/dev/null

  openssl pkcs12 -export -out "$p12" -inkey "$key" -in "$crt" -passout "pass:${p12_pass}" -legacy 2>/dev/null \
    || openssl pkcs12 -export -out "$p12" -inkey "$key" -in "$crt" -passout "pass:${p12_pass}"

  security import "$p12" -k "$keychain" -P "$p12_pass" -T /usr/bin/codesign -T /usr/bin/security
  security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$crt"

  rm -rf "$tmp_dir"

  echo "Created and trusted '${EMBER_SIGN_IDENTITY}' in ${keychain}"
  echo "Note: the first 'codesign' call below may show a Keychain access prompt —"
  echo "click 'Always Allow' so future builds sign silently."
}
