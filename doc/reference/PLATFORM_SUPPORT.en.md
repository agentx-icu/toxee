# toxee Platform Support
> Language: [Chinese](PLATFORM_SUPPORT.md) | [English](PLATFORM_SUPPORT.en.md)


This document details toxee's multi-operating system and multi-platform support.

## Supported platforms

### Operating system

- ✅ **macOS**: 10.15 or higher (matches `macos/Podfile` `platform :osx, '10.15'` and `MACOSX_DEPLOYMENT_TARGET = 10.15`)
- ✅ **Linux**: Supports mainstream distributions (Ubuntu 18.04+, Debian 10+, Fedora 30+, etc.)
- ✅ **Windows**: Windows 10 or higher
- ✅ **Android**: Android 5.0 (API 21) or higher
- ✅ **iOS**: iOS 13.0 or higher. Note: the Flutter Xcode project's `IPHONEOS_DEPLOYMENT_TARGET` is still `12.0`, but the Tim2Tox FFI library shipped by CI is built with `-miphoneos-version-min=13.0` and its generated framework `Info.plist` sets `MinimumOSVersion=13.0` (see `tool/ci/build_tim2tox.sh`). 13.0 is the effective runtime minimum.

### Device type

- ✅ **Desktop**: Full support, including window management, system tray and other functions
- ✅ **Tablet**: Responsive layout, adaptive UI
- ✅ **Mobile**: Responsive layout, mobile-optimized UI

## Platform specific configuration

### macOS

#### Build requirements

- Xcode 14.0 or higher (matches the Flutter 3.29 toolchain)
- macOS SDK 10.15 or higher
- Homebrew (for installing libsodium)
- CMake 3.16 or higher

#### Install dependencies

```bash
brew install libsodium cmake
```

#### Build

```bash
flutter build macos --release
```

#### Permission configuration

In `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

#### Native library path

- FFI library: `libtim2tox_ffi.dylib`
- Location: `Contents/MacOS/` directory of application bundle
- Dependencies: `libsodium.dylib` (installed via Homebrew)

### Linux

#### Build requirements

- CMake 3.16 or higher
- GTK3 development library
- pkg-config
- libsodium development library

#### Install dependencies

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

#### Build

```bash
flutter build linux --release
```

#### Native library path

- FFI library: `libtim2tox_ffi.so`
- Location: executable file directory or `lib/` subdirectory
- Dependency: `libsodium.so` (system library)

#### Runtime requirements

- GTK3 runtime library
- libsodium runtime library

### Windows

#### Build requirements

- Visual Studio 2019 or higher (includes C++ tools)
- CMake 3.16 or higher
- Windows 10 SDK
- WiX Toolset v3 (for `.msi` packaging via CPack)

#### Install dependencies

**Use vcpkg** (recommended):
```bash
vcpkg install libsodium:x64-windows
```

**Or install manually**:
- Download the libsodium precompiled library
- Configure environment variables or CMake path

#### Build

```bash
flutter build windows --release
```

#### Native library path

- FFI library: `tim2tox_ffi.dll`
- Location: executable file directory
- Dependencies: `libsodium.dll` (installed via vcpkg or manually)

#### Runtime requirements

- Visual C++ Redistributable (if using dynamic linking)

### Android

#### Build requirements

- Android SDK
- Android NDK
- Gradle

#### Install dependencies

Native library dependencies are automatically handled through Gradle and CMake.

#### Build

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

#### Native library path

- FFI library: `libtim2tox_ffi.so`
- Location: `app/src/main/jniLibs/` or build via CMake
- Architecture: arm64-v8a, armeabi-v7a, x86, x86_64

#### Permission configuration

In `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### iOS

#### Build requirements

