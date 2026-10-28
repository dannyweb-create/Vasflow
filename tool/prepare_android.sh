#!/usr/bin/env bash
# Prepares the Android part of the project for a cloud build.
# - Creates the android/ folder if it is missing (this repo only stores Dart code).
# - Makes sure the release app is allowed to use the internet (needed for Supabase).
# - Sets the app name shown on the phone.
# Safe to run more than once.
set -euo pipefail

if [ ! -d android ]; then
  flutter create --platforms=android --org com.vasflow --project-name vasflow .
fi

MANIFEST="android/app/src/main/AndroidManifest.xml"

if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
fi

sed -i 's#android:label="[^"]*"#android:label="VasFlow"#' "$MANIFEST"

echo "---- AndroidManifest.xml after preparation ----"
cat "$MANIFEST"
