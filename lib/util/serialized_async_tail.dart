typedef SerializedTailErrorLogger =
    void Function(Object error, StackTrace stackTrace);

class SerializedAsyncTail {
  SerializedAsyncTail({required SerializedTailErrorLogger logError})
    : _logError = logError;

  final SerializedTailErrorLogger _logError;
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object error, StackTrace stackTrace) {
      _logError(error, stackTrace);
    });
    return next;
  }
}
