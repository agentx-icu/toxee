# toxee 多平台支持
> 语言 / Language: [中文](PLATFORM_SUPPORT.md) | [English](PLATFORM_SUPPORT.en.md)


本文档详细说明 toxee 的多操作系统和多平台支持。

## 支持的平台

### 操作系统

- ✅ **macOS**: 10.15 或更高版本（与 `macos/Podfile` 的 `platform :osx, '10.15'` 和 `MACOSX_DEPLOYMENT_TARGET = 10.15` 一致）
- ✅ **Linux**: 支持主流发行版（Ubuntu 18.04+, Debian 10+, Fedora 30+ 等）
- ✅ **Windows**: Windows 10 或更高版本
- ✅ **Android**: Android 5.0 (API 21) 或更高版本
- ✅ **iOS**: iOS 13.0 或更高版本。注意：Flutter Xcode 工程中的 `IPHONEOS_DEPLOYMENT_TARGET` 仍为 `12.0`，但 CI 构建出的 Tim2Tox FFI 库使用 `-miphoneos-version-min=13.0`，生成的 framework `Info.plist` 也设置 `MinimumOSVersion=13.0`（详见 `tool/ci/build_tim2tox.sh`）。运行时的实际最低版本为 13.0。

### 设备类型

- ✅ **桌面**: 完整支持，包括窗口管理、系统托盘等功能
- ✅ **平板**: 响应式布局，自适应 UI
- ✅ **手机**: 响应式布局，移动端优化 UI

## 平台特定配置

### macOS

#### 构建要求

- Xcode 14.0 或更高版本（与 Flutter 3.29 工具链匹配）
- macOS SDK 10.15 或更高版本
- Homebrew（用于安装 libsodium）
- CMake 3.16 或更高版本

#### 安装依赖

```bash
brew install libsodium cmake
```

#### 构建

```bash
flutter build macos --release
```

#### 权限配置

在 `macos/Runner/DebugProfile.entitlements` 和 `macos/Runner/Release.entitlements` 中：

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

#### 原生库路径

- FFI 库: `libtim2tox_ffi.dylib`
- 位置: 应用 bundle 的 `Contents/MacOS/` 目录
- 依赖: `libsodium.dylib`（通过 Homebrew 安装）

### Linux

#### 构建要求

- CMake 3.16 或更高版本
- GTK3 开发库
- pkg-config
- libsodium 开发库

#### 安装依赖

**Ubuntu/Debian**:
```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  cmake \
  pkg-config \
  libgtk-3-dev \
  libsodium-dev
```

**Fedora/RHEL**:
```bash
sudo dnf install -y \
  gcc-c++ \
  cmake \
  pkg-config \
  gtk3-devel \
  libsodium-devel
```

#### 构建

```bash
flutter build linux --release
```

#### 原生库路径

- FFI 库: `libtim2tox_ffi.so`
- 位置: 可执行文件目录或 `lib/` 子目录
- 依赖: `libsodium.so`（系统库）

#### 运行时要求

- GTK3 运行时库
- libsodium 运行时库

### Windows

#### 构建要求

- Visual Studio 2019 或更高版本（包含 C++ 工具）
- CMake 3.16 或更高版本
- Windows 10 SDK
- WiX Toolset v3（用于通过 CPack 打包 `.msi`）

#### 安装依赖

**使用 vcpkg**（推荐）:
```bash
vcpkg install libsodium:x64-windows
```

**或手动安装**:
- 下载 libsodium 预编译库
- 配置环境变量或 CMake 路径

#### 构建

```bash
flutter build windows --release
```

#### 原生库路径

- FFI 库: `tim2tox_ffi.dll`
- 位置: 可执行文件目录
- 依赖: `libsodium.dll`（通过 vcpkg 或手动安装）

#### 运行时要求

- Visual C++ Redistributable（如果使用动态链接）

### Android

#### 构建要求

- Android SDK
- Android NDK
- Gradle

#### 安装依赖

原生库依赖通过 Gradle 和 CMake 自动处理。

#### 构建

```bash
flutter build apk --release
# 或
flutter build appbundle --release
```

#### 原生库路径

- FFI 库: `libtim2tox_ffi.so`
- 位置: `app/src/main/jniLibs/` 或通过 CMake 构建
- 架构: arm64-v8a, armeabi-v7a, x86, x86_64

#### 权限配置

在 `android/app/src/main/AndroidManifest.xml` 中：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### iOS

#### 构建要求

