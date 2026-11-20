#!/usr/bin/env bash
# Zanzibarr macOS notarization + stapling.
#
# Signs nothing itself — run AFTER the Developer-ID signing flow:
#   1. flutter build macos --release (lipo shim + build-override)
#   2. xcodebuild archive + exportArchive (Developer ID, ProvisionsAllDevices)
#   3. python3 tools/sign_macos_app.py
#   4. tools/notarize_macos.sh <path-to-zanzibarr.app>
#
# One-time owner setup (the profile lives in the login keychain; the script
# never sees the credentials — do NOT put them in source or shell history):
#   xcrun notarytool store-credentials zanzibarr-notary \
#     --apple-id <your-apple-id> \
#     --team-id 8665FDLXA6 \
#     --password <app-specific-password>
# (app-specific password: appleid.apple.com → Sign-In and Security → App-Specific Passwords)
#
# Output: the final, notarized + stapled distribution zip at
# dist/macos/zanzibarr-macos-arm64.zip — upload it with:
#   gh release upload vX.Y dist/macos/zanzibarr-macos-arm64.zip --clobber

set -euo pipefail

APP_PATH="${1:?usage: notarize_macos.sh <path-to-zanzibarr.app>}"
PROFILE="zanzibarr-notary"
OUT="dist/macos/zanzibarr-macos-arm64.zip"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found (pass the exported zanzibarr.app path)" >&2
  exit 1
fi

# Credentials must already be stored in the login keychain.
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "error: notarytool profile '$PROFILE' missing." >&2
  echo "run once: xcrun notarytool store-credentials $PROFILE \\" >&2
  echo "    --apple-id <apple-id> --team-id 8665FDLXA6 --password <app-specific-password>" >&2
  exit 1
fi

echo "==> codesign sanity check"
codesign --verify --deep --strict "$APP_PATH"

# Submission copy: staple attaches the ticket to the .app bundle, so the
# DISTRIBUTION zip must be re-created after stapling; a temp zip is used
# only for the submission itself.
SUBMIT_ZIP="$(mktemp -t zanzibarr-notary).zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMIT_ZIP"

echo "==> submitting to Apple notary service and waiting (this can take minutes)"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$SUBMIT_ZIP"

echo "==> stapling"
# Xcode 27: notarytool'un 'staple' alt komutu yok; staple her zaman
# 'xcrun stapler' ile yapilir (onceki denemede auth bosuna hata uretirdi).
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Gatekeeper check (should now say Accepted)"
spctl -a -vv "$APP_PATH"

echo "==> packaging final distribution zip"
rm -f "$OUT"
mkdir -p "$(dirname "$OUT")"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUT"

echo "done: $OUT (notarized, stapled, signed)"
