import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/appearance_sync.dart';
import '../../util/locale_controller.dart';
import '../../util/logger.dart';
import '../../util/theme_controller.dart';
import '../../util/prefs.dart';
import '../../i18n/app_localizations.dart';
import '../testing/ui_keys.dart';
import '../widgets/section_header.dart';
import '_hoverable_settings_row.dart';

/// Which subset of the global settings to render. Desktop shows everything on
/// one page ([all]); the mobile settings list splits it into an "Appearance"
/// entry (theme + language) and a "General" entry (notification sound,
/// downloads directory, auto-download size limit).
enum GlobalSettingsView { all, appearance, general }

/// Global app settings (appearance, language, notification sound, downloads, auto-download).
/// Shown on both login settings and main settings. When [toxId] is null (login page),
/// notification sound is hidden.
class GlobalSettingsSection extends StatefulWidget {
  const GlobalSettingsSection({
    super.key,
    required this.colorTheme,
    this.toxId,
    this.onDownloadsConfigChanged,
    this.view = GlobalSettingsView.all,
  });

  final dynamic colorTheme;

  /// Which subset of settings to render (see [GlobalSettingsView]).
  final GlobalSettingsView view;

  /// When non-null, show notification sound setting (per-account).
  final String? toxId;

  /// Optional hook the host can use to notify the running FfiChatService when
  /// the downloads directory or auto-download size limit changes. The service
  /// reads Prefs on-demand for each file transfer so this is currently
  /// advisory (e.g. for refresh/log surfaces), but the contract lets future
  /// callers push a value down without re-plumbing this widget.
  final VoidCallback? onDownloadsConfigChanged;

  @override
  State<GlobalSettingsSection> createState() => _GlobalSettingsSectionState();
}

class _GlobalSettingsSectionState extends State<GlobalSettingsSection> {
  bool _languageExpanded = false;
  bool _notificationSoundEnabled = true;
  final TextEditingController _downloadsDirectoryController =
      TextEditingController();
  final TextEditingController _sizeLimitController = TextEditingController();

  dynamic get _colorTheme => widget.colorTheme;

  bool _isLocaleEqual(Locale a, Locale b) {
    if (a.languageCode != b.languageCode) return false;
    if (a.scriptCode != null && b.scriptCode != null)
      return a.scriptCode == b.scriptCode;
    if (a.scriptCode != null || b.scriptCode != null) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadNotificationSoundSetting();
    _loadDownloadsDirectory();
    _loadAutoDownloadSizeLimit();
  }

