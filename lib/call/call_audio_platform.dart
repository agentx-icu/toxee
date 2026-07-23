import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum CallAudioRouteKind { earpiece, speaker, wired, bluetooth, unknown }

bool shouldEnableCallProximity({
  required bool isActiveMediaCall,
  required bool isVideoCall,
  required CallAudioRouteKind? selectedRouteKind,
}) {
  return isActiveMediaCall &&
      !isVideoCall &&
      selectedRouteKind == CallAudioRouteKind.earpiece;
}

class CallAudioRoute {
  final String id;
  final CallAudioRouteKind kind;
  final String label;
  final bool selected;

  const CallAudioRoute({
    required this.id,
    required this.kind,
    required this.label,
    required this.selected,
  });

  factory CallAudioRoute.fromMap(Map<dynamic, dynamic> map) {
    return CallAudioRoute(
      id: map['id'] as String? ?? '',
      kind: _kindFromString(map['kind'] as String?),
      label: map['label'] as String? ?? '',
      selected: map['selected'] as bool? ?? false,
    );
  }

  static CallAudioRouteKind _kindFromString(String? value) {
    switch (value) {
      case 'earpiece':
        return CallAudioRouteKind.earpiece;
      case 'speaker':
        return CallAudioRouteKind.speaker;
      case 'wired':
        return CallAudioRouteKind.wired;
      case 'bluetooth':
        return CallAudioRouteKind.bluetooth;
      default:
        return CallAudioRouteKind.unknown;
    }
  }
}

class CallAudioState {
  final bool sessionActive;
  final String? selectedRouteId;
  final List<CallAudioRoute> routes;

  const CallAudioState({
    this.sessionActive = false,
    this.selectedRouteId,
    this.routes = const <CallAudioRoute>[],
  });

  factory CallAudioState.fromMap(Map<dynamic, dynamic> map) {
    final routeMaps = (map['routes'] as List<dynamic>? ?? const <dynamic>[]);
    final routes = routeMaps
        .map((route) => CallAudioRoute.fromMap(route as Map<dynamic, dynamic>))
        .toList();

    return CallAudioState(
      sessionActive: map['sessionActive'] as bool? ?? false,
      selectedRouteId: map['selectedRouteId'] as String?,
      routes: routes,
    );
  }

  CallAudioRoute? get selectedRoute {
    for (final route in routes) {
      if (route.selected || route.id == selectedRouteId) {
        return route;
      }
    }
    return null;
  }

  bool get canSelectRoutes => routes.length > 1;
}

enum CallAudioEventKind {
  state,
  routeChanged,
  interruptionBegan,
  interruptionEnded,
  noisy,
  focusLost,
  focusDucked,
  focusGained,
  unknown,
}

class CallAudioEvent {
  final CallAudioEventKind kind;
  final CallAudioState? state;
  final bool shouldResume;

  const CallAudioEvent({
    required this.kind,
    this.state,
    this.shouldResume = true,
  });

  factory CallAudioEvent.fromMap(Map<dynamic, dynamic> map) {
    final stateMap = map['state'];
    return CallAudioEvent(
      kind: _kindFromString(map['type'] as String?),
      state: stateMap is Map ? CallAudioState.fromMap(stateMap) : null,
      shouldResume: map['shouldResume'] as bool? ?? true,
    );
  }

  static CallAudioEventKind _kindFromString(String? value) {
    switch (value) {
      case 'state':
        return CallAudioEventKind.state;
      case 'routeChanged':
        return CallAudioEventKind.routeChanged;
      case 'interruptionBegan':
        return CallAudioEventKind.interruptionBegan;
      case 'interruptionEnded':
        return CallAudioEventKind.interruptionEnded;
      case 'noisy':
        return CallAudioEventKind.noisy;
      case 'focusLost':
        return CallAudioEventKind.focusLost;
      case 'focusDucked':
        return CallAudioEventKind.focusDucked;
      case 'focusGained':
        return CallAudioEventKind.focusGained;
      default:
        return CallAudioEventKind.unknown;
    }
  }
}

bool shouldResumeInterruptedCallMedia({
  required CallAudioEvent event,
  required bool hasActiveMediaCall,
}) {
  if (!hasActiveMediaCall) return false;
  return switch (event.kind) {
    CallAudioEventKind.interruptionEnded => event.shouldResume,
    CallAudioEventKind.focusGained => true,
    _ => false,
  };
}

class CallAudioPlatform {
  CallAudioPlatform({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel = methodChannel ?? const MethodChannel('toxee/call_audio'),
      _eventChannel =
          eventChannel ?? const EventChannel('toxee/call_audio_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final ValueNotifier<CallAudioState> state = ValueNotifier(
    const CallAudioState(),
  );
  final StreamController<CallAudioEvent> _events =
      StreamController<CallAudioEvent>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;

  Stream<CallAudioEvent> get events => _events.stream;

  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() async {
    if (!isSupported || _eventSubscription != null) {
      return;
    }
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleNativeEvent,
      );
      await refreshState();
    } on MissingPluginException {
      // Native bridge is unavailable in non-mobile test/runtime environments.
    }
  }

  Future<void> activateSession({required bool preferSpeaker}) async {
    await _invokeAndUpdateState('activateSession', <String, dynamic>{
      'preferSpeaker': preferSpeaker,
    });
  }

  Future<void> deactivateSession() async {
    await _invokeAndUpdateState('deactivateSession');
  }

  Future<void> refreshState() async {
    await _invokeAndUpdateState('getState');
  }

  Future<void> selectRoute(String routeId) async {
    await _invokeAndUpdateState('setRoute', <String, dynamic>{
      'routeId': routeId,
    });
  }

  Future<void> setProximityMonitoring(bool enabled) async {
    if (!isSupported) return;
    try {
      await _methodChannel.invokeMethod<void>(
        'setProximityMonitoring',
        <String, dynamic>{'enabled': enabled},
      );
    } on MissingPluginException {
      // Native bridge is unavailable in non-mobile test/runtime environments.
    }
  }

  Future<void> _invokeAndUpdateState(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!isSupported) {
      return;
    }
    try {
      final result = await _methodChannel.invokeMethod<dynamic>(
        method,
        arguments,
      );
      if (result is Map) {
        state.value = CallAudioState.fromMap(result);
      }
    } on MissingPluginException {
      // Ignore in unsupported environments.
    }
  }

  void _handleNativeEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    final parsed = CallAudioEvent.fromMap(event);
    if (parsed.state != null) {
      state.value = parsed.state!;
    }
    _events.add(parsed);
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _events.close();
    state.dispose();
  }
}
