import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import '../discovery/unified_discovery.dart';
import 'app_driver.dart';

class FlutterSkillClient implements AppDriver {
  final String wsUri;
  VmService? _service;
  String? _isolateId;
  bool _reconnecting = false;

  FlutterSkillClient(this.wsUri);

  /// Get the VM Service URI this client is connected to
  String get vmServiceUri => wsUri;

  Future<void> connect() async {
    print('DEBUG: Connecting to $wsUri');
    try {
      _service = await vmServiceConnectUri(wsUri);
      print('DEBUG: Connected to VM Service');

      final vm = await _service!.getVM();
      print('DEBUG: Got VM info');
      final isolates = vm.isolates;
      if (isolates == null || isolates.isEmpty) {
        throw Exception('''❌ No Dart isolates found in the VM

This usually means:
• App is still starting up (wait a few seconds and retry)
• App crashed during startup
• flutter_skill dependency is not properly initialized

Solution:
1. Wait 2-3 seconds and try again
2. Ensure FlutterSkillBinding.ensureInitialized() is called in main()
3. Check app logs for startup errors

URI: $wsUri''');
      }
      _isolateId = isolates.first.id!;
    } catch (e) {
      // Clean up partially initialized service
      try {
        await _service?.dispose();
      } catch (_) {}
      _service = null;
      _isolateId = null;

      throw Exception('''❌ Failed to connect to VM Service at $wsUri

Possible causes:
• Invalid URI format (must start with ws://)
• App is not running or has crashed
• Wrong port number
• Network connectivity issues
• VM Service proxy failed to initialize (LateInitializationError)

Solution:
1. Verify the URI: $wsUri
2. Check if app is running: flutter run --vm-service-port=50000
3. Try scan_and_connect() to auto-detect running apps

Error details: $e''');
    }
  }

  Future<void> disconnect() async {
    try {
      await _service?.dispose();
    } catch (_) {
      // Ignore errors during disposal — service may already be broken
    }
    _service = null;
    _isolateId = null;
  }

  /// Check if an error indicates a broken VM Service connection that
  /// may be recoverable via reconnection.
  bool _isConnectionError(Object e) {
    final msg = e.toString();
    return msg.contains('LateInitializationError') ||
        (e is StateError && msg.contains('Stream'));
  }

  /// Attempt to re-establish the VM Service connection.
  /// Returns true if reconnection succeeded.
  Future<bool> _reconnect() async {
    if (_reconnecting) return false;
    _reconnecting = true;
    try {
      print(
          'DEBUG: VM Service connection lost, attempting reconnect to $wsUri');
      // Tear down the old connection
      try {
        await _service?.dispose();
      } catch (_) {}
      _service = null;
      _isolateId = null;

      // Re-establish
      _service = await vmServiceConnectUri(wsUri);
      final vm = await _service!.getVM();
      final isolates = vm.isolates;
      if (isolates != null && isolates.isNotEmpty) {
        _isolateId = isolates.first.id!;
        print('DEBUG: Reconnected to VM Service successfully');
        return true;
      }
      // Connected but no isolates — app may have exited
      _service = null;
      return false;
    } catch (e) {
      print('DEBUG: Reconnection failed: $e');
      _service = null;
      _isolateId = null;
      return false;
    } finally {
      _reconnecting = false;
    }
  }

  Future<Map<String, dynamic>> _call(String method,
      [Map<String, dynamic>? args]) async {
    if (_service == null || _isolateId == null) {
      throw Exception('''❌ Not connected to VM Service

Call connect() first before making requests.
URI: $wsUri''');
    }
    try {
      final response = await _service!.callServiceExtension(
        method,
        isolateId: _isolateId!,
        args: args,
      );
      return response.json ?? {};
    } catch (e) {
      // Detect SDK-not-integrated errors and surface a clear setup message.
      final msg = e.toString();
      if (msg.contains('Method not found') ||
          msg.contains('Service extension not found') ||
          msg.contains('ext.flutter.flutter_skill') && msg.contains('-32601')) {
        throw Exception('''❌ flutter_skill SDK not found in the running app.

The app is running but the flutter_skill extensions are not registered.

🔧 Fix:
1. Add dependency to pubspec.yaml:
   flutter pub add flutter_skill

2. Add to lib/main.dart BEFORE runApp():
   import 'package:flutter_skill/flutter_skill.dart';
   void main() {
     FlutterSkillBinding.ensureInitialized();
     runApp(MyApp());
   }

3. Hot restart the app (not just hot reload):
   flutter_skill hot_restart

Auto-setup: run  diagnose_project()  to fix automatically.
''');
      }
      if (!_isConnectionError(e)) rethrow;

      // Connection broken — attempt one reconnect and retry
      if (await _reconnect()) {
        final response = await _service!.callServiceExtension(
          method,
          isolateId: _isolateId!,
          args: args,
        );
        return response.json ?? {};
      }
      throw Exception('❌ VM Service connection lost and reconnection failed.\n'
          'URI: $wsUri\n'
          'Original error: $e\n\n'
          'Try: scan_and_connect() or connect_app(uri: "ws://...")');
    }
  }

