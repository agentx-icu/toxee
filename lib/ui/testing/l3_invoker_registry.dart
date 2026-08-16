// L3 invoker registry - the typedefs, slots and (un)registration API for
// the live UI hooks a HomePage hands to the L3 debug tool surface.
//
// Split out of `l3_debug_tools.dart` (which is baselined in
// `tool/.complexity_baseline.txt`) so the registry can carry the ownership
// semantics documented on `_l3InvokerOwner` without pushing the tool file
// past its pin. This is a `part` rather than its own library on purpose:
// the `_l3*` slots are private to the library and are read directly by the
// tool handlers in `l3_debug_tools.dart`.

part of 'l3_debug_tools.dart';

/// S46/S47: the live auto-accept setter hook. `l3_set_setting` only writes
/// Prefs, but the inbound friend-application / group-invite listeners read a
/// CACHED HomePage flag (`_autoAcceptFriends` etc.) that a Prefs write does not
/// refresh — so the setting never takes effect mid-session. HomePage registers
/// this applier (gated) in `_initAfterSessionReady` and clears it on dispose;
/// it drives the SAME `_setAutoAcceptFriends`/`_setAutoAcceptGroupInvites` the
/// settings toggle uses (cached flag + Prefs + accept-pending side effect). When
/// present, `l3_set_setting` routes through it; otherwise it falls back to a
/// Prefs-only write (e.g. unit tests with no live HomePage).
typedef L3AutoAcceptApplier = Future<void> Function(String key, bool value);
L3AutoAcceptApplier? _l3AutoAcceptApplier;
typedef L3HomeShellApplier = Future<void> Function(String tab);
L3HomeShellApplier? _l3HomeShellApplier;
typedef L3OpenAddFriendDialogInvoker = Future<bool> Function();
L3OpenAddFriendDialogInvoker? _l3OpenAddFriendDialogInvoker;
typedef L3OpenAddGroupDialogInvoker = Future<bool> Function();
L3OpenAddGroupDialogInvoker? _l3OpenAddGroupDialogInvoker;
typedef L3OpenChatInvoker =
    Future<bool> Function({String? userId, String? groupId});
L3OpenChatInvoker? _l3OpenChatInvoker;
typedef L3OpenSelfProfileInvoker = Future<bool> Function();
L3OpenSelfProfileInvoker? _l3OpenSelfProfileInvoker;
typedef L3PopToRootInvoker = Future<bool> Function();
L3PopToRootInvoker? _l3PopToRootInvoker;
typedef L3OpenGlobalSearchInvoker = Future<bool> Function();
L3OpenGlobalSearchInvoker? _l3OpenGlobalSearchInvoker;
typedef L3OpenGroupAddMemberInvoker = Future<bool> Function(String groupId);
L3OpenGroupAddMemberInvoker? _l3OpenGroupAddMemberInvoker;
typedef L3OpenGroupMemberListInvoker = Future<bool> Function(String groupId);
L3OpenGroupMemberListInvoker? _l3OpenGroupMemberListInvoker;
typedef L3OpenGroupProfileInvoker = Future<bool> Function(String groupId);
L3OpenGroupProfileInvoker? _l3OpenGroupProfileInvoker;
typedef L3OpenConversationMenuInvoker =
    Future<bool> Function(String conversationId, {String? action});
L3OpenConversationMenuInvoker? _l3OpenConversationMenuInvoker;
typedef L3HomeShellSnapshotReader = Map<String, dynamic> Function();
L3HomeShellSnapshotReader? _l3HomeShellSnapshotReader;

/// Register (or clear, with null) the live auto-accept applier. No-op unless the
/// L3 test surface is enabled.
void registerL3AutoAcceptApplier(L3AutoAcceptApplier? fn) {
  if (kL3TestSurfaceEnabled) _l3AutoAcceptApplier = fn;
}

void registerL3HomeShellApplier(L3HomeShellApplier? fn) {
  if (kL3TestSurfaceEnabled) _l3HomeShellApplier = fn;
}

void registerL3OpenAddFriendDialogInvoker(L3OpenAddFriendDialogInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenAddFriendDialogInvoker = fn;
}