- Xcode 14.0 或更高版本
- iOS SDK 13.0 或更高版本（FFI 库基于 13.0 SDK 构建；参见 [操作系统](#操作系统)）
- CocoaPods

#### 安装依赖

```bash
cd ios
pod install
```

#### 构建

```bash
flutter build ios --release
```

#### 原生库路径

- FFI 库: `tim2tox_ffi.framework` 或 `libtim2tox_ffi.dylib`
- 位置: 应用 bundle 的 `Frameworks/` 目录
- 依赖: 通过 CocoaPods 管理

#### 权限配置

在 `ios/Runner/Info.plist` 中：

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

## 响应式布局

应用根据屏幕尺寸自动调整布局：

### 断点定义

- **Mobile**: < 600px 宽度
- **Tablet**: 600px - 1024px 宽度
- **Desktop**: > 1024px 宽度

### 布局模式

#### Mobile（手机）

- 单列布局
- 底部导航栏
- 抽屉式侧边栏（通过汉堡菜单访问）
- 全屏内容区域

#### Tablet（平板）

- 双列布局
- 可折叠侧边栏
- 更大的内容区域
- 优化的触摸目标

#### Desktop（桌面）

- 多列布局
- 固定侧边栏
- 最大宽度限制（1200px）
- 鼠标悬停效果

### 使用响应式工具

```dart
import 'package:toxee/util/responsive_layout.dart';

// 检查设备类型
if (ResponsiveLayout.isMobile(context)) {
  // 移动端逻辑
} else if (ResponsiveLayout.isTablet(context)) {
  // 平板逻辑
} else if (ResponsiveLayout.isDesktop(context)) {
  // 桌面逻辑
}

// 获取响应式值
final padding = ResponsiveLayout.responsivePadding(context);
final maxWidth = ResponsiveLayout.responsiveMaxWidth(context);
```

## FFI 库加载

### 加载策略

FFI 库按以下优先级顺序加载：

1. **可执行文件目录**: 首先尝试从可执行文件所在目录加载
2. **应用资源目录**: 然后尝试从应用资源目录加载
3. **系统库搜索路径**: 最后回退到系统库搜索路径

### 平台特定库名

- **macOS/iOS**: `libtim2tox_ffi.dylib`
- **Linux/Android**: `libtim2tox_ffi.so`
- **Windows**: `tim2tox_ffi.dll`

### 错误处理

如果库加载失败，应用会：

1. 记录详细错误信息到日志
2. 显示用户友好的错误消息
3. 提供故障排除建议

## 平台特定功能

### 桌面平台（macOS/Linux/Windows）

- ✅ 窗口管理（调整大小、最小化、最大化）
- ✅ 系统托盘（macOS/Windows/Linux）
- ✅ 全局快捷键（macOS/Windows）
- ✅ 文件系统访问

### 移动平台（Android/iOS）

- ✅ 触摸优化 UI
- ✅ 移动端导航模式
- ✅ 系统集成（通知、分享等）
- ✅ 权限管理

## 构建脚本

### 跨平台构建

使用 `build_all.sh` 脚本：

```bash
# 构建所有平台
./build_all.sh

# 构建特定平台
./build_all.sh --platform macos --platform linux

# 指定构建模式
./build_all.sh --mode release

# 清理后构建
./build_all.sh --clean
```

### 平台特定构建

**macOS**:
```bash
flutter build macos --release
```

**Linux**:
```bash
flutter build linux --release
```

**Windows**:
```bash
flutter build windows --release
```

**Android**:
```bash
flutter build apk --release
```

**iOS**:
```bash
flutter build ios --release
```

## 故障排除

### 库加载失败

**问题**: 应用启动时提示无法加载原生库

**解决方案**:
1. 确保原生库已正确构建
2. 检查库文件是否存在于正确位置
3. 验证库文件权限
4. 检查依赖库（如 libsodium）是否已安装

### 构建失败

**问题**: CMake 构建失败

**解决方案**:
1. 检查 CMake 版本（需要 >= 3.16，参见 [BUILD_AND_DEPLOY](../operations/BUILD_AND_DEPLOY.md)）
2. 验证所有依赖库已安装
3. 检查 CMake 配置路径
4. 查看构建日志获取详细错误信息

### UI 布局问题

**问题**: UI 在不同屏幕尺寸下显示异常

**解决方案**:
1. 检查是否使用了响应式布局工具
2. 验证断点设置是否正确
3. 测试不同设备尺寸
4. 检查媒体查询是否正确

### 权限问题

**问题**: 应用无法访问网络或文件系统

**解决方案**:
1. **macOS**: 检查 entitlements 文件配置
2. **Android**: 验证 AndroidManifest.xml 权限
3. **iOS**: 检查 Info.plist 配置
4. **Linux/Windows**: 通常无需特殊权限

## 已知问题和限制

### 平台特定限制

1. **Windows**: 
   - 某些功能可能需要管理员权限
   - 路径长度限制可能影响深层目录

2. **Linux**:
   - 不同发行版的库路径可能不同
   - GTK 主题可能影响 UI 外观

3. **Android**:
   - 需要处理不同架构（arm, x86）
   - 后台限制可能影响连接保持

4. **iOS**:
   - 需要代码签名才能运行
   - App Store 审核可能有额外要求

### 功能限制

- 某些高级功能可能在移动平台上受限
- 文件系统访问权限因平台而异
- 系统集成功能因平台而异

## 测试清单

### 桌面平台测试

- [ ] 应用启动和关闭
- [ ] 窗口管理功能
- [ ] 系统托盘功能
- [ ] 文件选择对话框
- [ ] 原生库加载
- [ ] 网络连接
- [ ] UI 响应式布局

### 移动平台测试

- [ ] 应用启动和关闭
- [ ] 触摸交互
- [ ] 屏幕旋转
- [ ] 权限请求
- [ ] 后台运行
- [ ] 通知功能
- [ ] UI 响应式布局

## 贡献指南

添加新平台支持时：

1. 更新 CMakeLists.txt 添加平台特定配置
2. 更新 FFI 加载器添加平台检测
3. 创建平台目录结构
4. 更新本文档添加平台说明
5. 添加测试用例

## 相关文档

- [toxee 架构](../architecture/ARCHITECTURE.md)
- [实现细节](./IMPLEMENTATION_DETAILS.md)
- [主 README](../../README.zh-CN.md)