- Xcode 14.0 or higher
- iOS SDK 13.0 or higher (the FFI library is built against the 13.0 SDK; see [Operating system](#operating-system))
- CocoaPods

#### Install dependencies

```bash
cd ios
pod install
```

#### Build

```bash
flutter build ios --release
```

#### Native library path

- FFI library: `tim2tox_ffi.framework` or `libtim2tox_ffi.dylib`
- Location: `Frameworks/` directory of application bundle
- Dependencies: managed through CocoaPods

#### Permission configuration

In `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

## Responsive layout

The app automatically adjusts its layout based on screen size:

### Breakpoint definition

- **Mobile**: < 600px width
- **Tablet**: 600px - 1024px width
- **Desktop**: > 1024px width

### Layout mode

#### Mobile

- Single column layout
- Bottom navigation bar
- Drawer sidebar (accessed via hamburger menu)
- Full screen content area

#### Tablet

- Dual column layout
- Collapsible sidebar
- Larger content area
- Optimized touch targets

#### Desktop

- Multi-column layout
- Fixed sidebar
- Maximum width limit (1200px)
- Mouseover effect

### Use responsive tools

```dart
import 'package:toxee/util/responsive_layout.dart';

// Check device type
if (ResponsiveLayout.isMobile(context)) {
  // Mobile logic
} else if (ResponsiveLayout.isTablet(context)) {
  // Tablet logic
} else if (ResponsiveLayout.isDesktop(context)) {
  // Desktop logic
}

// Get responsive value
final padding = ResponsiveLayout.responsivePadding(context);
final maxWidth = ResponsiveLayout.responsiveMaxWidth(context);
```

## FFI library loading

### Loading strategy

FFI libraries are loaded in the following priority order:

1. **Executable file directory**: First try to load from the directory where the executable file is located
2. **Application Resource Contents**: Then try to load from the application resource directory
3. **System library search path**: Finally fall back to the system library search path

### Platform specific library name

- **macOS/iOS**: `libtim2tox_ffi.dylib`
- **Linux/Android**: `libtim2tox_ffi.so`
- **Windows**: `tim2tox_ffi.dll`

### Error handling

If the library fails to load, the application will:

1. Record detailed error information to the log
2. Display user-friendly error messages
3. Provide troubleshooting suggestions

## Platform specific features

### Desktop platform (macOS/Linux/Windows)

- ✅ Window management (resize, minimize, maximize)
- ✅ System tray (macOS/Windows/Linux)
- ✅ Global shortcut keys (macOS/Windows)
- ✅ File system access

### Mobile platform (Android/iOS)

- ✅ Touch optimized UI
- ✅ Mobile navigation mode
- ✅ System integration (notifications, sharing, etc.)
- ✅Permission management

## Build script

### Cross-platform build

Use the `build_all.sh` script:

```bash
# Build for all platforms
./build_all.sh

# Build a specific platform
./build_all.sh --platform macos --platform linux

# Specify build mode
./build_all.sh --mode release

# Build after cleaning
./build_all.sh --clean
```

### Platform specific builds

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

## Troubleshooting

### Library loading failed

**Problem**: When the application starts, it prompts that the native library cannot be loaded.

**Solution**:
1. Make sure the native library is built correctly
2. Check whether the library file exists in the correct location
3. Verify library file permissions
4. Check whether dependent libraries (such as libsodium) are installed

### Build failed

**Issue**: CMake build fails.

**Solution**:
1. Check CMake version (requires >= 3.16 — see [BUILD_AND_DEPLOY](../operations/BUILD_AND_DEPLOY.en.md))
2. Verify that all dependent libraries are installed
3. Check CMake configuration path
4. Check the build log for detailed error information

### UI layout issues

**Issue**: UI displays abnormally in different screen sizes

**Solution**:
1. Check whether responsive layout tools are used
2. Verify that the breakpoint settings are correct
3. Test different device sizes
4. Check if the media query is correct

### Permission issues

**Issue**: App cannot access the network or file system

**Solution**:
1. **macOS**: Check entitlements file configuration
2. **Android**: Verify AndroidManifest.xml permissions
3. **iOS**: Check Info.plist configuration
4. **Linux/Windows**: Usually no special permissions required

## Known issues and limitations

### Platform specific restrictions

1. **Windows**:
   - Some features may require administrator rights
   - Path length limit may affect deep directories

2. **Linux**:
   - The library path may be different for different distributions
   - GTK themes may affect UI appearance

3. **Android**:
   - Need to handle different architectures (arm, x86)
   - Background restrictions may affect connection retention

4. **iOS**:
   - Requires code signing to run
   - App Store review may have additional requirements

### Functional limitations

- Some advanced features may be limited on mobile platforms
- File system access permissions vary by platform
- System integration capabilities vary by platform

## Test list

### Desktop platform testing

- [ ] Application startup and shutdown
- [ ] Window management function
- [ ] System tray function
- [ ] File selection dialog
- [ ] Native library loading
- [ ] Internet connection
- [ ] UI responsive layout

### Mobile platform testing

- [ ] Application startup and shutdown
- [ ] touch interaction
- [ ] screen rotation
- [ ] permission request
- [ ] Run in the background
- [ ] notification function
- [ ] UI responsive layout

## Contribution Guidelines

When adding new platform support:

1. Update CMakeLists.txt to add platform-specific configuration
2. Update FFI loader to add platform detection
3. Create the platform directory structure
4. Update this document to add platform description
5. Add test cases

## Related documents

- [toxee Architecture](../architecture/ARCHITECTURE.en.md)
- [Hybrid architecture](../architecture/HYBRID_ARCHITECTURE.en.md)
- [Build and deploy](../operations/BUILD_AND_DEPLOY.en.md)
- [Implementation details](./IMPLEMENTATION_DETAILS.en.md)
- [Main README](../../README.md)