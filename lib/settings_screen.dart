// Settings screen overview:
// 1. Loads the stored settings once, then shows them on painted cards.
// 2. Every change persists immediately — there is no save button; leaving
//    the screen never loses a choice. The slider persists once per gesture.
// 3. The music slider also drives the app-wide loop live while dragging,
//    through the player instance the shell owns and hands in.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'background_music.dart';
import 'riso_icons.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.store = const SharedPreferencesAppSettingsStore(),
    this.music,
  });

  /// Tests pass an in-memory store.
  final AppSettingsStore store;

  /// The ambient loop the music slider adjusts live; null leaves the
  /// slider storage-only (screens under test).
  final BackgroundMusic? music;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Null until the stored settings arrive; the UI renders nothing before
  /// that so a slider never flashes a default it is about to replace.
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.store.load();
    if (mounted) {
      setState(() => _settings = settings);
    }
  }

  /// Shows [next] immediately and persists it in the background.
  void _apply(AppSettings next) {
    setState(() => _settings = next);
    widget.store.save(next);
  }

  /// One chrome for every toggle card, so they can't drift apart.
  Widget _switchCard({
    required String identifier,
    required RisoGlyph glyph,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return PaintedCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Semantics(
        identifier: identifier,
        child: SwitchListTile(
          secondary: RisoIcon(glyph),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: risoAppBar('Settings'),
      body: settings == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PaintedCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sound', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Effect sounds: the drop, the snap, and the chime.',
                        style: theme.textTheme.bodySmall,
                      ),
                      Row(
                        children: [
                          RisoIcon(
                            RisoGlyph.speaker,
                            // Muted ink when silent — the riso set has no
                            // slashed variant; dimming reads as "off".
                            color: settings.effectsVolume == 0
                                ? StudioColors.mutedInk
                                : theme.colorScheme.onSurface,
                          ),
                          Expanded(
                            child: Semantics(
                              identifier: 'settings-effects-volume',
                              child: Slider(
                                value: settings.effectsVolume,
                                label:
                                    '${(settings.effectsVolume * 100).round()}%',
                                // Track the drag live, but hit storage only
                                // once, when the finger lifts.
                                onChanged: (value) => setState(
                                  () => _settings = settings.copyWith(
                                    effectsVolume: value,
                                  ),
                                ),
                                onChangeEnd: (_) =>
                                    widget.store.save(_settings!),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Music: the quiet loop behind every screen.',
                        style: theme.textTheme.bodySmall,
                      ),
                      Row(
                        children: [
                          RisoIcon(
                            RisoGlyph.music,
                            color: settings.musicVolume == 0
                                ? StudioColors.mutedInk
                                : theme.colorScheme.onSurface,
                          ),
                          Expanded(
                            child: Semantics(
                              identifier: 'settings-music-volume',
                              child: Slider(
                                value: settings.musicVolume,
                                label:
                                    '${(settings.musicVolume * 100).round()}%',
                                // The playing loop follows the drag so muting
                                // is audible at once; storage still waits for
                                // the finger to lift.
                                onChanged: (value) {
                                  widget.music?.setVolume(value);
                                  setState(
                                    () => _settings = settings.copyWith(
                                      musicVolume: value,
                                    ),
                                  );
                                },
                                onChangeEnd: (_) =>
                                    widget.store.save(_settings!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _switchCard(
                  identifier: 'settings-haptics',
                  glyph: RisoGlyph.vibrate,
                  title: 'Vibrate on snap',
                  subtitle:
                      'A light tap when a piece fits, and the buzz when '
                      'you finish.',
                  value: settings.hapticsEnabled,
                  onChanged: (value) =>
                      _apply(settings.copyWith(hapticsEnabled: value)),
                ),
                const SizedBox(height: 16),
                _switchCard(
                  identifier: 'settings-ghost-default',
                  // The same ghost-picture as the play screen's preview
                  // toggle: one icon, one meaning.
                  glyph: RisoGlyph.imagePreview,
                  title: 'Start with the image preview',
                  subtitle: 'New puzzles open with the faint picture hint on.',
                  value: settings.ghostPreviewDefault,
                  onChanged: (value) =>
                      _apply(settings.copyWith(ghostPreviewDefault: value)),
                ),
              ],
            ),
    );
  }
}
