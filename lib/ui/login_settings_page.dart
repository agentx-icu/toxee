import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

import '../i18n/app_localizations.dart';
import '../util/app_spacing.dart';
import '../util/responsive_layout.dart';
import 'settings/bootstrap_settings_section.dart';
import 'settings/global_settings_section.dart';

class LoginSettingsPage extends StatefulWidget {
  const LoginSettingsPage({super.key});

  @override
  State<LoginSettingsPage> createState() => _LoginSettingsPageState();
}

class _LoginSettingsPageState extends State<LoginSettingsPage> {
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final horizontal = ResponsiveLayout.responsiveHorizontalPadding(context);
    return AppBar(
      leadingWidth: 56 + horizontal,
      leading: Padding(
        padding: EdgeInsets.only(left: horizontal),
        child: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      title: Text(
        AppLocalizations.of(context)!.settings,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final tL10n = TencentCloudChatLocalizations.of(context);
        if (tL10n == null) {
          return Scaffold(
            appBar: _buildAppBar(context),
            body: const SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return Scaffold(
          appBar: _buildAppBar(context),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: ResponsiveLayout.responsivePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Global settings (appearance, language, downloads, auto-download;
                  // no notification sound when not logged in)
                  GlobalSettingsSection(
                    colorTheme: colorTheme,
                    toxId: null,
                  ),
                  AppSpacing.verticalLg,
                  // Bootstrap (shared section, no service on login page)
                  BootstrapSettingsSection(
                    service: null,
                    colorTheme: colorTheme,
                  ),
                  AppSpacing.verticalLg,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