  // ==================== EXISTING METHODS ====================

  /// Tap an element. Returns result with success status.
  /// Supports semantic ref IDs from inspect_interactive for reliable targeting.
  Future<Map<String, dynamic>> tap(
      {String? key, String? text, String? ref}) async {
    if (key == null && text == null && ref == null) {
      throw ArgumentError('Must provide key, text, or ref for tap');
    }
    final result = await _call('ext.flutter.flutter_skill.tap', {
      if (key != null) 'key': key,
      if (text != null) 'text': text,
      if (ref != null) 'ref': ref,
    });
    return result;
  }

  /// Enter text into a field. Returns result with success status.
  /// Supports semantic ref IDs from inspect_interactive for reliable targeting.
  Future<Map<String, dynamic>> enterText(String? key, String text,
      {String? ref}) async {
    final result = await _call('ext.flutter.flutter_skill.enterText', {
      if (key != null) 'key': key,
      'text': text,
      if (ref != null) 'ref': ref,
    });
    return result;
  }

  /// Scroll to element. Returns result with success status.
  Future<Map<String, dynamic>> scrollTo({String? key, String? text}) async {
    final result = await _call('ext.flutter.flutter_skill.scroll', {
      if (key != null) 'key': key,
      if (text != null) 'text': text,
    });
    return result;
  }

  // ==================== UI INSPECTION ====================

  Future<Map<String, dynamic>> getWidgetTree({int maxDepth = 10}) async {
    final result = await _call('ext.flutter.flutter_skill.getWidgetTree', {
      'maxDepth': maxDepth.toString(),
    });
    return result['tree'] ?? {};
  }

  Future<Map<String, dynamic>?> getWidgetProperties(String key) async {
    final result =
        await _call('ext.flutter.flutter_skill.getWidgetProperties', {
      'key': key,
    });
    return result['properties'];
  }

  Future<List<dynamic>> getTextContent() async {
    final result = await _call('ext.flutter.flutter_skill.getTextContent');
    return result['texts'] ?? [];
  }

  Future<List<dynamic>> findByType(String type) async {
    final result = await _call('ext.flutter.flutter_skill.findByType', {
      'type': type,
    });
    return result['elements'] ?? [];
  }

  // ==================== MORE INTERACTIONS ====================

  Future<bool> longPress(
      {String? key, String? text, int duration = 500}) async {
    final result = await _call('ext.flutter.flutter_skill.longPress', {
      if (key != null) 'key': key,
      if (text != null) 'text': text,
      'duration': duration.toString(),
    });
    return result['success'] == true;
  }

  Future<bool> swipe(
      {required String direction, double distance = 300, String? key}) async {
    final result = await _call('ext.flutter.flutter_skill.swipe', {
      'direction': direction,
      'distance': distance.toString(),
      if (key != null) 'key': key,
    });
    return result['success'] == true;
  }

  Future<bool> drag({required String fromKey, required String toKey}) async {
    final result = await _call('ext.flutter.flutter_skill.drag', {
      'fromKey': fromKey,
      'toKey': toKey,
    });
    return result['success'] == true;
  }

  Future<bool> doubleTap({String? key, String? text}) async {
    final result = await _call('ext.flutter.flutter_skill.doubleTap', {
      if (key != null) 'key': key,
      if (text != null) 'text': text,
    });
    return result['success'] == true;
  }

