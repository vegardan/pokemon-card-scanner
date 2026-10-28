import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  static final _preferences = SharedPreferencesAsync();
  static const _skipGuideKey = 'skip_scan_guide';

  static Future<bool> skipScanGuide() async => await _preferences.getBool(_skipGuideKey) ?? false;

  static Future<void> setSkipScanGuide(bool skip) => _preferences.setBool(_skipGuideKey, skip);
}
