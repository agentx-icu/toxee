import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';

void main() {
  testWidgets(
    'ar_rtl_smoke: Arabic is supported and resolves ambient Directionality to RTL',
    (tester) async {
      const probeKey = ValueKey('ar_rtl_smoke_probe');

      expect(AppLocalizations.supportedLocales, contains(const Locale('ar')));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            key: probeKey,
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Text('locale:${l10n?.localeName}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(probeKey));
      expect(AppLocalizations.of(context)?.localeName, 'ar');
      expect(Directionality.of(context), TextDirection.rtl);
    },
  );
}