  /// Press a key by name in the running Flutter app via the VM Service extension.
  /// Supported keys: enter, tab, escape, backspace, delete, space, up, down,
  /// left, right, and any single character.
  Future<Map<String, dynamic>> pressKey(String key,
      {List<String>? modifiers}) async {
    return await _call('ext.flutter.flutter_skill.pressKey', {
      'key': key,
      if (modifiers != null && modifiers.isNotEmpty)
        'modifiers': modifiers.join(','),
    });
  }

  // ==================== STATE & VALIDATION ====================

  Future<String?> getTextValue(String? key) async {
    final result = await _call('ext.flutter.flutter_skill.getTextValue', {
      if (key != null) 'key': key,
    });
    return result['value'];
  }

  Future<bool?> getCheckboxState(String key) async {
    final result = await _call('ext.flutter.flutter_skill.getCheckboxState', {
      'key': key,
    });
    return result['checked'];
  }

  Future<double?> getSliderValue(String key) async {
    final result = await _call('ext.flutter.flutter_skill.getSliderValue', {
      'key': key,
    });
    return result['value']?.toDouble();
  }

  Future<bool> waitForElement(
      {String? key, String? text, int timeout = 5000}) async {
    final result = await _call('ext.flutter.flutter_skill.waitForElement', {
      if (key != null) 'key': key,
      if (text != null) 'text': text,
      'timeout': timeout.toString(),
    });
    return result['found'] == true;
  }

  Future<bool> waitForGone(
      {String? key, String? text, int timeout = 5000}) async {
    final result = await _call('ext.flutter.flutter_skill.waitForGone', {
      if (key != null) 'key': key,
      if (text != null) 'text': text,
      'timeout': timeout.toString(),
    });
    return result['gone'] == true;
  }

  // ==================== SCREENSHOT ====================

  Future<String?> takeScreenshot({double quality = 1.0, int? maxWidth}) async {
    final result = await _call('ext.flutter.flutter_skill.screenshot', {
      'quality': quality.toString(),
      if (maxWidth != null) 'maxWidth': maxWidth.toString(),
    });
    return result['image'];
  }

  Future<String?> takeRegionScreenshot(
      double x, double y, double width, double height) async {
    final result = await _call('ext.flutter.flutter_skill.screenshotRegion', {
      'x': x.toString(),
      'y': y.toString(),
      'width': width.toString(),
      'height': height.toString(),
    });
    return result['image'];
  }

  Future<String?> takeElementScreenshot(String key) async {
    final result = await _call('ext.flutter.flutter_skill.screenshotElement', {
      'key': key,
    });
    return result['image'];
  }

  // ==================== NAVIGATION ====================

  Future<String?> getCurrentRoute() async {
    final result = await _call('ext.flutter.flutter_skill.getCurrentRoute');
    return result['route'];
  }

  Future<bool> goBack() async {
    final result = await _call('ext.flutter.flutter_skill.goBack');
    return result['success'] == true;
  }

  Future<List<String>> getNavigationStack() async {
    final result = await _call('ext.flutter.flutter_skill.getNavigationStack');
    return (result['stack'] as List?)?.cast<String>() ?? [];
  }

  // ==================== DEBUG & LOGS ====================

  Future<List<String>> getLogs() async {
    final result = await _call('ext.flutter.flutter_skill.getLogs');
    return (result['logs'] as List?)?.cast<String>() ?? [];
  }

  Future<List<dynamic>> getErrors() async {
    final result = await _call('ext.flutter.flutter_skill.getErrors');
    return result['errors'] ?? [];
  }

  Future<void> clearLogs() async {
    await _call('ext.flutter.flutter_skill.clearLogs');
  }

  Future<Map<String, dynamic>> getPerformance() async {
    return await _call('ext.flutter.flutter_skill.getPerformance');
  }

  // ==================== COORDINATE-BASED ACTIONS ====================

  Future<Map<String, dynamic>> tapAt(double x, double y) async {
    return await _call('ext.flutter.flutter_skill.tapAt', {
      'x': x.toString(),
      'y': y.toString(),
    });
  }

  Future<Map<String, dynamic>> longPressAt(double x, double y,
      {int duration = 500}) async {
    return await _call('ext.flutter.flutter_skill.longPressAt', {
      'x': x.toString(),
      'y': y.toString(),
      'duration': duration.toString(),
    });
  }

