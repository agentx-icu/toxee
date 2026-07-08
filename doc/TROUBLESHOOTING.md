# toxee 故障排查
> 语言 / Language: [中文](TROUBLESHOOTING.md) | [English](TROUBLESHOOTING.en.md)

本文档提供 toxee 的常见问题解答、日志分析指南、调试技巧和性能优化建议。**构建环境、各平台详细步骤、依赖安装**见 [operations/BUILD_AND_DEPLOY.md](operations/BUILD_AND_DEPLOY.md)；**首次克隆与依赖引导**见 [getting-started.md](getting-started.md)、[operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md)。

## 目录

- [常见问题](#常见问题)
- [日志分析](#日志分析)
- [调试技巧](#调试技巧)
- [性能优化](#性能优化)

## 常见问题

### 构建问题

#### Q1: 构建时找不到 libsodium

**症状**:
```
fatal error: 'sodium.h' file not found
```

**解决方案**:

**macOS**:
```bash
brew install libsodium
```

**Linux**:
```bash
sudo apt-get install libsodium-dev
# 或
sudo yum install libsodium-devel
```

**Windows**:
```bash
vcpkg install libsodium:x64-windows
```

#### Q2: CMake 配置失败

**症状**:
```
CMake Error: Could not find a package configuration file
```

**解决方案**:
1. 检查 CMake 版本: `cmake --version` (需要 >= 3.4.1)
2. 检查依赖库是否已安装
3. 清理构建目录: `rm -rf build` 然后重新构建
4. 检查环境变量和路径配置

#### Q3: Flutter 依赖解析失败

**症状**:
```
Error: Could not resolve the package 'tim2tox_dart'
```

**解决方案**:
```bash
# 清理并重新获取依赖
flutter clean
flutter pub get

# 检查 pubspec.yaml 中的路径配置
# 确保 tim2tox_dart 路径正确
```

### 运行时问题

#### Q4: 应用启动后立即崩溃

**症状**: 应用启动后立即退出，没有任何错误信息

**可能原因**:
1. 动态库加载失败
2. FFI 函数符号未找到
3. 初始化失败

**解决方案**:

1. **检查动态库路径**:
```bash
# macOS
otool -L libtim2tox_ffi.dylib

# Linux
ldd libtim2tox_ffi.so
```

2. **检查日志文件**:
```bash
# 查看构建日志
cat build/native_build.log
cat build/flutter_build.log

# 查看运行时日志
cat build/flutter_client.log
```

3. **验证函数符号**:
```bash
# macOS/Linux
nm -D libtim2tox_ffi.dylib | grep Dart

# Windows
dumpbin /EXPORTS tim2tox_ffi.dll
```

#### Q5: 无法连接到 Tox 网络

**症状**: 应用启动后显示"未连接"或"连接失败"

**可能原因**:
1. 网络连接问题
2. 防火墙阻止
3. Bootstrap 节点配置错误
4. libsodium 未正确打包

**解决方案**:

1. **检查网络连接**:
```bash
# 测试网络连接
ping 8.8.8.8
```

2. **检查防火墙设置**:
- macOS: 系统偏好设置 > 安全性与隐私 > 防火墙
- Linux: `sudo ufw status`
- Windows: Windows Defender 防火墙

3. **验证 Bootstrap 节点**:
```dart
// 检查当前 Bootstrap 节点配置
final host = await bootstrapService.getBootstrapHost();
final port = await bootstrapService.getBootstrapPort();
final publicKey = await bootstrapService.getBootstrapPublicKey();
print('Bootstrap node: $host:$port');
print('Bootstrap public key: $publicKey');
```

4. **查看连接日志**:
```bash
# 查看日志中的 "bootstrap nodes queued" 消息
grep "bootstrap" build/flutter_client.log
```

#### Q6: 消息发送失败

**症状**: 发送消息后立即显示为失败状态

**可能原因**:
1. 联系人离线
2. 消息超时
3. 网络连接问题

**解决方案**:

1. **检查联系人状态**:
```dart
// 检查好友是否在线
final friends = await getFriendList();
for (final friend in friends) {
  print('Friend: ${friend.userID}, Online: ${friend.isOnline}');
}
```

2. **检查消息超时设置**:
- 文本消息: 默认 5 秒超时
- 文件消息: 根据大小动态计算

3. **查看失败消息日志**:
```dart
// 检查失败消息
final failedMessages = await getFailedMessages();
for (final msg in failedMessages) {
  print('Failed message: ${msg.msgID}, Reason: ${msg.failureReason}');
}
```

#### macOS 音视频通话（语音无采集、视频黑屏）

**症状**: 在 macOS 上语音通话对方听不到本端声音，或视频通话本地/远端黑屏。

**解决方案**:

1. **系统权限**
   - 打开 **系统设置 → 隐私与安全性 → 麦克风**，确保已允许 toxee 使用麦克风。
   - 打开 **系统设置 → 隐私与安全性 → 摄像头**，确保已允许 toxee 使用摄像头。

2. **关闭占用设备的应用**
   - 若其他应用（如浏览器标签、会议软件）正在使用麦克风或摄像头，请关闭后再试。

3. **音频无法采集时**
   - 确认应用已正确签名并包含沙盒能力：在 Xcode 中检查 Runner target 的 **Signing & Capabilities**，应使用 `Runner/DebugProfile.entitlements`（Debug）或 `Runner/Release.entitlements`（Release），且其中包含 `com.apple.security.device.audio-input`。
   - 可在终端验证：`codesign -d --entitlements - --xml /path/to/toxee.app 2>/dev/null | grep -A1 audio-input`
   - 查看控制台或运行日志中是否有 `[AudioHandler]` 相关错误或“all-zero audio”提示。

4. **视频黑屏时**
   - 确认摄像头权限已授予（见上文）。
   - 查看日志是否有 `[VideoHandler] startCapture: no cameras available` 或 `[VideoHandler] startCapture error`；若有，说明摄像头未就绪或权限/格式问题。
   - 确保未在其他应用中独占使用摄像头。

#### Q7: 回调不触发

**症状**: 注册的监听器回调没有被调用

**可能原因**:
1. SendPort 未注册
2. Dart API 未初始化
3. Listener 未正确注册

**解决方案**:

1. **检查 SendPort 注册**:
```dart
// 确保在初始化时调用
final receivePort = ReceivePort();
bindings.DartRegisterSendPort(receivePort.sendPort.nativePort);
```

2. **检查 Dart API 初始化**:
```dart
// 确保在注册 SendPort 之前调用
final result = bindings.DartInitDartApiDL(DartApiDL.initData);
if (result != 0) {
  print('Failed to initialize Dart API');
}
```

3. **验证 Listener 注册**:
```dart
// 检查 Listener 是否正确注册
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

#### Q8: UI 显示 "Invalid friend application"

**症状**: 好友申请显示为无效

**解决方案**:
- 确保 `ContactActionProvider` 正确处理好友申请
- 检查返回的 `resultCode` 是否为 0
- 查看日志中的错误信息

#### Q9: 消息顺序错误

**症状**: 消息列表中的消息顺序不正确

**解决方案**:
- 消息列表在渲染前按时间戳升序排序
- 检查消息的时间戳是否正确
- 确保消息 ID 格式为 `timestamp_userID`

#### Q10: 动态库路径错误

**症状**: 
```
dlopen failed: library not found
```

**解决方案**:

**macOS**:
```bash
# 检查动态库路径
otool -L libtim2tox_ffi.dylib

# 修复路径
install_name_tool -change \
    /old/path/libsodium.dylib \
    @loader_path/libsodium.dylib \
    libtim2tox_ffi.dylib
```

**Linux**:
```bash
# 检查依赖
ldd libtim2tox_ffi.so

# 设置库路径
export LD_LIBRARY_PATH=/path/to/libs:$LD_LIBRARY_PATH
```

**Windows**:
- 确保所有 DLL 在可执行文件目录
- 检查 PATH 环境变量

## 日志分析

### 日志文件位置

构建和运行脚本会生成以下日志：

- `build/native_build.log` - C++ 构建日志
- `build/flutter_build.log` - Flutter 构建日志
- `build/flutter_client.log` - 应用运行时日志

### 日志级别

#### C++ 日志

在 CMake 配置时设置：

```bash
cmake .. -DDEBUG=ON -DTRACE=ON
```

日志级别：
- `ERROR`: 错误信息
- `WARNING`: 警告信息
- `INFO`: 一般信息
- `DEBUG`: 调试信息
- `TRACE`: 跟踪信息

#### Dart 日志

在初始化时设置：

```dart
TencentImSDKPlugin.v2TIMManager.initSDK(
  sdkAppID: 123456,
  logLevel: LogLevelEnum.V2TIM_LOG_DEBUG,
);
```

### 关键日志消息

#### 初始化成功

```
[callback_bridge] DartRegisterSendPort: registered port 12345
[dart_compat] DartInitSDK: SDK initialized
```

#### 连接成功

```
[dart_compat] OnConnectSuccess
[ffi] Connection status: connected
```

#### 消息接收

```
[dart_compat] OnRecvNewMessage: msgID=1234567890_user123
[ffi] Received message from user123
```

#### 错误信息

```
[ERROR] Failed to send message: timeout
[ERROR] Bootstrap connection failed: network error
```

### 日志分析技巧

#### 查找错误

```bash
# 查找所有错误
grep -i error build/flutter_client.log

# 查找特定错误
grep "timeout" build/flutter_client.log
```

#### 跟踪调用流程

```bash
# 跟踪消息发送
grep "sendMessage" build/flutter_client.log

# 跟踪回调
grep "SendCallbackToDart" build/flutter_client.log
```

#### 性能分析

```bash
# 查找耗时操作
grep "took" build/flutter_client.log

# 统计操作次数
grep -c "OnRecvNewMessage" build/flutter_client.log
```

## 调试技巧

### 启用详细日志

#### C++ 层

在 `CMakeLists.txt` 或构建时启用：

```bash
cmake .. -DDEBUG=ON -DTRACE=ON
```

#### Dart 层

在代码中启用：

```dart
// 设置日志级别
TencentImSDKPlugin.v2TIMManager.initSDK(
  sdkAppID: 123456,
  logLevel: LogLevelEnum.V2TIM_LOG_DEBUG,
);

// 使用 LoggerService
loggerService?.debug('Debug message');
loggerService?.info('Info message');
loggerService?.warning('Warning message');
loggerService?.error('Error message', error, stackTrace);
```

### 使用调试器

#### C++ 调试 (GDB/LLDB)

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

#### Dart 调试 (Flutter)

```bash
# 运行调试模式
flutter run --debug

# 附加调试器
# 在 VS Code 或 Android Studio 中设置断点
```

### 检查函数符号

```bash
# macOS/Linux
nm -D libtim2tox_ffi.dylib | grep Dart

# Windows
dumpbin /EXPORTS tim2tox_ffi.dll
```

### 验证回调消息

在 Dart 层添加日志：

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

### 网络调试

#### 检查 Tox 连接

```dart
// 检查连接状态
final status = await ffiService.getConnectionStatus();
print('Connection status: $status');

// 监听连接状态变化
ffiService.connectionStatusStream.listen((connected) {
  print('Connection changed: $connected');
});
```

#### 检查 Bootstrap 节点

```dart
// 获取当前 Bootstrap 节点
final host = await bootstrapService.getBootstrapHost();
final port = await bootstrapService.getBootstrapPort();
final publicKey = await bootstrapService.getBootstrapPublicKey();
print('Bootstrap node: $host:$port');
print('Bootstrap public key: $publicKey');
```

## 性能优化

### 消息处理优化

#### 批量处理

```dart
// 批量处理消息而不是逐个处理
final messages = await getMessages();
processMessagesBatch(messages);
```

#### 使用 Stream

```dart
// 使用 Stream 而不是轮询
ffiService.messages.listen((message) {
  handleMessage(message);
});
```

#### 缓存常用数据

```dart
// 缓存好友列表
final friendsCache = <String, V2TimFriendInfo>{};
final friends = await getFriendList();
for (final friend in friends) {
  friendsCache[friend.userID] = friend;
}
```

### 网络优化

#### 连接池管理

- 复用 Tox 实例
- 避免频繁创建和销毁连接
- 使用连接池管理多个连接

#### 自动重连

```dart
// 监听连接状态并自动重连
ffiService.connectionStatusStream.listen((connected) {
  if (!connected) {
    // 自动重连逻辑
    reconnect();
  }
});
```

#### 网络状态监控

```dart
// 监控网络状态
final connectivity = Connectivity();
connectivity.onConnectivityChanged.listen((result) {
  if (result == ConnectivityResult.none) {
    // 处理网络断开
  } else {
    // 处理网络恢复
  }
});
```

### 内存优化

#### 对象池复用

```dart
// 复用消息对象
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

#### 及时释放资源

```dart
@override
void dispose() {
  // 取消订阅
  _subscription?.cancel();
  
  // 清理资源
  _controller.close();
  
  super.dispose();
}
```

#### 避免内存泄漏

- 及时移除监听器
- 避免循环引用
- 使用弱引用（WeakReference）

### UI 优化

#### 分页加载

```dart
// 使用分页加载消息列表
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

#### 虚拟滚动

```dart
// 使用 ListView.builder 实现虚拟滚动
ListView.builder(
  itemCount: _messages.length,
  itemBuilder: (context, index) {
    return MessageItem(message: _messages[index]);
  },
)
```

#### 图片缓存

```dart
// 使用缓存管理图片
CachedNetworkImage(
  imageUrl: avatarUrl,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
)
```

## 相关文档

- [toxee 构建与部署](operations/BUILD_AND_DEPLOY.md) - 构建环境、各平台步骤、依赖安装（构建失败时也可先查本文「常见问题」）
- [getting-started.md](getting-started.md) - 从克隆到跑起来
- [依赖引导](operations/DEPENDENCY_BOOTSTRAP.md) - bootstrap 顺序与选项
- [集成指南](integration/INTEGRATION_GUIDE.md) - 集成 [Tim2Tox](https://github.com/agentx-icu/tim2tox) 指南
- [主 README](../README.zh-CN.md) - 项目概述
