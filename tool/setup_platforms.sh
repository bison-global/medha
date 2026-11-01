#!/usr/bin/env bash
# Generates the android/ and ios/ host projects with `flutter create` and
# applies Medha's settings. Safe to re-run; existing files are kept.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create . --platforms=android,ios --org com.bisonglobaltech --project-name medha

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  # Release builds need INTERNET for catalog fetches and model downloads.
  perl -0pi -e 's|(<manifest[^>]*>)|$1\n    <uses-permission android:name="android.permission.INTERNET"/>|' "$MANIFEST"
fi
if ! grep -q 'android.intent.action.DIAL' "$MANIFEST"; then
  # Lets the crisis card open the phone dialer (Android 11+ package visibility).
  perl -0pi -e 's|(<queries>)|$1\n        <intent>\n            <action android:name="android.intent.action.DIAL"/>\n            <data android:scheme="tel"/>\n        </intent>|' "$MANIFEST"
fi

for g in android/app/build.gradle.kts android/app/build.gradle; do
  [[ -f "$g" ]] && perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 28/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 28/' "$g"
done

if [[ -f ios/Podfile ]]; then
  perl -pi -e "s/^#?\s*platform :ios, '[0-9.]+'/platform :ios, '15.0'/" ios/Podfile
fi

echo "Platform projects ready. iOS also needs: ./tool/build_ios_llama.sh (on macOS)."
