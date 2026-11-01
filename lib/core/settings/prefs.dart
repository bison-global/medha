import 'package:flutter/foundation.dart';

/// Simple key–value settings. [SettingsRepository] stores them in the
/// encrypted database; [MemoryPrefs] is for tests.
abstract interface class Prefs {
  String? getString(String key);
  void setString(String key, String value);
  bool getBool(String key, {required bool fallback});
  void setBool(String key, bool value);
  int getInt(String key, {required int fallback});
  void setInt(String key, int value);
}

class MemoryPrefs implements Prefs {
  final Map<String, String> values = {};
  @override
  String? getString(String key) => values[key];
  @override
  void setString(String key, String value) => values[key] = value;
  @override
  bool getBool(String key, {required bool fallback}) => values[key] == null ? fallback : values[key] == 'true';
  @override
  void setBool(String key, bool value) => values[key] = '$value';
  @override
  int getInt(String key, {required int fallback}) => int.tryParse(values[key] ?? '') ?? fallback;
  @override
  void setInt(String key, int value) => values[key] = '$value';
}

/// Voice languages offered in Settings (BCP-47 tags for speech engines).
const voiceLanguages = <String, String>{
  'en-IN': 'English',
  'hi-IN': 'हिन्दी',
  'ta-IN': 'தமிழ்',
  'kn-IN': 'ಕನ್ನಡ',
};

/// User settings other than the app lock.
class AppSettings extends ChangeNotifier {
  AppSettings(this.prefs);
  final Prefs prefs;

  bool get saveHistory => prefs.getBool('history.save', fallback: true);
  set saveHistory(bool v) {
    prefs.setBool('history.save', v);
    notifyListeners();
  }

  bool get wifiOnly => prefs.getBool('download.wifiOnly', fallback: true);
  set wifiOnly(bool v) {
    prefs.setBool('download.wifiOnly', v);
    notifyListeners();
  }

  String get voiceLanguage => prefs.getString('voice.language') ?? 'en-IN';
  set voiceLanguage(String v) {
    prefs.setString('voice.language', v);
    notifyListeners();
  }

  bool get readAloud => prefs.getBool('voice.readAloud', fallback: true);
  set readAloud(bool v) {
    prefs.setBool('voice.readAloud', v);
    notifyListeners();
  }
}
