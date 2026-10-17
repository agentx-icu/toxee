import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_location_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/testing/nearby_ui_keys.dart';
import 'package:toxee/ui/widgets/location_message_bubble.dart';

/// The SDK's message models touch the native binding when constructed; the
/// CI test job stages libtim2tox_ffi, a developer machine may not.
bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

V2TimMessage _message({double? lat, double? lon, String desc = ''}) {
  final m = V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_LOCATION);
  if (lat != null && lon != null) {
    m.locationElem = V2TimLocationElem(desc: desc, latitude: lat, longitude: lon);
  }
  return m;
}

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: SizedBox(width: 320, child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  testWidgets('renders coordinates, label and both actions at phone width', (tester) async {
    await tester.pumpWidget(_host(LocationMessageBubble(
      message: _message(lat: 39.9042, lon: 116.4074, desc: 'Tiananmen'),
      launcher: (_) async => true,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Tiananmen'), findsOneWidget);
    expect(find.text('39.90420, 116.40740'), findsOneWidget);
    expect(find.byKey(NearbyUiKeys.locationBubbleOpenMaps), findsOneWidget);
    expect(find.text('Copy coordinates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: skipReason != null);

  testWidgets('Open in Maps launches the platform URI and reports a failure', (tester) async {
    Uri? launched;
    await tester.pumpWidget(_host(LocationMessageBubble(
      message: _message(lat: 1.5, lon: 2.5),
      launcher: (u) async {
        launched = u;
        return false;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(NearbyUiKeys.locationBubbleOpenMaps));
    await tester.pumpAndSettle();
    expect(launched, isNotNull);
    expect(launched.toString(), contains('1.500000'));
    expect(find.text('No maps app could open this location.'), findsOneWidget);
  }, skip: skipReason != null);

  testWidgets('falls back to a label when the element has no coordinates', (tester) async {
    await tester.pumpWidget(_host(LocationMessageBubble(message: _message())));
    await tester.pumpAndSettle();
    expect(find.text('[Location]'), findsOneWidget);
  }, skip: skipReason != null);

  test('maps URIs per platform', () {
    // Linux/Windows (the test host) get the OSM link; the mobile/macOS
    // schemes are string contracts checked by inspection of mapsUri.
    final uri = LocationMessageBubble.mapsUri(39.9042, 116.4074);
    expect(uri.toString(), anyOf(contains('openstreetmap.org'), startsWith('geo:'), startsWith('maps://')));
  });
}
