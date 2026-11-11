// App settings overview:
// 1. AppSettings is a plain value object with safe defaults; every field is
//    optional so old stored data and missing fields degrade gracefully.
// 2. AppSettingsStore hides shared_preferences behind an interface, like
//    PuzzleSaveStore — gameplay and screens never import the plugin.
// 3. Storage failures never interrupt the app: loads fall back to defaults,
//    writes are logged in debug builds and otherwise ignored.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player-adjustable preferences.
@immutable
class AppSettings {
  const AppSettings({
    this.effectsVolume = 1,
    this.ghostPreviewDefault = false,
    this.boardColorId = 'tan',
  });

  /// Scales every gameplay sound cue: 0 is silent, 1 is full presence.
  /// The per-cue mix (quiet drop, present chime) is preserved.
  final double effectsVolume;

  /// Whether a puzzle opens with the ghost image hint already visible.
  final bool ghostPreviewDefault;

  /// Board backdrop choice, a BoardColorOption id from studio_theme.dart.
  /// Kept as a plain string so this file stays theme-import-free; unknown
  /// ids fall back to the default at lookup, not here.
  final String boardColorId;

  AppSettings copyWith({
    double? effectsVolume,
    bool? ghostPreviewDefault,
    String? boardColorId,
  }) {
    return AppSettings(
      effectsVolume: effectsVolume ?? this.effectsVolume,
      ghostPreviewDefault: ghostPreviewDefault ?? this.ghostPreviewDefault,
      boardColorId: boardColorId ?? this.boardColorId,
    );
  }

  String toJsonString() => jsonEncode({
    'effectsVolume': effectsVolume,
    'ghostPreviewDefault': ghostPreviewDefault,
    'boardColorId': boardColorId,
  });

  /// Tolerant by field: anything malformed falls back to that field's
  /// default instead of discarding the rest of the settings.
  factory AppSettings.fromJsonString(String raw) {
    const defaults = AppSettings();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map<String, dynamic>) {
      return defaults;
    }
    final volume = decoded['effectsVolume'];
    final ghost = decoded['ghostPreviewDefault'];
    final boardColor = decoded['boardColorId'];
    return AppSettings(
      effectsVolume: volume is num
          ? volume.toDouble().clamp(0, 1)
          : defaults.effectsVolume,
      ghostPreviewDefault: ghost is bool ? ghost : defaults.ghostPreviewDefault,
      boardColorId: boardColor is String ? boardColor : defaults.boardColorId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.effectsVolume == effectsVolume &&
      other.ghostPreviewDefault == ghostPreviewDefault &&
      other.boardColorId == boardColorId;

  @override
  int get hashCode =>
      Object.hash(effectsVolume, ghostPreviewDefault, boardColorId);
}

/// Reads and writes the app settings.
abstract class AppSettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// Device-local storage. Failures are logged in debug builds and handled
/// without throwing — settings must never block playing.
class SharedPreferencesAppSettingsStore implements AppSettingsStore {
  const SharedPreferencesAppSettingsStore();

  static const _key = 'settings.v1';

  @override
  Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) {
        return const AppSettings();
      }
      return AppSettings.fromJsonString(raw);
    } on Object catch (error) {
      _logFailure('load', error);
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(_key, settings.toJsonString());
      if (!saved) {
        _logFailure('save', 'Storage returned false.');
      }
    } on Object catch (error) {
      _logFailure('save', error);
    }
  }

  void _logFailure(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('Settings storage: $operation failed: $error');
    }
  }
}

/// Keeps settings in memory; used by tests.
class InMemorySettingsStore implements AppSettingsStore {
  AppSettings settings = const AppSettings();
  int saves = 0;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = settings;
    saves++;
  }
}
