import 'dart:async';

// Minimal event bus to mimic TencentCloudChat.instance.eventBusInstance
class FakeEventBus {
  final Map<String, StreamController<dynamic>> _topicToCtrl = {};

  Stream<T> on<T>(String topic) {
    return _topicToCtrl.putIfAbsent(topic, () => StreamController.broadcast())
        .stream.where((e) => e is T).cast<T>();
  }

  void emit(String topic, dynamic event) {
    _topicToCtrl.putIfAbsent(topic, () => StreamController.broadcast());
    if (_topicToCtrl[topic]?.isClosed == false) _topicToCtrl[topic]!.add(event);
  }

  void dispose() {
    for (final c in _topicToCtrl.values) {
      c.close();
    }
    _topicToCtrl.clear();
  }
}


