#!/bin/bash

# Cross-platform build script for toxee
# This script builds the application for all supported platforms

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter is not installed or not in PATH"
    exit 1
fi

print_info "Flutter version: $(flutter --version | head -n 1)"

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Build tim2tox native library first
print_info "Building tim2tox native library..."
TIM2TOX_DIR="$SCRIPT_DIR/third_party/tim2tox"
if [ -d "$TIM2TOX_DIR" ]; then
    # Ensure tim2tox submodules (e.g. c-toxcore) are initialized
    if [ -f "$TIM2TOX_DIR/.gitmodules" ] && { [ -d "$TIM2TOX_DIR/.git" ] || [ -f "$TIM2TOX_DIR/.git" ]; }; then
        print_info "Initializing tim2tox submodules (c-toxcore)..."
        (cd "$TIM2TOX_DIR" && git submodule update --init --recursive)
    fi
    cd "$TIM2TOX_DIR"
    if [ -f "build_ffi.sh" ]; then
        ./build_ffi.sh
    elif [ -f "build.sh" ]; then
        print_warn "build_ffi.sh not found in tim2tox, falling back to build.sh"
        print_warn "Note: build.sh does NOT produce libtim2tox_ffi (no toxav, no FFI shim)."
        ./build.sh
    else
        print_warn "Neither build_ffi.sh nor build.sh found in tim2tox, skipping native library build"
        print_warn "Please build tim2tox manually before building the Flutter app"
    fi
    cd "$SCRIPT_DIR"
else
    print_warn "tim2tox directory not found, skipping native library build"
fi

# Parse command line arguments
BUILD_MODE="release"
PLATFORMS=""
CLEAN=false
SKIP_BOOTSTRAP=false
FORCE_PUB_GET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            BUILD_MODE="$2"
            shift 2
            ;;
        --platform)
            PLATFORMS="$PLATFORMS $2"
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        --force-pub-get)
            FORCE_PUB_GET=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mode MODE          Build mode: debug, profile, or release (default: release)"
            echo "  --platform PLATFORM  Build for specific platform: macos, linux, windows, android, ios"
            echo "                       Can be specified multiple times. If not specified, builds for all available platforms."
            echo "  --clean              Clean build before building"
            echo "  --skip-bootstrap     Skip dart run tool/bootstrap_deps.dart"
            echo "  --force-pub-get      Force flutter pub get even when pubspec.lock is fresh"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Bootstrap dependencies (submodules, vendor SDK, overrides).
# bootstrap_deps.dart is itself cache-aware; --skip-bootstrap is just a fast-path
# when the caller knows the SDK/patches/submodules haven't changed.
if [ "$SKIP_BOOTSTRAP" = false ]; then
    print_info "Bootstrapping dependencies..."
    dart run tool/bootstrap_deps.dart
fi

# Clean if requested
if [ "$CLEAN" = true ]; then
    print_info "Cleaning build..."
    flutter clean
fi

# Get dependencies only when the lock file is missing or older than the spec files.
# Saves 1-3 minutes on hot dev loops where dependencies haven't changed.
need_pub_get=false
if [ "$FORCE_PUB_GET" = true ] || [ "$CLEAN" = true ]; then
    need_pub_get=true
elif [ ! -f pubspec.lock ]; then
    need_pub_get=true
elif [ pubspec.yaml -nt pubspec.lock ]; then
    need_pub_get=true
elif [ -f pubspec_overrides.yaml ] && [ pubspec_overrides.yaml -nt pubspec.lock ]; then
    need_pub_get=true
fi
if [ "$need_pub_get" = true ]; then
    print_info "Getting Flutter dependencies..."
    flutter pub get
else
    print_info "Flutter dependencies up to date — skipping pub get."
fi

# Determine which platforms to build
if [ -z "$PLATFORMS" ]; then
    # Build for all available platforms
    PLATFORMS="macos linux windows android ios"
    print_info "Building for all available platforms: $PLATFORMS"
else
    print_info "Building for specified platforms: $PLATFORMS"
fi

# Build for each platform
for PLATFORM in $PLATFORMS; do
    print_info "Building for $PLATFORM ($BUILD_MODE)..."
    
    case $PLATFORM in
        macos)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                flutter build macos --$BUILD_MODE
                print_info "macOS build completed"
            else
                print_warn "Skipping macOS build (not on macOS)"
            fi
            ;;
        linux)
            flutter build linux --$BUILD_MODE
            print_info "Linux build completed"
            ;;
        windows)
            if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
                flutter build windows --$BUILD_MODE
                print_info "Windows build completed"
            else
                print_warn "Skipping Windows build (not on Windows)"
            fi
            ;;
        android)
            flutter build apk --$BUILD_MODE
            print_info "Android build completed"
            ;;
        ios)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                flutter build ios --$BUILD_MODE --no-codesign
                print_info "iOS build completed (unsigned)"
            else
                print_warn "Skipping iOS build (not on macOS)"
            fi
            ;;
        *)
            print_error "Unknown platform: $PLATFORM"
            ;;
    esac
done

print_info "Build process completed!"