void registerL3OpenAddGroupDialogInvoker(L3OpenAddGroupDialogInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenAddGroupDialogInvoker = fn;
}

void registerL3OpenChatInvoker(L3OpenChatInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenChatInvoker = fn;
}

void registerL3OpenSelfProfileInvoker(L3OpenSelfProfileInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenSelfProfileInvoker = fn;
}

void registerL3PopToRootInvoker(L3PopToRootInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3PopToRootInvoker = fn;
}

void registerL3OpenGlobalSearchInvoker(L3OpenGlobalSearchInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGlobalSearchInvoker = fn;
}

void registerL3OpenGroupAddMemberInvoker(L3OpenGroupAddMemberInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGroupAddMemberInvoker = fn;
}

void registerL3OpenGroupMemberListInvoker(L3OpenGroupMemberListInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGroupMemberListInvoker = fn;
}

void registerL3OpenGroupProfileInvoker(L3OpenGroupProfileInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGroupProfileInvoker = fn;
}

void registerL3OpenConversationMenuInvoker(L3OpenConversationMenuInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenConversationMenuInvoker = fn;
}

void registerL3HomeShellSnapshotReader(L3HomeShellSnapshotReader? fn) {
  if (kL3TestSurfaceEnabled) _l3HomeShellSnapshotReader = fn;
}

/// The currently-registered home-shell snapshot reader, exposed so a HomePage's
/// dispose can identity-guard its unregister: a switch-back
/// (`pushAndRemoveUntil(HomePage)`) mounts the NEW HomePage (which re-registers)
/// BEFORE the old one disposes, so an unconditional `register…(null)` on dispose
/// would clobber the new instance's reader and leave the dump's `homeShellTab`
/// null after every switch (breaking `_settingsTabActive`/settings nav).
L3HomeShellSnapshotReader? get currentL3HomeShellSnapshotReader =>
    _l3HomeShellSnapshotReader;

L3OpenAddGroupDialogInvoker? get currentL3OpenAddGroupDialogInvoker =>
    _l3OpenAddGroupDialogInvoker;

L3OpenGroupProfileInvoker? get currentL3OpenGroupProfileInvoker =>
    _l3OpenGroupProfileInvoker;

L3PopToRootInvoker? get currentL3PopToRootInvoker => _l3PopToRootInvoker;

/// Monotonic ownership token for the L3 invoker slots that a HomePage registers
/// as a SET (auto-accept / home-shell / add-friend / open-chat / self-profile /
/// group add-member / group member-list).
///
/// Same hazard the `currentL3…` identity getters above exist for, but applied to
/// the whole set at once: a HomePage REMOUNT — `pushAndRemoveUntil(HomePage)`,
/// and on mobile the harness's `forceHomeRoot` recovery — mounts the NEW
/// HomePage (which re-registers every slot) BEFORE the old one disposes. An
/// unconditional `register…(null)` in the old instance's dispose bag therefore
/// clobbers the LIVE invokers, and every later `l3_open_*` call fails with
/// `invoker_not_registered` for the rest of the process.
///
/// Contract: a HomePage calls [beginL3InvokerRegistration] once, immediately
/// before registering the set, and passes the returned token to
/// [clearL3InvokersIfOwner] from its dispose bag. A stale token (a newer
/// HomePage has registered since) clears nothing.
int _l3InvokerOwner = 0;

/// Claim ownership of the L3 invoker slot set; see [_l3InvokerOwner].
int beginL3InvokerRegistration() => ++_l3InvokerOwner;

/// Clear the L3 invoker slot set, but ONLY if [token] is still the live owner.
void clearL3InvokersIfOwner(int token) {
  if (!kL3TestSurfaceEnabled || token != _l3InvokerOwner) return;
  _l3AutoAcceptApplier = null;
  _l3HomeShellApplier = null;
  _l3OpenAddFriendDialogInvoker = null;
  _l3OpenChatInvoker = null;
  _l3OpenSelfProfileInvoker = null;
  _l3OpenGroupAddMemberInvoker = null;
  _l3OpenGroupMemberListInvoker = null;
}
