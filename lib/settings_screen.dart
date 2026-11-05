// Settings screen overview:
// 1. Loads the stored settings once, then shows them on painted cards.
// 2. Every change persists immediately — there is no save button; leaving
//    the screen never loses a choice. The slider persists once per gesture.
// 3. A music volume slider joins the sound card when the ambient loop
//    lands (see the plan's cozy-audio note); effects-only until then.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'studio_surfaces.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.store = const SharedPreferencesAppSettingsStore(),
  });

  /// Tests pass an in-memory store.
  final AppSettingsStore store;

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

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
                          Icon(
                            settings.effectsVolume == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                            color: theme.colorScheme.onSurface,
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PaintedCard(
                  variant: 1,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Semantics(
                    identifier: 'settings-ghost-default',
                    child: SwitchListTile(
                      title: const Text('Start with the image preview'),
                      subtitle: const Text(
                        'New puzzles open with the faint picture hint on.',
                      ),
                      value: settings.ghostPreviewDefault,
                      onChanged: (value) =>
                          _apply(settings.copyWith(ghostPreviewDefault: value)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
