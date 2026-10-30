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

python3 tool/enable_desugaring.py

MANIFEST="android/app/src/main/AndroidManifest.xml"

if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
fi

# Deadline reminders (flutter_local_notifications): POST_NOTIFICATIONS for
# Android 13+, RECEIVE_BOOT_COMPLETED + receivers so reminders survive a
# reboot. Each guard keeps the script idempotent.
for PERMISSION in 'android.permission.POST_NOTIFICATIONS' 'android.permission.RECEIVE_BOOT_COMPLETED' 'android.permission.VIBRATE'; do
  if ! grep -q "$PERMISSION" "$MANIFEST"; then
    sed -i "s#<application#    <uses-permission android:name=\"$PERMISSION\"/>\n    <application#" "$MANIFEST"
  fi
done

if ! grep -q 'ScheduledNotificationReceiver' "$MANIFEST"; then
  sed -i 's#</application>#    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n      <intent-filter>\n        <action android:name="android.intent.action.BOOT_COMPLETED" />\n      </intent-filter>\n    </receiver>\n</application>#' "$MANIFEST"
fi

sed -i 's#android:label="[^"]*"#android:label="VasFlow"#' "$MANIFEST"

echo "---- AndroidManifest.xml after preparation ----"
cat "$MANIFEST"
