import 'dart:io';
import 'package:toxee/bootstrap/desktop_session_owner.dart';

Future<void> main(List<String> args) async {
  final owner = await DesktopSessionOwner.claim(
    args.single,
    onActivate: () async => stdout.writeln('activated'),
  );
  stdout.writeln(owner == null ? 'yielded' : 'owner');
  if (owner == null) return;
  await stdin.first;
  await owner.close();
}
