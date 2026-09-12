import 'prefs.dart';

/// Guards the durable active-account mirror while a session is initialized and
/// booted. Initialization may publish the candidate account before the runtime
/// is ready; callers commit only after full boot succeeds.
final class AccountActivationTransaction {
  AccountActivationTransaction._({
    required String? previousToxId,
    required String? previousNickname,
    required String? previousStatusMessage,
    required String? previousAvatarPath,
  }) : _previousToxId = previousToxId,
       _previousNickname = previousNickname,
       _previousStatusMessage = previousStatusMessage,
       _previousAvatarPath = previousAvatarPath;

  final String? _previousToxId;
  final String? _previousNickname;
  final String? _previousStatusMessage;
  final String? _previousAvatarPath;
  bool _committed = false;
  bool _rolledBack = false;

  static Future<AccountActivationTransaction> begin() async {
    final snapshot = await Future.wait<String?>([
      Prefs.getCurrentAccountToxId(),
      Prefs.getNickname(),
      Prefs.getStatusMessage(),
      Prefs.getAvatarPath(),
    ]);
    return AccountActivationTransaction._(
      previousToxId: snapshot[0],
      previousNickname: snapshot[1],
      previousStatusMessage: snapshot[2],
      previousAvatarPath: snapshot[3],
    );
  }

  void commit() {
    _committed = true;
  }

  Future<void> rollback() async {
    if (_committed || _rolledBack) return;
    await Prefs.setCurrentAccountToxId(_previousToxId);
    await Prefs.setNickname(_previousNickname ?? '');
    await Prefs.setStatusMessage(_previousStatusMessage ?? '');
    await Prefs.setAvatarPath(_previousAvatarPath);
    _rolledBack = true;
  }
}
