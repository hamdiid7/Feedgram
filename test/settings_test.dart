import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feedgram/data/settings_store.dart';
import 'package:feedgram/data/storage_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('defaults', () {
    test('follows the system theme until told otherwise', () async {
      final settings = await SettingsStore.open();
      expect(settings.themeMode, ThemeMode.system);
    });

    test('images and video load, data saver off', () async {
      final settings = await SettingsStore.open();
      expect(settings.dataSaver, isFalse);
      expect(settings.autoLoadImages, isTrue);
      expect(settings.autoplayVideo, isTrue);
    });
  });

  group('persistence', () {
    test('a theme choice survives a restart', () async {
      // The whole reason shared_preferences was added: before this every choice
      // was session-only, so dark mode reverted on every launch.
      final first = await SettingsStore.open();
      first.setThemeMode(ThemeMode.dark);

      final reopened = await SettingsStore.open();
      expect(reopened.themeMode, ThemeMode.dark);
    });

    test('the data switches survive a restart', () async {
      final first = await SettingsStore.open();
      first.setAutoLoadImages(false);
      first.setAutoplayVideo(false);

      final reopened = await SettingsStore.open();
      expect(reopened.autoLoadImagesPreference, isFalse);
      expect(reopened.autoplayVideoPreference, isFalse);
    });

    test('an unrecognised stored theme falls back to system', () async {
      // Defends against a downgrade or a hand-edited prefs file naming a mode
      // this build does not have.
      SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
      final settings = await SettingsStore.open();
      expect(settings.themeMode, ThemeMode.system);
    });
  });

  group('data saver', () {
    test('overrides both switches while on', () async {
      final settings = await SettingsStore.open();
      settings.setDataSaver(true);

      expect(settings.autoLoadImages, isFalse);
      expect(settings.autoplayVideo, isFalse);
    });

    test('turning it off restores what you had chosen, not a guess', () async {
      // Why data saver overrides rather than rewrites: someone who had video off
      // and images on must get that back, not both switched on.
      final settings = await SettingsStore.open();
      settings.setAutoplayVideo(false);
      settings.setDataSaver(true);
      settings.setDataSaver(false);

      expect(settings.autoLoadImages, isTrue, reason: 'was on before');
      expect(settings.autoplayVideo, isFalse, reason: 'was off before');
    });

    test('the underlying preferences are left alone while it is on', () async {
      final settings = await SettingsStore.open();
      settings.setDataSaver(true);

      expect(settings.autoLoadImagesPreference, isTrue);
      expect(settings.autoplayVideoPreference, isTrue);
    });
  });

  group('notifications', () {
    test('every setter notifies, so the theme and feed both react', () async {
      final settings = await SettingsStore.open();
      var notifications = 0;
      settings.addListener(() => notifications++);

      settings.setThemeMode(ThemeMode.light);
      settings.setDataSaver(true);
      settings.setAutoLoadImages(false);
      settings.setAutoplayVideo(false);

      expect(notifications, 4);
    });
  });

  group('formatBytes', () {
    test('scales up through the units', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('drops the decimal once it would be noise', () {
      // "278 MB" not "278.4 MB" — a tenth of a megabyte is not information at
      // that scale, and the extra digit makes the column ragged.
      expect(formatBytes(278 * 1024 * 1024), '278 MB');
    });

    test('binary units, matching what Android reports', () {
      // 1000 bytes is not a kilobyte here. If this used decimal units the
      // numbers would disagree with the system storage screen.
      expect(formatBytes(1000), '1000 B');
      expect(formatBytes(1024), '1.0 KB');
    });
  });
}
