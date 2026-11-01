#!/usr/bin/env bash
# Generates the android/ and ios/ host projects with `flutter create` and
# applies Medha's settings. Safe to re-run; existing settings are kept.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create . --platforms=android,ios --org com.bisonglobaltech --project-name medha

# ---------- Android ----------
MANIFEST=android/app/src/main/AndroidManifest.xml
add_permission() {
  grep -q "$1" "$MANIFEST" || perl -0pi -e "s|(<manifest[^>]*>)|\$1\n    <uses-permission android:name=\"$1\"/>|" "$MANIFEST"
}
add_permission android.permission.INTERNET          # catalog, model downloads, reports
add_permission android.permission.RECORD_AUDIO      # voice chat
add_permission android.permission.USE_BIOMETRIC     # app lock

add_query() {
  grep -q "$2" "$MANIFEST" || perl -0pi -e "s|(<queries>)|\$1\n        $1|" "$MANIFEST"
}
if ! grep -q '<queries>' "$MANIFEST"; then
  perl -0pi -e 's|(</application>)|$1\n    <queries>\n    </queries>|' "$MANIFEST"
fi
add_query '<intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>' 'android.intent.action.DIAL'
add_query '<intent><action android:name="android.speech.RecognitionService"/></intent>' 'android.speech.RecognitionService'
add_query '<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>' 'android.intent.action.TTS_SERVICE'

# local_auth needs a FragmentActivity.
for f in $(find android/app/src/main -name 'MainActivity.kt' -o -name 'MainActivity.java'); do
  perl -pi -e 's/io\.flutter\.embedding\.android\.FlutterActivity\b/io.flutter.embedding.android.FlutterFragmentActivity/; s/:\s*FlutterActivity\(\)/: FlutterFragmentActivity()/; s/extends FlutterActivity\b/extends FlutterFragmentActivity/' "$f"
done

for g in android/app/build.gradle.kts android/app/build.gradle; do
  [[ -f "$g" ]] && perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 28/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 28/' "$g"
done

# ---------- iOS ----------
if [[ -f ios/Podfile ]]; then
  perl -pi -e "s/^#?\s*platform :ios, '[0-9.]+'/platform :ios, '15.0'/" ios/Podfile
fi
PLIST=ios/Runner/Info.plist
add_plist() {
  grep -q "<key>$1</key>" "$PLIST" || perl -0pi -e "s|(<dict>\n)|\$1\t<key>$1</key>\n\t<string>$2</string>\n|" "$PLIST"
}
if [[ -f "$PLIST" ]]; then
  add_plist NSFaceIDUsageDescription 'Medha uses Face ID to unlock your chats.'
  add_plist NSMicrophoneUsageDescription 'Medha listens only while you hold a voice chat. Audio never leaves your phone.'
  add_plist NSSpeechRecognitionUsageDescription 'Your speech is turned into text on this phone for voice chat.'
fi

echo "Platform projects ready. iOS also needs: ./tool/build_ios_llama.sh (on macOS)."