  @override
  void dispose() {
    _downloadsDirectoryController.dispose();
    _sizeLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadNotificationSoundSetting() async {
    final toxId = widget.toxId;
    if (toxId == null || toxId.isEmpty) return;
    final enabled = await Prefs.getNotificationSoundEnabled(toxId);
    if (mounted) setState(() => _notificationSoundEnabled = enabled);
  }

  Future<void> _setNotificationSoundEnabled(bool value) async {
    final toxId = widget.toxId;
    if (toxId == null || toxId.isEmpty) return;
    await Prefs.setNotificationSoundEnabled(value, toxId);
    if (mounted) setState(() => _notificationSoundEnabled = value);
  }

  Future<String?> _getDefaultDownloadsDirectory() async {
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) return p.join(home, 'Downloads');
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) return p.join(userProfile, 'Downloads');
      } else if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getApplicationDocumentsDirectory();
        return p.join(appDir.path, 'Downloads');
      }
    } catch (e) {
      AppLogger.warn(
        '[GlobalSettings] default downloads directory lookup failed: $e',
      );
    }
    return null;
  }

  Future<void> _loadDownloadsDirectory() async {
    final dir = await Prefs.getDownloadsDirectory();
    final defaultDir = await _getDefaultDownloadsDirectory();
    if (mounted) {
      setState(() {
        _downloadsDirectoryController.text = dir ?? defaultDir ?? '';
      });
    }
  }

  /// True on platforms where FilePicker.platform.getDirectoryPath() works.
  /// Android/iOS surface a directory picker that returns content:// URIs we
  /// can't write through dart:io File APIs, so we hide the picker entirely
  /// on mobile rather than show a button that does nothing useful.
  bool get _supportsDirectoryPicker =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _selectDownloadsDirectory() async {
    if (!mounted) return;
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await Prefs.setDownloadsDirectory(selectedDirectory);
        widget.onDownloadsConfigChanged?.call();
        if (mounted) {
          setState(
            () => _downloadsDirectoryController.text = selectedDirectory,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context)!.failedToSelectDirectory}: $e',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _loadAutoDownloadSizeLimit() async {
    final limit = await Prefs.getAutoDownloadSizeLimit();
    if (mounted) {
      setState(() => _sizeLimitController.text = limit.toString());
    }
  }

  Future<void> _saveAutoDownloadSizeLimit() async {
    final text = _sizeLimitController.text.trim();
    final limit = int.tryParse(text);
    if (limit != null && limit > 0 && limit <= 10000) {
      await Prefs.setAutoDownloadSizeLimit(limit);
      widget.onDownloadsConfigChanged?.call();
      if (mounted) setState(() {});
    }
  }

  Color _primaryTextColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.primaryTextColor != null) {
      return _colorTheme.primaryTextColor as Color;
    }
    return Theme.of(context).colorScheme.onSurface;
  }

  Color _secondaryTextColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.secondaryTextColor != null) {
      return _colorTheme.secondaryTextColor as Color;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final tL10n = TencentCloudChatLocalizations.of(context);
    if (tL10n == null) return const SizedBox.shrink();

    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    final showAppearance = widget.view != GlobalSettingsView.general;
    final showGeneral = widget.view != GlobalSettingsView.appearance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAppearance) ...[
        // Appearance
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: outlineVariant),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: tL10n.appearance),
                AppSpacing.verticalSm,
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppTheme.mode,
                  builder: (context, mode, _) {
                    return SizedBox(
                      // Scroll anchor for real-UI automation (the segment labels
                      // aren't individually surfaced; the harness scrolls this
                      // keyed box into the viewport before tapping a segment).
                      key: UiKeys.settingsThemeSegment,
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        // Three segments: System / Light / Dark.
                        segments: <ButtonSegment<ThemeMode>>[
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            icon: const Icon(Icons.brightness_auto),
                            label: Text(
                              AppLocalizations.of(context)!.themeSystem,
                            ),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            icon: const Icon(Icons.light_mode),
                            label: Text(
                              AppLocalizations.of(context)!.themeLight,
                            ),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            icon: const Icon(Icons.dark_mode),
                            label: Text(
                              AppLocalizations.of(context)!.themeDark,
                            ),
                          ),
                        ],
                        selected: <ThemeMode>{mode},
                        showSelectedIcon: false,
                        onSelectionChanged: (Set<ThemeMode> selection) {
                          final chosen = selection.first;
                          // Shared applier: app theme + UIKit brightness in
                          // one step (also used by l3_set_setting{themeMode}).
                          unawaited(
                            applyThemeModeEverywhere(
                              chosen,
                              platformBrightness:
                                  MediaQuery.platformBrightnessOf(context),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        AppSpacing.verticalMd,
        // Language
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: outlineVariant),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: tL10n.language),
                AppSpacing.verticalSm,
                ValueListenableBuilder<Locale>(
                  valueListenable: AppLocale.locale,
                  builder: (context, loc, _) {
                    final appL10n = AppLocalizations.of(context)!;
                    final languages = [
                      (locale: const Locale('en'), label: appL10n.english),
                      (
                        locale: const Locale.fromSubtags(
                          languageCode: 'zh',
                          scriptCode: 'Hans',
                        ),
                        label: appL10n.simplifiedChinese,
                      ),
                      (
                        locale: const Locale.fromSubtags(
                          languageCode: 'zh',
                          scriptCode: 'Hant',
                        ),
                        label: appL10n.traditionalChinese,
                      ),
                      (locale: const Locale('ja'), label: appL10n.japanese),
                      (locale: const Locale('ko'), label: appL10n.korean),
                      (locale: const Locale('ar'), label: appL10n.arabic),
                    ];
                    Locale? selectedLocale;
                    for (final lang in languages) {
                      if (_isLocaleEqual(loc, lang.locale)) {
                        selectedLocale = lang.locale;
                        break;
                      }
                    }
                    if (selectedLocale == null) {
                      for (final lang in languages) {
                        if (loc.languageCode == lang.locale.languageCode) {
                          if (loc.languageCode == 'zh' &&
                              loc.scriptCode == null) {
                            if (lang.locale.scriptCode == 'Hans') {
                              selectedLocale = lang.locale;
                              break;
                            }
                          } else {
                            selectedLocale = lang.locale;
                            break;
                          }
                        }
                      }
                    }
                    selectedLocale ??= languages.first.locale;
                    final selectedLabel = languages
                        .firstWhere(
                          (l) => _isLocaleEqual(l.locale, selectedLocale!),
                          orElse: () => languages.first,
                        )
                        .label;
                    void selectLocale(Locale newLocale) {
                      // Shared applier: app locale + UIKit intl in one step
                      // (also used by l3_set_setting{languageCode}).
                      unawaited(applyLocaleEverywhere(newLocale));
                      setState(() => _languageExpanded = false);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          // Scroll anchor for real-UI automation (the collapsed
                          // selector row; the harness scrolls this keyed box into
                          // the viewport before tapping to expand the list).
                          key: UiKeys.settingsLanguageSelector,
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(
                              () => _languageExpanded = !_languageExpanded,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppThemeConfig.inputBorderRadius,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.md,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: outlineVariant),
                                borderRadius: BorderRadius.circular(
                                  AppThemeConfig.inputBorderRadius,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      selectedLabel,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                  Icon(
                                    _languageExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: Theme.of(context).iconTheme.color,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_languageExpanded) ...[
                          AppSpacing.verticalSm,
                          ...languages.map((lang) {
                            final isSelected = _isLocaleEqual(
                              selectedLocale!,
                              lang.locale,
                            );
                            // Stable per-option key for real-UI automation:
                            // 'settings_language_option_<code>' where <code> is
                            // the persisted `${languageCode}[_${scriptCode}]`
                            // form (matches Prefs._localeToString) — e.g.
                            // settings_language_option_en / ..._zh_Hans. The
                            // option label Text isn't surfaced by flutter_skill's
                            // interactiveStructured, so the harness taps this key.
                            final optionCode = lang.locale.scriptCode != null
                                ? '${lang.locale.languageCode}_${lang.locale.scriptCode}'
                                : lang.locale.languageCode;
                            return Material(
                              key: Key('settings_language_option_$optionCode'),
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => selectLocale(lang.locale),
                                borderRadius: BorderRadius.circular(
                                  AppThemeConfig.inputBorderRadius,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                    horizontal: AppSpacing.md,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        size: 20,
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(context).iconTheme.color,
                                      ),
                                      AppSpacing.horizontalMd,
                                      Text(
                                        lang.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : null,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        ], // end Appearance view group (theme + language)
        // Single separator between the two groups — only when BOTH render
        // (view == all, i.e. desktop). Keeping it here (rather than as the
        // leading child of the general group) avoids a doubled top gap on the
        // mobile "General" sub-page, where showAppearance is false.
        if (showAppearance && showGeneral) AppSpacing.verticalMd,
        if (showGeneral) ...[
        if (widget.toxId != null && widget.toxId!.isNotEmpty) ...[
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: outlineVariant),
              borderRadius: BorderRadius.circular(
                AppThemeConfig.cardBorderRadius,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              // Match the title/description switch-row pattern used by the
              // three sibling switches on the main settings page (auto-login,
              // auto-accept friends, auto-accept group invites). Previously
              // this row used a bare SwitchListTile which rendered subtly
              // differently (denser, different padding, different hover).
              child: HoverableSettingsRow(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.notificationSound,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          AppSpacing.verticalXs,
                          Text(
                            AppLocalizations.of(context)!.notificationSoundDesc,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _secondaryTextColor(context)),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      key: UiKeys.settingsNotificationSoundSwitch,
                      value: _notificationSoundEnabled,
                      onChanged: _setNotificationSoundEnabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.verticalMd,
        ],
        // Downloads Directory
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: outlineVariant),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: AppLocalizations.of(context)!.downloadsDirectory,
                ),
                AppSpacing.verticalSm,
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _downloadsDirectoryController,
                        readOnly: true,
                        textAlignVertical: TextAlignVertical.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontFamily: 'monospace',
                          color: _primaryTextColor(context),
                        ),
                        decoration: InputDecoration(
                          // hintText removed: the same string is shown as the
                          // helper Text below the field, so the hint was just
                          // duplicate copy fighting for the user's eye.
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppThemeConfig.inputBorderRadius,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                    ),
                    // Mobile platforms can't usefully pick a directory through
                    // FilePicker (Android returns content:// URIs we can't
                    // write through dart:io; iOS lacks a directory picker
                    // altogether). The field above still shows the default
                    // app-sandbox Downloads directory so the user knows
                    // where files land.
                    if (_supportsDirectoryPicker) ...[
                      AppSpacing.horizontalSm,
                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(
                          AppLocalizations.of(
                            context,
                          )!.selectDownloadsDirectory,
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppThemeConfig.buttonBorderRadius,
                            ),
                          ),
                        ),
                        onPressed: _selectDownloadsDirectory,
                      ),
                    ],
                  ],
                ),
                AppSpacing.verticalXs,
                Text(
                  AppLocalizations.of(context)!.downloadsDirectoryDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppSpacing.verticalMd,
        // Auto Download Size Limit
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: outlineVariant),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: AppLocalizations.of(context)!.autoDownloadSizeLimit,
                ),
                AppSpacing.verticalSm,
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: UiKeys.settingsDownloadLimitField,
                        controller: _sizeLimitController,
                        keyboardType: TextInputType.number,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(
                            context,
                          )!.sizeLimitInMB,
                          // Hint reflects the platform default — 5 MB on
                          // mobile (cellular-friendly), 30 MB on desktop.
                          hintText: (Platform.isAndroid || Platform.isIOS)
                              ? '5'
                              : '30',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppThemeConfig.inputBorderRadius,
                            ),
                          ),
                          suffixText: 'MB',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        onSubmitted: (_) => _saveAutoDownloadSizeLimit(),
                      ),
                    ),
                    AppSpacing.horizontalSm,
                    ElevatedButton.icon(
                      key: UiKeys.settingsDownloadLimitSaveButton,
                      icon: const Icon(Icons.save, size: 18),
                      label: Text(AppLocalizations.of(context)!.save),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppThemeConfig.buttonBorderRadius,
                          ),
                        ),
                      ),
                      onPressed: _saveAutoDownloadSizeLimit,
                    ),
                  ],
                ),
                AppSpacing.verticalXs,
                Text(
                  AppLocalizations.of(context)!.autoDownloadSizeLimitDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        ], // end General view group (notification / downloads / auto-download)
      ],
    );
  }
}
