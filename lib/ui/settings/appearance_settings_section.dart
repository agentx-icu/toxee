import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/interface_style.dart';
import '../../util/app_theme_config.dart';
import '../../util/theme_controller.dart';
import '../testing/ui_keys.dart';
import '../widgets/section_header.dart';

part 'appearance_settings_widgets.dart';

typedef AppearanceSaver =
    Future<void> Function({
      required InterfaceStyle style,
      required ThemeMode mode,
    });

/// Stages device-wide appearance locally. Only Apply publishes global changes.
class AppearanceSettingsSection extends StatefulWidget {
  const AppearanceSettingsSection({super.key, this.saveAppearance});

  final AppearanceSaver? saveAppearance;

  @override
  State<AppearanceSettingsSection> createState() =>
      _AppearanceSettingsSectionState();
}

class _AppearanceSettingsSectionState extends State<AppearanceSettingsSection> {
  late InterfaceStyle _style;
  late InterfaceStyle _savedStyle;
  late ThemeMode _mode;
  late ThemeMode _savedMode;
  bool _saving = false;
  bool _saveFailed = false;

  bool get _hasChanges => _style != _savedStyle || _mode != _savedMode;

  @override
  void initState() {
    super.initState();
    _style = _savedStyle = AppTheme.style.value;
    _mode = _savedMode = AppTheme.mode.value;
    AppTheme.style.addListener(_onGlobalAppearanceChanged);
    AppTheme.mode.addListener(_onGlobalAppearanceChanged);
  }

  @override
  void dispose() {
    AppTheme.style.removeListener(_onGlobalAppearanceChanged);
    AppTheme.mode.removeListener(_onGlobalAppearanceChanged);
    super.dispose();
  }

  void _onGlobalAppearanceChanged() {
    if (_saving || _hasChanges) return;
    setState(() {
      _style = _savedStyle = AppTheme.style.value;
      _mode = _savedMode = AppTheme.mode.value;
    });
  }

  void _selectStyle(InterfaceStyle style) {
    if (_saving) return;
    setState(() {
      _style = style;
      _saveFailed = false;
    });
  }

  void _selectMode(ThemeMode mode) {
    if (_saving) return;
    setState(() {
      _mode = mode;
      _saveFailed = false;
    });
  }

  void _reset() {
    if (_saving) return;
    setState(() {
      _style = InterfaceStyle.classic;
      _mode = ThemeMode.system;
      _saveFailed = false;
    });
  }

  Future<void> _apply() async {
    if (_saving || !_hasChanges) return;
    final style = _style;
    final mode = _mode;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await (widget.saveAppearance ?? AppTheme.setAppearance)(
        style: style,
        mode: mode,
      );
      if (!mounted) return;
      setState(() {
        _savedStyle = style;
        _savedMode = mode;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  Brightness _brightness(BuildContext context) => switch (_mode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => MediaQuery.platformBrightnessOf(context),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final brightness = _brightness(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: l10n.appearance),
            const SizedBox(height: 16),
            Text(
              l10n.interfaceStyle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = math.max(
                  1,
                  math.min(5, (constraints.maxWidth / 140).floor()),
                );
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: InterfaceStyle.values
                      .map(
                        (style) => SizedBox(
                          width: width,
                          child: _StyleChoice(
                            style: style,
                            brightness: brightness,
                            label: _styleName(l10n, style),
                            selected: style == _style,
                            onTap: _saving ? null : () => _selectStyle(style),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              l10n.appearanceBrightness,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              key: UiKeys.settingsThemeSegment,
              width: double.infinity,
              child: _BrightnessChoices(
                mode: _mode,
                onChanged: _saving ? null : _selectMode,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.appearancePreview,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            _ChatPreview(style: _style, brightness: brightness),
            if (_hasChanges) ...[
              const SizedBox(height: 12),
              Text(
                l10n.appearancePending,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_saveFailed) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.appearanceSaveFailed,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  key: const Key('settings_appearance_apply'),
                  onPressed: _hasChanges && !_saving ? _apply : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 44),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_saving) ...[
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(l10n.appearanceApply),
                    ],
                  ),
                ),
                TextButton(
                  key: const Key('settings_appearance_reset'),
                  onPressed: _saving ? null : _reset,
                  style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
                  child: Text(l10n.reset),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _styleName(AppLocalizations l10n, InterfaceStyle style) =>
    switch (style) {
      InterfaceStyle.classic => l10n.interfaceStyleClassic,
      InterfaceStyle.modern => l10n.interfaceStyleModern,
      InterfaceStyle.night => l10n.interfaceStyleNight,
      InterfaceStyle.paper => l10n.interfaceStylePaper,
      InterfaceStyle.cartoon => l10n.interfaceStyleCartoon,
    };
