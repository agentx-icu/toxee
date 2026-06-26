// Windows-only: force the Flutter engine to re-size its render surface to the
// real window client area, by issuing a real WM_SIZE through user32
// `SetWindowPos` (grow then restore). window_manager's hidden-create →
// setBounds → show sequence can leave the engine's swapchain sized to the
// pre-show window metrics on a HiDPI/VM guest (observed live on Parallels: a
// large black band above the UI). `windowManager.setSize` does NOT retrigger
// the engine re-surface here.
//
// CRITICAL: the resize is performed from a BACKGROUND ISOLATE (a separate OS
// thread). A SetWindowPos issued from the window's OWN (UI) thread is processed
// synchronously/reentrantly and was verified live to NOT re-surface the engine,
// whereas one issued from a DIFFERENT thread is POSTED to the window's message
// queue and processed by the normal message loop — which is exactly how the
// proven external (scheduled-task) repro worked. So we replicate that: find the
// window on the main isolate-thread is unnecessary; the worker does everything
// on its own thread. Safe no-op on non-Windows.
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../util/logger.dart';

// --- user32 / kernel32 signatures -------------------------------------------
typedef _FindWindowExNative =
    IntPtr Function(IntPtr parent, IntPtr after, Pointer<Utf16> cls,
        Pointer<Utf16> title);
typedef _FindWindowExDart =
    int Function(int parent, int after, Pointer<Utf16> cls,
        Pointer<Utf16> title);

typedef _GetWindowThreadProcessIdNative =
    Uint32 Function(IntPtr hwnd, Pointer<Uint32> pid);
typedef _GetWindowThreadProcessIdDart =
    int Function(int hwnd, Pointer<Uint32> pid);

typedef _GetCurrentProcessIdNative = Uint32 Function();
typedef _GetCurrentProcessIdDart = int Function();

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

typedef _GetWindowRectNative = Int32 Function(IntPtr hwnd, Pointer<_Rect> r);
typedef _GetWindowRectDart = int Function(int hwnd, Pointer<_Rect> r);

typedef _SetWindowPosNative =
    Int32 Function(IntPtr hwnd, IntPtr after, Int32 x, Int32 y, Int32 cx,
        Int32 cy, Uint32 flags);
typedef _SetWindowPosDart =
    int Function(int hwnd, int after, int x, int y, int cx, int cy, int flags);

const int _swpNoMove = 0x0002;
const int _swpNoZOrder = 0x0004;
const int _swpNoActivate = 0x0010;
const int _swpFlags = _swpNoMove | _swpNoZOrder | _swpNoActivate;

// The Flutter Win32 runner's top-level window class (see
// windows/runner/win32_window.cpp kWindowClassName).
const String _kFlutterWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// Grow the window by [delta] px then restore it, forcing a real WM_SIZE so the
/// Flutter engine re-creates its render surface at the true client size. Runs
/// the user32 calls on a background isolate (separate thread) so the WM_SIZE is
/// POSTED to the UI thread's message loop (the only variant that re-surfaces the
/// engine). Must be called AFTER the first frame; the caller delays. Safe no-op
/// on non-Windows and on any failure.
Future<void> nudgeWindowsRenderSurface({int delta = 20}) async {
  if (!Platform.isWindows) return;
  try {
    final result = await Isolate.run(() => _resurfaceWorker(delta));
    AppLogger.info('Window re-surface nudge: $result');
  } catch (e) {
    AppLogger.warn('Window re-surface nudge failed: $e');
  }
}

/// Runs on a background isolate's thread. Finds THIS process's top-level Flutter
/// window (by class + current pid, so a second toxee instance can't be nudged by
/// mistake) and issues the grow/restore SetWindowPos pair. Returns a short
/// diagnostic string. Self-contained (no shared state) so it is isolate-safe.
String _resurfaceWorker(int delta) {
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');

  final findWindowEx = user32.lookupFunction<_FindWindowExNative,
      _FindWindowExDart>('FindWindowExW');
  final getWindowThreadProcessId = user32.lookupFunction<
      _GetWindowThreadProcessIdNative,
      _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
  final getCurrentProcessId = kernel32.lookupFunction<
      _GetCurrentProcessIdNative, _GetCurrentProcessIdDart>(
      'GetCurrentProcessId');
  final getWindowRect = user32
      .lookupFunction<_GetWindowRectNative, _GetWindowRectDart>(
          'GetWindowRect');
  final setWindowPos = user32
      .lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');

  final myPid = getCurrentProcessId();
  final clsPtr = _kFlutterWindowClass.toNativeUtf16();
  final pidOut = calloc<Uint32>();
  final rectPtr = calloc<_Rect>();
  try {
    var hwnd = 0;
    var found = 0;
    while (true) {
      hwnd = findWindowEx(0, hwnd, clsPtr, nullptr);
      if (hwnd == 0) break;
      getWindowThreadProcessId(hwnd, pidOut);
      if (pidOut.value == myPid) {
        found = hwnd;
        break;
      }
    }
    if (found == 0) return 'own Flutter window not found (pid=$myPid)';
    if (getWindowRect(found, rectPtr) == 0) return 'GetWindowRect failed';
    final cx = rectPtr.ref.right - rectPtr.ref.left;
    final cy = rectPtr.ref.bottom - rectPtr.ref.top;
    if (cx <= 0 || cy <= 0) return 'bad rect ${cx}x$cy';
    setWindowPos(found, 0, 0, 0, cx + delta, cy + delta, _swpFlags);
    sleep(const Duration(milliseconds: 300));
    setWindowPos(found, 0, 0, 0, cx, cy, _swpFlags);
    return 'applied hwnd=$found ${cx}x$cy +$delta then restore';
  } finally {
    calloc.free(clsPtr);
    calloc.free(pidOut);
    calloc.free(rectPtr);
  }
}
