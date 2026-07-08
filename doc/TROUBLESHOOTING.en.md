# toxee Troubleshooting
> Language: [Chinese](TROUBLESHOOTING.md) | [English](TROUBLESHOOTING.en.md)

This document provides FAQs, log analysis guides, debugging tips, and performance optimization suggestions for toxee. **Build environment, per-platform steps, dependency installation**: see [BUILD_AND_DEPLOY.md](operations/BUILD_AND_DEPLOY.en.md). **First-time clone and dependency bootstrap**: see [getting-started.en.md](getting-started.en.md), [DEPENDENCY_BOOTSTRAP.en.md](operations/DEPENDENCY_BOOTSTRAP.en.md).

## Contents

- [FAQ](#faq)
- [Log Analysis](#log-analysis)
- [Debugging Tips](#debugging-tips)
- [Performance Optimization](#performance-optimization)

## FAQ

### Build issues

#### Q1: libsodium not found when building

**Symptoms**:
```
fatal error: 'sodium.h' file not found
```

**Solution**:

**macOS**:
```bash
brew install libsodium
```

**Linux**:
```bash
sudo apt-get install libsodium-dev
# or
sudo yum install libsodium-devel
```

**Windows**:
```bash
vcpkg install libsodium:x64-windows
```

#### Q2: CMake configuration failed

**Symptoms**:
```
CMake Error: Could not find a package configuration file
```

**Solution**:
1. Check CMake version: `cmake --version` (requires >= 3.4.1)
2. Check whether the dependent libraries are installed
3. Clean the build directory: `rm -rf build` and rebuild
4. Check environment variables and path configuration

#### Q3: Flutter dependency resolution failed

**Symptoms**:
```
Error: Could not resolve the package 'tim2tox_dart'
```

**Solution**:
```bash
# Clean and re-obtain dependencies
flutter clean
flutter pub get

# Check the path configuration in pubspec.yaml
# Make sure the tim2tox_dart path is correct
```

### Runtime issues

#### Q4: App crashes immediately after startup

**Symptoms**: App exits immediately after launching without any error message

**Possible reasons**:
1. Dynamic library loading failed
2. FFI function symbol not found
3. Initialization failed

**Solution**:

1. **Check dynamic library path**:
```bash
# macOS
otool -L libtim2tox_ffi.dylib

# Linux
ldd libtim2tox_ffi.so
```

2. **Check log files**:
```bash
# View build log
cat build/native_build.log
cat build/flutter_build.log

# View runtime logs
cat build/flutter_client.log
```

3. **Verify function symbols**:
```bash
# macOS/Linux
nm -D libtim2tox_ffi.dylib | grep Dart

# Windows
dumpbin /EXPORTS tim2tox_ffi.dll
```

#### Q5: Unable to connect to Tox network

**Symptoms**: "Not connected" or "Connection failed" is displayed after the application is launched

**Possible reasons**:
1. Network connection problem
2. Firewall blocking
3. Bootstrap node configuration error
4. libsodium is not packaged correctly

**Solution**:

1. **Check network connection**:
```bash
# Test network connection
ping 8.8.8.8
```

2. **Check firewall settings**:
- macOS: System Preferences > Security & Privacy > Firewall
- Linux: `sudo ufw status`
- Windows: Windows Defender Firewall

3. **Verify Bootstrap node**:
```dart
// Check current Bootstrap node configuration
final host = await bootstrapService.getBootstrapHost();
final port = await bootstrapService.getBootstrapPort();
final publicKey = await bootstrapService.getBootstrapPublicKey();
print('Bootstrap node: $host:$port');
print('Bootstrap public key: $publicKey');
```

4. **View connection log**:
```bash
# Check the logs for "bootstrap nodes queued" messages
grep "bootstrap" build/flutter_client.log
```

#### Q6: Message sending failed

**Symptom**: Failed status appears immediately after sending message

**Possible reasons**:
1. The contact is offline
2. Message timeout
3. Network connection issues

**Solution**:

1. **Check contact status**:
```dart
// Check if friends are online
final friends = await getFriendList();
for (final friend in friends) {
  print('Friend: ${friend.userID}, Online: ${friend.isOnline}');
}
```

2. **Check message timeout settings**:
- Text messages: Default 5 second timeout
- File messages: dynamically calculated based on size

3. **View failure message log**:
```dart
// Check failure message
final failedMessages = await getFailedMessages();
for (final msg in failedMessages) {
  print('Failed message: ${msg.msgID}, Reason: ${msg.failureReason}');
}
```

#### macOS voice/video calls (no audio capture, black video)

**Symptoms**: On macOS, the other party cannot hear you on voice calls, or video calls show a black screen locally or remotely.

**Solution**:

1. **System permissions**
   - Open **System Settings → Privacy & Security → Microphone** and ensure toxee is allowed.
   - Open **System Settings → Privacy & Security → Camera** and ensure toxee is allowed.

2. **Close apps using the device**
   - If another app (e.g. a browser tab, meeting software) is using the microphone or camera, close it and try again.

3. **When audio is not captured**
   - Ensure the app is signed with the correct entitlements: In Xcode, check the Runner target's **Signing & Capabilities** uses `Runner/DebugProfile.entitlements` (Debug) or `Runner/Release.entitlements` (Release), and that `com.apple.security.device.audio-input` is present.
   - You can verify from the terminal: `codesign -d --entitlements - --xml /path/to/toxee.app 2>/dev/null | grep -A1 audio-input`
   - Check the console or run logs for any `[AudioHandler]` errors or "all-zero audio" messages.

4. **When video is black**
   - Confirm camera permission is granted (see above).
   - Check logs for `[VideoHandler] startCapture: no cameras available` or `[VideoHandler] startCapture error`; if present, the camera is not ready or there is a permission/format issue.
   - Ensure the camera is not exclusively used by another app.

#### Q7: Callback does not trigger

**Symptom**: The registered listener callback is not called

**Possible reasons**:
1. SendPort is not registered
2. Dart API is not initialized
3. Listener is not registered correctly

**Solution**:

1. **Check SendPort registration**:
```dart
// Make sure to call it on initialization
final receivePort = ReceivePort();
bindings.DartRegisterSendPort(receivePort.sendPort.nativePort);
```

2. **Check Dart API initialization**:
```dart
// Make sure to call before registering SendPort
final result = bindings.DartInitDartApiDL(DartApiDL.initData);
if (result != 0) {
  print('Failed to initialize Dart API');
}
```

3. **Verify Listener registration**:
```dart
// Check if the Listener is correctly registered
TencentImSDKPlugin.v2TIMManager
    .getMessageManager()
    .addAdvancedMsgListener(
      listener: V2TimAdvancedMsgListener(
        onRecvNewMessage: (message) {
          print('Message received: ${message.msgID}');
        },
      ),
    );
```

#### Q8: UI displays "Invalid friend application"

**Symptom**: Friend application is shown as invalid

**Solution**:
- Ensure `ContactActionProvider` handles friend requests correctly
- Check if the returned `resultCode` is 0
- View error messages in logs

#### Q9: Wrong message order

**Symptom**: Messages in the message list are not in the correct order

**Solution**:
- The message list is sorted in ascending order by timestamp before rendering
- Check that the timestamp of the message is correct
- Make sure the message ID is in the format `timestamp_userID`

#### Q10: Dynamic library path error

**Symptoms**:
```
dlopen failed: library not found
```

**Solution**:

**macOS**:
```bash
# Check dynamic library path
otool -L libtim2tox_ffi.dylib

# repair path
install_name_tool -change \
    /old/path/libsodium.dylib \
    @loader_path/libsodium.dylib \
    libtim2tox_ffi.dylib
```

**Linux**:
```bash
# Check dependencies
ldd libtim2tox_ffi.so

# Set library path
export LD_LIBRARY_PATH=/path/to/libs:$LD_LIBRARY_PATH
```

**Windows**:
- Make sure all DLLs are in the executable directory
- Check the PATH environment variable

## Log analysis

### Log file location

Building and running the script generates the following logs:

- `build/native_build.log` - C++ build log
- `build/flutter_build.log` - Flutter build log
- `build/flutter_client.log` - Application runtime log

### Log level

#### C++ Log

Set during CMake configuration:

```bash
cmake .. -DDEBUG=ON -DTRACE=ON
```

Log level:
- `ERROR`: Error message
- `WARNING`: Warning message
- `INFO`: General information
- `DEBUG`: debugging information
- `TRACE`: Tracking information

#### Dart Log

Set during initialization:

```dart
TencentImSDKPlugin.v2TIMManager.initSDK(
  sdkAppID: 123456,
  logLevel: LogLevelEnum.V2TIM_LOG_DEBUG,
);
```

### Key log messages

#### Initialization successful

```
[callback_bridge] DartRegisterSendPort: registered port 12345
[dart_compat] DartInitSDK: SDK initialized
```

#### Connection successful

```
[dart_compat] OnConnectSuccess
[ffi] Connection status: connected
```

#### Message receiving

```
[dart_compat] OnRecvNewMessage: msgID=1234567890_user123
[ffi] Received message from user123
```

#### Error message

```
[ERROR] Failed to send message: timeout
[ERROR] Bootstrap connection failed: network error
```

### Log analysis skills

#### Find errors

```bash
# Find all errors
grep -i error build/flutter_client.log

# Find specific errors
grep "timeout" build/flutter_client.log
```

#### Track the calling process

```bash
# Track message delivery
grep "sendMessage" build/flutter_client.log

# Tracking callbacks
grep "SendCallbackToDart" build/flutter_client.log
```

#### Performance Analysis

```bash
# Find time-consuming operations
grep "took" build/flutter_client.log

# Count operations
grep -c "OnRecvNewMessage" build/flutter_client.log
```

## Debugging Tips

### Enable detailed logging

#### C++ layer

Enable at `CMakeLists.txt` or build time:

```bash
cmake .. -DDEBUG=ON -DTRACE=ON
```

#### Dart layer

Enable it in code:

```dart
// Set log level
TencentImSDKPlugin.v2TIMManager.initSDK(
  sdkAppID: 123456,
  logLevel: LogLevelEnum.V2TIM_LOG_DEBUG,
);

// Use LoggerService
loggerService?.debug('Debug message');
loggerService?.info('Info message');
loggerService?.warning('Warning message');
loggerService?.error('Error message', error, stackTrace);
```

### Using the debugger

#### C++ Debugging (GDB/LLDB)

```bash
# GDB (Linux)
gdb ./build/example/echo_bot_client
(gdb) break V2TIMMessageManagerImpl::SendMessage
(gdb) run

# LLDB (macOS)
lldb ./build/example/echo_bot_client
(lldb) breakpoint set --name V2TIMMessageManagerImpl::SendMessage
(lldb) run
```

#### Dart Debugging (Flutter)

```bash
# Run debug mode
flutter run --debug

# Attached debugger
# Set breakpoints in VS Code or Android Studio
```

### Check function symbols

```bash
# macOS/Linux
nm -D libtim2tox_ffi.dylib | grep Dart

# Windows
dumpbin /EXPORTS tim2tox_ffi.dll
```

### Verification callback message

Add logging in the Dart layer:

```dart
receivePort.listen((message) {
  print('Received callback: $message');
  try {
    final json = jsonDecode(message as String);
    print('Parsed JSON: $json');
    _handleNativeMessage(json);
  } catch (e) {
    print('Failed to parse callback: $e');
  }
});
```

### Network debugging

#### Check Tox connection

```dart
// Check connection status
final status = await ffiService.getConnectionStatus();
print('Connection status: $status');

// Monitor connection status changes
ffiService.connectionStatusStream.listen((connected) {
  print('Connection changed: $connected');
});
```

#### Check the Bootstrap node

```dart
// Get the current Bootstrap node
final host = await bootstrapService.getBootstrapHost();
final port = await bootstrapService.getBootstrapPort();
final publicKey = await bootstrapService.getBootstrapPublicKey();
print('Bootstrap node: $host:$port');
print('Bootstrap public key: $publicKey');
```

## Performance optimization

### Message processing optimization

#### Batch processing

```dart
// Process messages in batches rather than one by one
final messages = await getMessages();
processMessagesBatch(messages);
```

#### Using Stream

```dart
// Use Stream instead of polling
ffiService.messages.listen((message) {
  handleMessage(message);
});
```

#### Cache commonly used data

```dart
// cache friends list
final friendsCache = <String, V2TimFriendInfo>{};
final friends = await getFriendList();
for (final friend in friends) {
  friendsCache[friend.userID] = friend;
}
```

### Network optimization

#### Connection pool management

- Reuse Tox instances
- Avoid frequent creation and destruction of connections
- Use connection pooling to manage multiple connections

#### Automatically reconnect

```dart
// Monitor connection status and automatically reconnect
ffiService.connectionStatusStream.listen((connected) {
  if (!connected) {
    // Automatic reconnection logic
    reconnect();
  }
});
```

#### Network status monitoring

```dart
// Monitor network status
final connectivity = Connectivity();
connectivity.onConnectivityChanged.listen((result) {
  if (result == ConnectivityResult.none) {
    // Handling network disconnections
  } else {
    // Handle network recovery
  }
});
```

### Memory optimization

#### Object pool reuse

```dart
// Reuse message objects
class MessagePool {
  final _pool = <V2TimMessage>[];
  
  V2TimMessage acquire() {
    return _pool.isNotEmpty ? _pool.removeLast() : V2TimMessage();
  }
  
  void release(V2TimMessage msg) {
    _pool.add(msg);
  }
}
```

#### Release resources promptly

```dart
@override
void dispose() {
  // Unsubscribe
  _subscription?.cancel();
  
  // Clean up resources
  _controller.close();
  
  super.dispose();
}
```

#### Avoid memory leaks- Remove the listener promptly
- Avoid circular references
- Use weak references (WeakReference)

### UI optimization

#### Paging loading

```dart
// Load message list using pagination
class MessageList extends StatefulWidget {
  @override
  _MessageListState createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _messages = <V2TimMessage>[];
  bool _isLoading = false;
  
  Future<void> _loadMore() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    final more = await loadMessages(offset: _messages.length, limit: 20);
    setState(() {
      _messages.addAll(more);
      _isLoading = false;
    });
  }
}
```

#### Virtual scrolling

```dart
// Implement virtual scrolling using ListView.builder
ListView.builder(
  itemCount: _messages.length,
  itemBuilder: (context, index) {
    return MessageItem(message: _messages[index]);
  },
)
```

#### Image cache

```dart
// Use cache to manage images
CachedNetworkImage(
  imageUrl: avatarUrl,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
)
```

## Related documents

- [toxee Build and Deployment](operations/BUILD_AND_DEPLOY.en.md) - Build environment, per-platform steps (also check this doc’s FAQ for build failures)
- [getting-started.en.md](getting-started.en.md) - Clone to run
- [Dependency bootstrap](operations/DEPENDENCY_BOOTSTRAP.en.md) - Bootstrap order and options
- [Integration Guide](integration/INTEGRATION_GUIDE.en.md) - Guide to integrating [Tim2Tox](https://github.com/agentx-icu/tim2tox)
- [Main README](../README.md) - Project Overview