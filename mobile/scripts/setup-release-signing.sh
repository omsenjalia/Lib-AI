#!/usr/bin/env bash
# One-time setup of a release signing key for the nightly and CI builds.
#
#   bash mobile/scripts/setup-release-signing.sh            # create key + set GitHub secrets
#   bash mobile/scripts/setup-release-signing.sh --dry-run  # create key only, set nothing
#
# Needs only openssl (bundled with Git for Windows) and an authenticated `gh`.
# No JDK: the keystore is PKCS12, which Gradle and apksigner read directly.
#
# The key and its password are written OUTSIDE the repository, to
# ~/.library-ai-signing/. Back that folder up: Android only accepts updates
# signed with the same key, so losing it means users must reinstall.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
OUT_DIR="${LIBRARY_AI_SIGNING_DIR:-$HOME/.library-ai-signing}"
KEYSTORE="$OUT_DIR/release.p12"
ALIAS="libraryai"

command -v openssl >/dev/null || { echo "openssl not found (it ships with Git for Windows)." >&2; exit 1; }
if [ "$DRY_RUN" = 0 ]; then
  command -v gh >/dev/null || { echo "gh (GitHub CLI) not found." >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Run 'gh auth login' first." >&2; exit 1; }
fi
if [ -e "$KEYSTORE" ]; then
  echo "A keystore already exists at $KEYSTORE; refusing to overwrite it." >&2
  echo "Move it away first if you really want a new key." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR" 2>/dev/null || true
umask 077
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Git for Windows ships a native openssl.exe, so give it Windows paths;
# MSYS_NO_PATHCONV below keeps the -subj value from being rewritten as a path.
if command -v cygpath >/dev/null 2>&1; then
  TMP=$(cygpath -m "$TMP"); OUT_DIR=$(cygpath -m "$OUT_DIR"); KEYSTORE="$OUT_DIR/release.p12"
fi

PASSWORD=$(openssl rand -hex 24)

# Self-signed RSA 4096 certificate, valid for 30 years (Play requires > 2033).
MSYS_NO_PATHCONV=1 openssl req -x509 -newkey rsa:4096 -sha256 -days 10950 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=Library AI/O=Library AI" 2>/dev/null
# In PKCS12 the key password and the store password are the same.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$ALIAS" -out "$KEYSTORE" -passout "pass:$PASSWORD"
printf '%s\n' "$PASSWORD" > "$OUT_DIR/password.txt"

# Prove the file opens with that password before anything is uploaded.
openssl pkcs12 -in "$KEYSTORE" -passin "pass:$PASSWORD" -nokeys -noout 2>/dev/null \
  || { echo "Generated keystore failed to open; nothing was uploaded." >&2; exit 1; }
FINGERPRINT=$(openssl x509 -in "$TMP/cert.pem" -noout -fingerprint -sha256 | cut -d= -f2)

echo "Keystore:    $KEYSTORE"
echo "Password:    saved to $OUT_DIR/password.txt"
echo "Alias:       $ALIAS"
echo "SHA-256:     $FINGERPRINT"

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run: no GitHub secrets were set."
  exit 0
fi

# Values go to gh on stdin, never as command-line arguments.
base64 -w0 "$KEYSTORE" | gh secret set KEYSTORE_BASE64
printf '%s' "$PASSWORD" | gh secret set KEYSTORE_PASSWORD
printf '%s' "$PASSWORD" | gh secret set KEY_PASSWORD
printf '%s' "$ALIAS" | gh secret set KEY_ALIAS
echo "Set KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_PASSWORD and KEY_ALIAS."
echo "Back up $OUT_DIR somewhere safe."