  Future<Map<String, dynamic>> swipeCoordinates(
    double startX,
    double startY,
    double endX,
    double endY, {
    int duration = 300,
  }) async {
    return await _call('ext.flutter.flutter_skill.swipeCoordinates', {
      'startX': startX.toString(),
      'startY': startY.toString(),
      'endX': endX.toString(),
      'endY': endY.toString(),
      'duration': duration.toString(),
    });
  }

  /// Edge swipe from screen edge
  Future<Map<String, dynamic>> edgeSwipe({
    required String edge, // left, right, top, bottom
    required String direction, // up, down, left, right
    double distance = 200,
  }) async {
    return await _call('ext.flutter.flutter_skill.edgeSwipe', {
      'edge': edge,
      'direction': direction,
      'distance': distance.toString(),
    });
  }

  // ==================== PERFORMANCE & MEMORY ====================

  Future<Map<String, dynamic>> getFrameStats() async {
    try {
      final result = await _call('ext.flutter.flutter_skill.getFrameStats');
      return result;
    } catch (e) {
      // Fallback to basic stats if extension not available
      return {
        "message":
            "Frame stats not available. Ensure flutter_skill is properly initialized in the app.",
        "error": e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> getMemoryStats() async {
    if (_service == null || _isolateId == null) {
      throw Exception('Not connected to Flutter app');
    }

    try {
      final allocationProfile =
          await _service!.getAllocationProfile(_isolateId!);
      return {
        "heapUsed": allocationProfile.memoryUsage?.heapUsage ?? 0,
        "heapCapacity": allocationProfile.memoryUsage?.heapCapacity ?? 0,
        "external": allocationProfile.memoryUsage?.externalUsage ?? 0,
      };
    } catch (e) {
      // getAllocationProfile not available on web VM
      if (e.toString().contains('Unknown method') ||
          e.toString().contains('-32601')) {
        return {
          "heapUsed": 0,
          "heapCapacity": 0,
          "external": 0,
          "message": "Memory stats not available on this platform",
        };
      }
      if (!_isConnectionError(e)) rethrow;
      if (await _reconnect()) {
        final allocationProfile =
            await _service!.getAllocationProfile(_isolateId!);
        return {
          "heapUsed": allocationProfile.memoryUsage?.heapUsage ?? 0,
          "heapCapacity": allocationProfile.memoryUsage?.heapCapacity ?? 0,
          "external": allocationProfile.memoryUsage?.externalUsage ?? 0,
        };
      }
      throw Exception('❌ VM Service connection lost and reconnection failed.\n'
          'URI: $wsUri\n'
          'Original error: $e');
    }
  }

  // ==================== ENHANCED INSPECTION ====================

  Future<List<dynamic>> getInteractiveElements(
      {bool includePositions = true}) async {
    final result = await _call('ext.flutter.flutter_skill.interactive', {
      'includePositions': includePositions.toString(),
    });

    if (result.containsKey('elements')) {
      return result['elements'] as List<dynamic>;
    }
    return [];
  }

  /// Get interactive elements with enhanced structure including actions and selectors
  Future<Map<String, dynamic>> getInteractiveElementsStructured() async {
    final result =
        await _call('ext.flutter.flutter_skill.interactiveStructured');

    if (result.containsKey('data')) {
      return result['data'] as Map<String, dynamic>;
    }

    // Return empty structured result if no data
    return {
      'elements': <Map<String, dynamic>>[],
      'summary': 'No interactive elements found',
    };
  }

  // ==================== EXISTING HELPERS ====================

  Future<void> hotReload() async {
    if (_service == null || _isolateId == null) {
      throw Exception('Not connected');
    }
    try {
      await _service!.reloadSources(_isolateId!);
    } catch (e) {
      if (!_isConnectionError(e)) rethrow;
      if (await _reconnect()) {
        await _service!.reloadSources(_isolateId!);
        return;
      }
      throw Exception('❌ VM Service connection lost and reconnection failed.\n'
          'URI: $wsUri\n'
          'Original error: $e');
    }
  }

  Future<void> hotRestart() async {
    if (_service == null || _isolateId == null) {
      throw Exception('Not connected');
    }
    try {
      await _service!.reloadSources(_isolateId!);
    } catch (e) {
      if (!_isConnectionError(e)) rethrow;
      if (await _reconnect()) {
        await _service!.reloadSources(_isolateId!);
        return;
      }
      throw Exception('❌ VM Service connection lost and reconnection failed.\n'
          'URI: $wsUri\n'
          'Original error: $e');
    }
  }

  Future<Map<String, dynamic>> getLayoutTree() async {
    try {
      final groupName =
          'flutter_skill_${DateTime.now().millisecondsSinceEpoch}';
      final result =
          await _call('ext.flutter.inspector.getRootWidgetSummaryTree', {
        'objectGroup': groupName,
      });
      return result;
    } catch (e) {
      rethrow;
    }
  }

  bool get isConnected => _service != null && _isolateId != null;

  @override
  String get frameworkName => 'Flutter';

  static Future<String> resolveUri(List<String> args) async {
    // 1. If URI provided as argument, use it directly
    if (args.isNotEmpty) {
      final arg = args[0];
      if (arg.startsWith('ws://') || arg.startsWith('http://')) {
        return arg;
      }
    }

    // 2. Try automatic discovery (fast and smart!)
    print('🔍 Auto-discovering running Flutter apps...');

    try {
      final result = await UnifiedDiscovery.discover(verbose: false);

      if (result.success && result.vmServiceUri != null) {
        // Convert http:// to ws:// if needed
        var uri = result.vmServiceUri!;
        if (uri.startsWith('http://')) {
          uri = uri.replaceFirst('http://', 'ws://');
          if (!uri.endsWith('/ws')) {
            uri = '$uri/ws';
          }
        }
        print('✅ Connected: $uri');
        return uri;
      }
    } catch (e) {
      print('⚠️  Auto-discovery failed: $e');
    }

    // 3. All methods failed
    throw ArgumentError('\n❌ No running Flutter apps found\n\n'
        'Please try:\n'
        '  1. Launch app: flutter_skill launch -d <device>\n'
        '  2. Or manually: flutter run -d <device>\n'
        '  3. Or provide URI: flutter_skill inspect ws://...\n');
  }

  // ==================== TEST INDICATORS ====================

  /// Enable test indicators with optional style
  Future<Map<String, dynamic>> enableTestIndicators(
      {String style = 'standard'}) async {
    return await _call('ext.flutter.flutter_skill.enableIndicators', {
      'style': style,
    });
  }

  /// Disable test indicators
  Future<Map<String, dynamic>> disableTestIndicators() async {
    return await _call('ext.flutter.flutter_skill.disableIndicators');
  }

  /// Get indicator status
  Future<Map<String, dynamic>> getIndicatorStatus() async {
    return await _call('ext.flutter.flutter_skill.getIndicatorStatus');
  }

  // ==================== HTTP MONITORING ====================

  /// Enable HTTP timeline logging via VM Service
  Future<bool> enableHttpTimelineLogging({bool enable = true}) async {
    try {
      await _service!.callServiceExtension(
        'ext.dart.io.httpEnableTimelineLogging',
        isolateId: _isolateId,
        args: {'enabled': enable},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get HTTP profile from VM Service (built-in Dart HTTP profiling)
  Future<Map<String, dynamic>> getHttpProfile() async {
    try {
      final response = await _service!.callServiceExtension(
        'ext.dart.io.getHttpProfile',
        isolateId: _isolateId,
      );
      return response.json ?? {};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Get HTTP request details from VM Service
  Future<Map<String, dynamic>> getHttpProfileRequest(int id) async {
    try {
      final response = await _service!.callServiceExtension(
        'ext.dart.io.getHttpProfileRequest',
        isolateId: _isolateId,
        args: {'id': id},
      );
      return response.json ?? {};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Get manually logged HTTP requests from the app
  Future<Map<String, dynamic>> getHttpRequests(
      {int limit = 50, int offset = 0}) async {
    return await _call('ext.flutter.flutter_skill.getHttpRequests', {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
  }

  /// Clear manually logged HTTP requests
  Future<Map<String, dynamic>> clearHttpRequests() async {
    return await _call('ext.flutter.flutter_skill.clearHttpRequests');
  }
}
