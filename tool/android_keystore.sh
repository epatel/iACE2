#!/usr/bin/env bash
# Creates the Android upload key for Google Play and android/key.properties, which the release
# build reads (see android/app/build.gradle.kts). Run through `make keystore`.
#
#   tool/android_keystore.sh [keystore path]     default: ~/.android-keys/iace-upload.jks
#
# Environment (all optional):
#   KEYSTORE_PASSWORD  use this password instead of asking (e.g. for CI)
#   KEY_PROPERTIES     where to write the properties (default: android/key.properties)
#   DNAME              certificate owner (default: CN=Edward Patel, O=Memention AB, C=SE)
#
# Never commit the keystore or key.properties. Back up the keystore and password: with Play App
# Signing a lost upload key can be reset through Play Console support, but it takes time.
set -euo pipefail
cd "$(dirname "$0")/.."

KEYSTORE="${1:-$HOME/.android-keys/iace-upload.jks}"
PROPS="${KEY_PROPERTIES:-android/key.properties}"
DNAME="${DNAME:-CN=Edward Patel, O=Memention AB, C=SE}"
ALIAS=upload

# macOS ships a keytool stub without a Java runtime; prefer a real JDK.
keytool_bin() {
  for candidate in "${JAVA_HOME:-}/bin/keytool" \
      "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
      "$(command -v keytool || true)"; do
    if [ -x "$candidate" ] && "$candidate" -help >/dev/null 2>&1; then
      echo "$candidate"
      return
    fi
  done
  echo "No working keytool found: install a JDK or Android Studio, or set JAVA_HOME." >&2
  exit 1
}
KEYTOOL="$(keytool_bin)"

if [ -e "$PROPS" ]; then
  echo "$PROPS already exists; not overwriting it." >&2
  exit 1
fi

if [ -n "${KEYSTORE_PASSWORD:-}" ]; then
  PASSWORD="$KEYSTORE_PASSWORD"
else
  if [ ! -t 0 ]; then
    echo "No terminal to ask for the password: run 'make keystore' in a terminal," >&2
    echo "or set KEYSTORE_PASSWORD." >&2
    exit 1
  fi
  read -r -s -p "Keystore password (6+ characters): " PASSWORD; echo
  read -r -s -p "Repeat password: " AGAIN; echo
  if [ "$PASSWORD" != "$AGAIN" ]; then echo "Passwords differ." >&2; exit 1; fi
fi
if [ "${#PASSWORD}" -lt 6 ]; then echo "The password must be at least 6 characters." >&2; exit 1; fi
export IACE_STOREPASS="$PASSWORD"

if [ -e "$KEYSTORE" ]; then
  echo "Using the existing keystore $KEYSTORE"
  "$KEYTOOL" -list -keystore "$KEYSTORE" -storepass:env IACE_STOREPASS -alias "$ALIAS" >/dev/null
else
  mkdir -p "$(dirname "$KEYSTORE")"
  chmod 700 "$(dirname "$KEYSTORE")"
  "$KEYTOOL" -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 -alias "$ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10000 -dname "$DNAME" \
    -storepass:env IACE_STOREPASS -keypass:env IACE_STOREPASS 2>/dev/null
  chmod 600 "$KEYSTORE"
  echo "Created $KEYSTORE"
fi

umask 077
cat > "$PROPS" <<PROPERTIES
# Upload key for Google Play (created by tool/android_keystore.sh). Never commit this file.
storeFile=$KEYSTORE
storePassword=$PASSWORD
keyAlias=$ALIAS
keyPassword=$PASSWORD
PROPERTIES
echo "Wrote $PROPS"
echo "Upload certificate:"
"$KEYTOOL" -list -v -keystore "$KEYSTORE" -storepass:env IACE_STOREPASS -alias "$ALIAS" \
  | grep -E "Owner|SHA256:" | sed 's/^/  /'
echo "Back up $KEYSTORE and its password somewhere safe (not in the repo)."
