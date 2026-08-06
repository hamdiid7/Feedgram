import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences, persisted across launches.
///
/// A [ChangeNotifier] rather than state on a widget: the theme is read at the
/// very top of the tree and the data toggles are read deep inside the feed, so a
/// single store both can listen to beats threading callbacks through everything
/// in between.
///
/// Writes are fire-and-forget. Nothing here is worth blocking a switch's
/// animation on, and a preference that fails to save is a preference that
/// reverts on next launch — not data loss.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs);

  static const _themeKey = 'theme_mode';
  static const _dataSaverKey = 'data_saver';
  static const _autoLoadImagesKey = 'auto_load_images';
  static const _autoplayVideoKey = 'autoplay_video';

  final SharedPreferences _prefs;

  static Future<SettingsStore> open() async =>
      SettingsStore._(await SharedPreferences.getInstance());

  // ---------------------------------------------------------------------------
  // Appearance
  // ---------------------------------------------------------------------------

  /// Defaults to following the OS, which is what an Android app should do until
  /// told otherwise.
  ThemeMode get themeMode => switch (_prefs.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  void setThemeMode(ThemeMode mode) {
    _prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  /// Master switch. When on it *overrides* the two switches below rather than
  /// rewriting them, so turning data saver off again restores whatever you had
  /// chosen before instead of a guess.
  bool get dataSaver => _prefs.getBool(_dataSaverKey) ?? false;

  void setDataSaver(bool value) {
    _prefs.setBool(_dataSaverKey, value);
    notifyListeners();
  }

  /// What the images switch is set to, ignoring data saver.
  bool get autoLoadImagesPreference =>
      _prefs.getBool(_autoLoadImagesKey) ?? true;

  void setAutoLoadImages(bool value) {
    _prefs.setBool(_autoLoadImagesKey, value);
    notifyListeners();
  }

  /// What the video switch is set to, ignoring data saver.
  bool get autoplayVideoPreference => _prefs.getBool(_autoplayVideoKey) ?? true;

  void setAutoplayVideo(bool value) {
    _prefs.setBool(_autoplayVideoKey, value);
    notifyListeners();
  }

  /// Whether images actually load. This is the one the feed should ask.
  bool get autoLoadImages => !dataSaver && autoLoadImagesPreference;

  /// Whether video actually autoplays. This is the one the feed should ask.
  bool get autoplayVideo => !dataSaver && autoplayVideoPreference;
}
