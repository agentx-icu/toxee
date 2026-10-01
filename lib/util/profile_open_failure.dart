// Typed failure for "the verifier accepted this password but the profile on
// disk did not open with it". Lets the login surfaces say something more
// useful than "login failed".

/// The native init refused the profile under a password the verifier had
/// accepted. NOT asserted as a wrong password: toxcore reports a decrypt
/// failure the same way for a damaged file. [passwordChangeInFlight] is true
/// when a journaled password change was interrupted for this account — then
/// the file is most likely under the OTHER password (before or after the
/// change) and the user should try that one.
class ProfileUnopenableWithPasswordException implements Exception {
  const ProfileUnopenableWithPasswordException({
    required this.passwordChangeInFlight,
  });

  final bool passwordChangeInFlight;

  @override
  String toString() =>
      'ProfileUnopenableWithPasswordException: the profile did not open with '
      'the verified password (passwordChangeInFlight=$passwordChangeInFlight)';
}
