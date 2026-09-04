import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/widgets/modal_barrier_mirror.dart';

/// Chrome drawn outside the Navigator (the desktop caption-button strip) must
/// dim with the app's modal barrier and clear again when the dialog closes.
void main() {
  testWidgets('mirror paints the dialog barrier colour and clears on pop', (
    tester,
  ) async {
    final observer = ModalBarrierObserver();
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(child: child!),
            Positioned(
              top: 0,
              right: 0,
              child: ModalBarrierMirror(
                observer: observer,
                child: const SizedBox(
                  key: ValueKey('caption_strip'),
                  width: 138,
                  height: 40,
                ),
              ),
            ),
          ],
        ),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    final mirror = find.byKey(const ValueKey('desktop_caption_barrier_mirror'));
    expect(mirror, findsNothing);

    final dialog = showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(title: Text('modal')),
    );
    await tester.pumpAndSettle();
    expect(mirror, findsOneWidget);
    final box = tester.widget<ColoredBox>(mirror);
    expect(box.color, Colors.black54, reason: 'dialog barrier colour');
    expect(tester.getSize(mirror), const Size(138, 40));

    Navigator.of(pageContext, rootNavigator: true).pop();
    await dialog;
    // Mid reverse transition (dialog: 150 ms): still painted, partly faded,
    // exactly like the Navigator's own barrier.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(mirror, findsOneWidget, reason: 'must fade with the barrier');
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: mirror, matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, greaterThan(0.0));
    expect(fade.opacity.value, lessThan(1.0));
    await tester.pumpAndSettle();
    expect(mirror, findsNothing);
  });
}
