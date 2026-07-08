import 'package:flutter/material.dart';

import '../widgets/safe_dialog_pop.dart';
import '../../util/app_spacing.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';
import '../testing/ui_keys.dart';

class IrcChannelDialog extends StatefulWidget {
  const IrcChannelDialog({super.key});

  @override
  State<IrcChannelDialog> createState() => _IrcChannelDialogState();
}

class _IrcChannelDialogState extends State<IrcChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _channelController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _channelController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  String? _validateChannel(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      final appL10n = AppLocalizations.of(context);
      return appL10n?.enterIrcChannel ?? 'Please enter IRC channel name';
    }
    // IRC channel names typically start with # or &
    if (!trimmed.startsWith('#') && !trimmed.startsWith('&')) {
      final appL10n = AppLocalizations.of(context);
      return appL10n?.invalidIrcChannel ?? 'IRC channel must start with # or &';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final fieldLabelStyle = theme.textTheme.labelLarge?.copyWith(
          color: colorTheme.primaryTextColor,
          fontWeight: FontWeight.w600,
        );
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 4, color: colorTheme.primaryColor),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appL10n?.joinIrcChannel ?? 'Join IRC Channel',
                          style: theme.textTheme.titleLarge,
                        ),
                        AppSpacing.verticalLg,
                        Text(
                          appL10n?.ircChannelName ?? 'IRC Channel Name',
                          style: fieldLabelStyle,
                        ),
                        AppSpacing.verticalSm,
                        TextFormField(
                          key: UiKeys.ircChannelDialogChannelField,
                          controller: _channelController,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: appL10n?.ircChannelHint ?? '#channel',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppThemeConfig.inputBorderRadius,
                              ),
                            ),
                            prefixText:
                                _channelController.text.isEmpty ||
                                    _channelController.text.startsWith('#') ||
                                    _channelController.text.startsWith('&')
                                ? null
                                : '#',
                          ),
                          validator: _validateChannel,
                          autofocus: true,
                          onChanged: (value) {
                            setState(() {});
                          },
                        ),
                        AppSpacing.verticalLg,
                        Text(
                          appL10n?.ircChannelPassword ??
                              'Channel Password (optional)',
                          style: fieldLabelStyle,
                        ),
                        AppSpacing.verticalSm,
                        TextFormField(
                          key: UiKeys.ircChannelDialogPasswordField,
                          controller: _passwordController,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText:
                                appL10n?.ircChannelPasswordHint ??
                                'Leave empty if no password',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppThemeConfig.inputBorderRadius,
                              ),
                            ),
                            suffixIcon: IconButton(
                              key: UiKeys
                                  .ircChannelDialogPasswordVisibilityToggle,
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          enableSuggestions: false,
                          autocorrect: false,
                        ),
                        AppSpacing.verticalLg,
                        Text(
                          appL10n?.ircCustomNickname ??
                              'Custom IRC Nickname (optional)',
                          style: fieldLabelStyle,
                        ),
                        AppSpacing.verticalSm,
                        TextFormField(
                          key: UiKeys.ircChannelDialogNicknameField,
                          controller: _nicknameController,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText:
                                appL10n?.ircCustomNicknameHint ??
                                'Leave empty to use auto-generated nickname',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppThemeConfig.inputBorderRadius,
                              ),
                            ),
                          ),
                        ),
                        AppSpacing.verticalLg,
                        Text(
                          appL10n?.ircChannelDesc ??
                              'Enter the IRC channel name (e.g., #channel). A Tox group will be created for this channel.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorTheme.secondaryTextColor,
                          ),
                        ),
                        AppSpacing.verticalXl,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              key: UiKeys.ircChannelDialogCancelButton,
                              onPressed: () => popDialogIfCurrent(context),
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppThemeConfig.buttonBorderRadius,
                                  ),
                                ),
                              ),
                              child: Text(appL10n?.cancel ?? 'Cancel'),
                            ),
                            AppSpacing.horizontalSm,
                            ElevatedButton(
                              key: UiKeys.ircChannelDialogJoinButton,
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  // _validateChannel already enforces a leading
                                  // `#` or `&` — no normalization needed here.
                                  final channel = _channelController.text
                                      .trim();
                                  final password = _passwordController.text
                                      .trim();
                                  final nickname = _nicknameController.text
                                      .trim();
                                  popDialogIfCurrent(context, (
                                    channel: channel,
                                    password: password.isEmpty
                                        ? null
                                        : password,
                                    nickname: nickname.isEmpty
                                        ? null
                                        : nickname,
                                  ));
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorTheme.primaryColor,
                                foregroundColor: colorTheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppThemeConfig.buttonBorderRadius,
                                  ),
                                ),
                              ),
                              child: Text(appL10n?.join ?? 'Join'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
