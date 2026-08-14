#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

APP_NAME="SimSlim Menu"
APP_PATH="dist/${APP_NAME}.app"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ARCHIVE_PATH="dist/${APP_NAME}-${VERSION}.zip"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  print -u2 "SIGNING_IDENTITY must name an installed Developer ID Application certificate."
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  print -u2 "Signing identity is not installed: $SIGNING_IDENTITY"
  exit 1
fi

VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ./scripts/build-app.sh

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"

  rm -f "$ARCHIVE_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
else
  print -u2 "Warning: NOTARY_PROFILE is not set. The build is signed but not notarized."
fi

shasum -a 256 "$ARCHIVE_PATH" > "${ARCHIVE_PATH}.sha256"
echo "Release: $PWD/$ARCHIVE_PATH"
echo "Checksum: $PWD/${ARCHIVE_PATH}.sha256"
