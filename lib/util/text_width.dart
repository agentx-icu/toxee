/// Display-width helpers for length-limited text fields.
///
/// Lives here, not in `account_service.dart` where it was originally written:
/// it has nothing to do with the account lifecycle and is used only by the
/// register/profile form validators.

/// Calculate text length where Chinese characters count as 1, and
/// letters/numbers/other characters count as 0.5.
double calculateTextLength(String text) {
  double length = 0;
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (char.codeUnitAt(0) >= 0x4E00 && char.codeUnitAt(0) <= 0x9FFF) {
      length += 1.0;
    } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
      length += 0.5;
    } else {
      length += 0.5;
    }
  }
  return length;
}
