import AVFoundation
import AudioToolbox
import Flutter
import UIKit

final class CallAudioChannel: NSObject, FlutterStreamHandler {
  static let shared = CallAudioChannel()

  private let session = AVAudioSession.sharedInstance()
  private var eventSink: FlutterEventSink?
  private var preferredRouteId: String?
  private var hasRegisteredNotifications = false
  private var isSessionActive = false
  private let ringer = IncomingRinger()

  private override init() {
    super.init()
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "toxee/call_audio",
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler(handleMethodCall)

    let eventChannel = FlutterEventChannel(
      name: "toxee/call_audio_events",
      binaryMessenger: binaryMessenger
    )
    eventChannel.setStreamHandler(self)

    registerNotificationsIfNeeded()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emit(type: "state")
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "activateSession":
      let args = call.arguments as? [String: Any]
      let preferSpeaker = args?["preferSpeaker"] as? Bool ?? false
      activateSession(preferSpeaker: preferSpeaker)
      result(makeState())
    case "deactivateSession":
      deactivateSession()
      result(makeState())
    case "getState":
      result(makeState())
    case "setRoute":
      let args = call.arguments as? [String: Any]
      let routeId = args?["routeId"] as? String
      setRoute(routeId)
      result(makeState())
    case "playIncomingRingtone":
      let path = (call.arguments as? [String: Any])?["path"] as? String
      result(path.map { ringer.start(path: $0) } ?? false)
    case "stopIncomingRingtone":
      ringer.stop()
      result(nil)
    case "setProximityMonitoring":
      let args = call.arguments as? [String: Any]
      setProximityMonitoring(args?["enabled"] as? Bool ?? false)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func registerNotificationsIfNeeded() {
    guard !hasRegisteredNotifications else {
      return
    }
    hasRegisteredNotifications = true

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: session
    )
  }

  private func activateSession(preferSpeaker: Bool) {
    do {
      var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
      if preferSpeaker {
        options.insert(.defaultToSpeaker)
      }
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
      try session.setActive(true, options: [])
      isSessionActive = true
      applyPreferredRoute(defaultToSpeaker: preferSpeaker)
    } catch {
      NSLog("[CallAudioChannel] Failed to activate audio session: \(error)")
    }
  }

  private func deactivateSession() {
    setProximityMonitoring(false)
    // The route preference is local intent, not OS state, so clearing it is
    // always safe.
    preferredRouteId = nil
    do {
      try session.overrideOutputAudioPort(.none)
      try session.setPreferredInput(nil)
      try session.setActive(false, options: [.notifyOthersOnDeactivation])
      // Only record the session as inactive once the OS actually deactivated
      // it. Previously a `defer` cleared this flag unconditionally, so a thrown
      // setActive(false) (e.g. another app holding the route) left the app
      // believing the session was torn down while it was still active.
      isSessionActive = false
    } catch {
      NSLog("[CallAudioChannel] Failed to deactivate audio session: \(error)")
    }
  }

  private func setRoute(_ routeId: String?) {
    preferredRouteId = routeId
    applyPreferredRoute(defaultToSpeaker: false)
    emit(type: "routeChanged")
  }

  private func setProximityMonitoring(_ enabled: Bool) {
    UIDevice.current.isProximityMonitoringEnabled =
      enabled && UIDevice.current.userInterfaceIdiom == .phone
  }

