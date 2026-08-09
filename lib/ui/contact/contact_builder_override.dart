import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart'
    as contact_pkg;

// Re-export the app-bar-name override so callers in `home_page.dart` (and
// its `part of` files) only need to import this single override module.
export 'contact_app_bar_name_override.dart';

/// Capture+restore handle for toxee's contact-profile builder overrides.
///
/// We do not snapshot the prior builder closures. The upstream
/// `setBuilders(...)` is destructive (any slot not passed is nulled), and
/// each slot falls through to a hard-coded upstream default widget when
/// null. So `restore()` just calls `setBuilders()` with no args, which nulls
/// all slots and reverts the manager to upstream defaults — exactly the
/// state before any toxee override was applied. Capturing closures over
/// `manager.getXxx` would create a self-referential loop after restore (the
/// closure ends up dispatching back into itself via the manager) and
/// stack-overflow on the next access; this design avoids that.
class ContactBuilderOverrideHandle {
  ContactBuilderOverrideHandle._();

  static ContactBuilderOverrideHandle? _activeOwner;

  bool _restored = false;

  /// Captures the override scope. Call this before
  /// [contact_pkg.TencentCloudChatContactManager.builder.setBuilders].
  static ContactBuilderOverrideHandle capture() {
    final handle = ContactBuilderOverrideHandle._();
    _activeOwner = handle;
    return handle;
  }

  /// Restores the upstream defaults. Idempotent.
  void restore() {
    if (_restored) return;
    _restored = true;
    if (!identical(_activeOwner, this)) return;
    _activeOwner = null;
    contact_pkg.TencentCloudChatContactManager.builder.setBuilders();
  }
}
