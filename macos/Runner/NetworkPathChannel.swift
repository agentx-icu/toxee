import Cocoa
import FlutterMacOS
import Network
import Darwin

final class ToxeeNetworkPathChannel: NSObject, FlutterStreamHandler {
  private let queue = DispatchQueue(label: "toxee.network_path")
  private var monitor: NWPathMonitor?
  private var sink: FlutterEventSink?
  private var lastSent: (Bool, String?)?
  private var wakeObserver: NSObjectProtocol?
  private var wakeGeneration = 0

  func register(binaryMessenger: FlutterBinaryMessenger) {
    FlutterEventChannel(name: "toxee/network_path", binaryMessenger: binaryMessenger)
      .setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    lastSent = nil
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      let available = path.status == .satisfied
      let identity = available ? ToxeeNetworkPathChannel.identity(of: path) : nil
      DispatchQueue.main.async { self?.emit(available: available, identity: identity) }
    }
    monitor.start(queue: queue)
    self.monitor = monitor
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
        guard let self, let path = self.monitor?.currentPath else { return }
        self.wakeGeneration += 1
        self.emit(available: path.status == .satisfied,
                  identity: Self.identity(of: path))
      }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    wakeObserver = nil
    monitor?.cancel()
    monitor = nil
    sink = nil
    return nil
  }

  private func emit(available: Bool, identity: String?) {
    guard let sink else { return }
    let identity = identity.map { $0 + "|wake=\(wakeGeneration)" }
    if let last = lastSent, last.0 == available, last.1 == identity { return }
    lastSent = (available, identity)
    sink(["available": available, "identity": identity.map { $0 as Any } ?? NSNull()])
  }

  /// What the default path is USING: the interface types it routes over
  /// (`usesInterfaceType`, not merely the available list), the interfaces of
  /// those types with their current addresses, and the path's gateways — so a
  /// Wi-Fi <-> cellular handover, a new address, or a new router all change it.
  private static func identity(of path: NWPath) -> String {
    let kinds: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .other]
    let used = kinds.filter { path.usesInterfaceType($0) }
    let interfaces = path.availableInterfaces
      .filter { iface in used.contains(iface.type) }
      .map { "\($0.name)=\(addresses(of: $0.name).joined(separator: ","))" }
      .sorted()
    let gateways = path.gateways.map { "\($0)" }.sorted()
    return "\(used.map { "\($0)" }.joined(separator: "+"))|"
      + "\(interfaces.joined(separator: ";"))|\(gateways.joined(separator: ","))"
  }

  /// Sorted numeric addresses (IPv4 + IPv6) currently on [name].
  private static func addresses(of name: String) -> [String] {
    var result: [String] = []
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return result }
    defer { freeifaddrs(head) }
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = cursor {
      defer { cursor = entry.pointee.ifa_next }
      guard String(cString: entry.pointee.ifa_name) == name,
        let addr = entry.pointee.ifa_addr
      else { continue }
      let family = Int32(addr.pointee.sa_family)
      guard family == AF_INET || family == AF_INET6 else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let len = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
      if getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
        result.append(String(cString: host))
      }
    }
    return result.sorted()
  }
}
