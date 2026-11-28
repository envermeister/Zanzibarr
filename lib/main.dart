import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_shell.dart';
import 'player/playback_tabs.dart';
import 'player/player_launcher.dart';
import 'player/player_screen.dart';
import 'settings/ui_preferences.dart';

export 'app_shell.dart' show HomeScreen, ZanzibarrApp, ZanzibarrBootstrap;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PlayerLauncher.register(
    ({key, required nzbPath, initialEntryKey, tabProfile, onRequestClose}) =>
        PlayerScreen(
          key: key,
          nzbPath: nzbPath,
          initialEntryKey: initialEntryKey,
          tabProfile: tabProfile,
          onRequestClose: onRequestClose,
        ),
    fileSelection: true,
  );
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    PlaybackTabsCoordinator.enable();
  }

  // Developer diagnostics: open an NZB directly at startup.
  final debugNzb = Platform.environment['ZANZIBARR_DEBUG_NZB'];
  runApp(
    ZanzibarrBootstrap(
      uiPreferences: UiPreferencesController(UiPreferencesStore()),
      debugNzbPath: debugNzb?.isNotEmpty == true ? debugNzb : null,
    ),
  );
}