  private func applyPreferredRoute(defaultToSpeaker: Bool) {
    do {
      let routeId = preferredRouteId ?? (defaultToSpeaker ? "speaker" : "earpiece")
      switch routeId {
      case "speaker":
        try session.setPreferredInput(nil)
        try session.overrideOutputAudioPort(.speaker)
      case "earpiece":
        try session.overrideOutputAudioPort(.none)
        if let builtInMic = session.availableInputs?.first(where: {
          $0.portType == .builtInMic
        }) {
          try session.setPreferredInput(builtInMic)
        } else {
          try session.setPreferredInput(nil)
        }
      case "wired":
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(nil)
      default:
        if routeId.hasPrefix("input:"),
           let input = session.availableInputs?.first(where: {
             "input:\($0.uid)" == routeId
           }) {
          try session.overrideOutputAudioPort(.none)
          try session.setPreferredInput(input)
        } else if defaultToSpeaker {
          try session.setPreferredInput(nil)
          try session.overrideOutputAudioPort(.speaker)
        } else {
          try session.overrideOutputAudioPort(.none)
          try session.setPreferredInput(nil)
        }
      }
    } catch {
      NSLog("[CallAudioChannel] Failed to apply preferred route: \(error)")
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    emit(type: "routeChanged")
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: rawType)
    else {
      emit(type: "state")
      return
    }

    switch type {
    case .began:
      emit(type: "interruptionBegan")
    case .ended:
      var shouldResume = false
      if let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
        shouldResume = options.contains(.shouldResume)
      }
      emit(type: "interruptionEnded", shouldResume: shouldResume)
    @unknown default:
      emit(type: "state")
    }
  }

  private func emit(type: String, shouldResume: Bool? = nil) {
    // AVAudioSession route-change / interruption notifications may be posted
    // on a secondary thread, but a Flutter event sink must be called on the
    // platform (main) thread. Build and send the event there.
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.emit(type: type, shouldResume: shouldResume)
      }
      return
    }
    guard let eventSink else {
      return
    }
    var event: [String: Any] = [
      "type": type,
      "state": makeState(),
    ]
    if let shouldResume {
      event["shouldResume"] = shouldResume
    }
    eventSink(event)
  }

  private func makeState() -> [String: Any] {
    let currentRouteId = currentRouteIdentifier()
    return [
      "sessionActive": isSessionActive,
      "selectedRouteId": currentRouteId as Any,
      "routes": availableRoutes(currentRouteId: currentRouteId),
    ]
  }

  private func availableRoutes(currentRouteId: String?) -> [[String: Any]] {
    var routes: [[String: Any]] = []

    if UIDevice.current.userInterfaceIdiom == .phone {
      routes.append(route(
        id: "earpiece",
        kind: "earpiece",
        label: "Earpiece",
        selected: currentRouteId == "earpiece"
      ))
    }

    routes.append(route(
      id: "speaker",
      kind: "speaker",
      label: "Speaker",
      selected: currentRouteId == "speaker"
    ))

    let availableInputs = session.availableInputs ?? []
    for input in availableInputs {
      let portType = input.portType.rawValue
      if bluetoothPortTypes.contains(portType) {
        routes.append(route(
          id: "input:\(input.uid)",
          kind: "bluetooth",
          label: input.portName,
          selected: currentRouteId == "input:\(input.uid)"
        ))
      } else if wiredPortTypes.contains(portType) {
        routes.append(route(
          id: "input:\(input.uid)",
          kind: "wired",
          label: input.portName,
          selected: currentRouteId == "input:\(input.uid)"
        ))
      }
    }

    if currentRouteId == "wired" {
      let currentOutputName = session.currentRoute.outputs.first?.portName ?? "Wired"
      routes.append(route(
        id: "wired",
        kind: "wired",
        label: currentOutputName,
        selected: true
      ))
    }

    return routes
  }

  private func route(
    id: String,
    kind: String,
    label: String,
    selected: Bool
  ) -> [String: Any] {
    return [
      "id": id,
      "kind": kind,
      "label": label,
      "selected": selected,
    ]
  }

  private func currentRouteIdentifier() -> String? {
    guard let output = session.currentRoute.outputs.first else {
      return nil
    }

    let outputType = output.portType.rawValue
    if output.portType == .builtInSpeaker {
      return "speaker"
    }
    if output.portType == .builtInReceiver {
      return "earpiece"
    }
    if bluetoothPortTypes.contains(outputType),
       let input = session.currentRoute.inputs.first {
      return "input:\(input.uid)"
    }
    if wiredOutputTypes.contains(outputType) {
      if let input = session.currentRoute.inputs.first {
        return "input:\(input.uid)"
      }
      return "wired"
    }

    return UIDevice.current.userInterfaceIdiom == .phone ? "earpiece" : "speaker"
  }

  private var bluetoothPortTypes: Set<String> {
    [
      AVAudioSession.Port.bluetoothHFP.rawValue,
      AVAudioSession.Port.bluetoothA2DP.rawValue,
      AVAudioSession.Port.bluetoothLE.rawValue,
    ]
  }

  private var wiredPortTypes: Set<String> {
    [
      AVAudioSession.Port.headsetMic.rawValue,
      AVAudioSession.Port.usbAudio.rawValue,
    ]
  }

  private var wiredOutputTypes: Set<String> {
    [
      AVAudioSession.Port.headphones.rawValue,
      AVAudioSession.Port.lineOut.rawValue,
      AVAudioSession.Port.usbAudio.rawValue,
    ]
  }
}

/// The in-app ringer used while the app is on screen when an incoming call
/// could not be reported to CallKit (checklist A9). A system alert sound,
/// looped: it honours the silent switch and the ringer volume, and — unlike
/// an audioplayers ringtone — never touches the app-wide AVAudioSession,
/// whose category the call itself owns. Whether it also vibrates depends on
/// the device settings and the session category (not under playAndRecord).
/// It cannot keep a backgrounded app alive; Dart moves to its audio loop
/// when the app leaves the screen.
final class IncomingRinger {
  private var soundID: SystemSoundID = 0
  private var generation = 0

  /// Starts ringing [path] (a short WAV); false if iOS cannot load it.
  func start(path: String) -> Bool {
    stop()
    var id: SystemSoundID = 0
    let status = AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &id)
    guard status == kAudioServicesNoError else { return false }
    soundID = id
    generation += 1
    ring(generation)
    return true
  }

  func stop() {
    generation += 1 // a completion still in flight rings no more
    if soundID != 0 {
      AudioServicesDisposeSystemSoundID(soundID)
      soundID = 0
    }
  }

  private func ring(_ current: Int) {
    guard current == generation, soundID != 0 else { return }
    AudioServicesPlayAlertSoundWithCompletion(soundID) { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        self?.ring(current)
      }
    }
  }
}
