# Location sharing and People Nearby — implementation plan (v1)

Status: plan, 2026-10-17, **r7** (r0 → 24 codex findings, r1 → 12, r2 → 5,
r3 → 4, r4 → 3, r5 → 1, r6 → 1; all addressed, see §9–§15). Branch `agentx/location-nearby-research`
(worktree `~/chat-uikit/toxee-location-nearby`). Companion research note:
`LOCATION_AND_NEARBY_RESEARCH.md` (feasibility, Option A/B/C trade-offs; not
repeated here). This plan implements **Option B** (DHT geocell rendezvous)
plus the location message and the settings switches, with no server.

Decisions taken by the product owner (2026-10-17): implement the server-less
design and accept its inherent limits (enumerable cells, unmoderated cells,
self-reported positions, coarse granularity). **Every step of the
implementation and every document change is codex-reviewed** (owner
instruction later the same day; the earlier "plan only" rule is withdrawn).

## 1. Scope

In v1:

- **F1 Location message.** Send my current device position to a friend or a
  group as a `V2TIM_ELEM_TYPE_LOCATION` message; render received location
  messages with a real bubble (label, coordinates, *Open in Maps*, copy).
- **F2 Settings.** Two account-scoped switches, both default **off**:
  *Location* (master; gates everything that reads the OS position) and
  *Visible to people nearby* (enabled only while the master is on).
- **F3 People nearby.** While visible, join the NGC rendezvous group(s) of
  my geocell, broadcast a coarse presence record, list the other members
  with a coarse distance, and send a friend-request *intent* to one of
  them; the receiver accepts by sending a Tox friend request that carries
  a nonce; the initiator confirms with one tap.

Out of v1 (follow-ups in the research note): continuous live location of a
friend, LAN/mDNS and BLE proximity, pre-handshake proof-of-possession,
background operation, in-app tile maps.

## 2. Architecture summary

```
toxee (Dart)                      tim2tox (Dart)          tim2tox (C++)                    toxcore (fork)
───────────────────────────────── ─────────────────────── ──────────────────────────────── ────────────────────────
LocationSource (geolocator)
LocationSender / bubble ────────► Tim2ToxSdkPlatform ───► existing __location__ envelope (unchanged)
Settings switches (Prefs part)
GeocellPlanner ─┐
NearbyService ──┴ presence / intent (Dart crypto, `cryptography` pkg)
      │ opaque bytes + chat_id
      ▼
                                  RendezvousTransport ──► tim2tox_ffi_rendezvous_* ──► RendezvousGroups ──► tox_group_new_with_seed
                                  (rendezvous_* events,   (producer bridge stamps     (own mutex, own peer map,  tox_group_join
                                   instance-stamped)       the instance id)            isolated from V2TIM)     custom packets
Friend request: existing addFriend(address, message = nonce tag) / acceptFriendApplication(pubkey)
```

Rendezvous groups are **transport only**: tim2tox never exposes them as
V2TIM groups, never lists them, never persists them as known groups, never
routes their packets into history. toxee owns the nearby protocol and its
cryptography.

## 3. Wire formats and protocol (normative)

Protocol id: `toxee/nearby/v1`. Every constant below is part of it; changing
one is a protocol bump.

### 3.1 Geocells

- Geohash (base32, standard alphabet) of the device position.
- **Primary precision 5** (≈ 4.9 km × 4.9 km). **Overflow precision 6**.
- Join set = primary cell + each of the 8 neighbours whose nearest edge is
  within **750 m** of the position, capped at **4 cells** (closest edges
  first). Re-planned on every fix; a cell is left only after it has been
  outside the join set for **2 consecutive fixes** (hysteresis).
- Overflow: when a joined primary cell reports `full`, additionally join the
  precision-6 cell of the position **and stay in the primary cell** (toxcore
  keeps us if we were admitted; if the join itself failed with `full`, the
  primary cell is retried every 5 min while the 6-cell is active). Presence
  records list every cell the sender is in (`cells`), so a reader in either
  cell sees the same person once (deduplicated by `sk`).
- Fixes: on opening the nearby page, then every **60 s** or on a move of
  ≥ 100 m, foreground only. Nearby stops (leaves all cells, forgets peers)
  when the app is paused, the master or visibility switch goes off, the
  account is switched/torn down, or the nearby page has been closed for
  **5 min**.

### 3.2 Rendezvous group identity and lifecycle

- `seed = SHA-256("toxee/nearby/v1|" + cell)` (32 bytes =
  `crypto_sign_SEEDBYTES`, exposed as `TOX_GROUP_SEED_SIZE` in
  `tox_private.h`).
- Keypair = `create_extended_keypair_from_seed(seed)` (ed25519 from seed +
  the same ed25519→curve25519 conversions as `create_extended_keypair`);
  `chat_id = sig_pk`.
- Group name set by the founder: `"toxee-nearby/v1/" + cell` (≤ 48 bytes).
  Nick: 8 random lower-hex chars, never the user's name.
- Privacy `TOX_GROUP_PRIVACY_STATE_PUBLIC` (needed for DHT announces).
- **Join-or-found** per cell: `tox_group_join(chat_id, nick)`; if neither
  `self_join` nor a `peer_join` arrives within **30 s**, `tox_group_leave`
  and `tox_group_new_with_seed(seed, PUBLIC, name, nick)`. **Threading
  rule:** toxcore callbacks only record state and queue events; every Tox
  call that changes membership (join, found, leave, retry) runs from
  `RendezvousGroups::Tick()` on the event thread (`PostToEventThread`, the
  same deferral the self-kick path uses at `V2TIMManagerImpl.cpp:10687`),
  never from inside a toxcore callback. A founded group
  that later meets peers with another shared-state version converges
  however toxcore converges; we read nothing from shared state.
- **Everything the group says is ignored**: name, topic, roles, moderation
  events, password/privacy changes, peer names and statuses.
- **Cell health** (what replaces "peer_exit of self", which toxcore does not
  emit — `tox_callback_group_peer_exit` fires for *other* peers only):
  - a `moderation` event whose target is self with `KICK` → cell `kicked`;
  - `join_fail` (`PEER_LIMIT`, `INVALID_PASSWORD`, `UNKNOWN`) → cell
    `failed` (`PEER_LIMIT` also raises `full`);
  - a burst of `peer_exit` with `SELF_DISCONNECTED` for every peer → cell
    `disconnected`; we rely on toxcore's own reconnect for 90 s;
  - watchdog: a joined cell with **0 confirmed peers for 90 s** after having
    had peers, or still `connecting` 90 s after `self_join` was expected →
    `stale`.
  On `kicked` / `failed` / `stale`: the callback marks the cell; the next
  `Tick()` leaves, backs off **15 s**, and re-plans (join → found). Max **3 retries per cell per 10 min**, then the cell is marked
  `unavailable` for 10 min and the UI says so.

### 3.3 Group packet framing (tim2tox)

Framing moves out of `V2TIMManagerImpl.cpp` into a shared unit
`source/Tim2ToxGroupPacket.{h,cpp}` (`WrapTim2ToxGroupPacket`,
`UnwrapTim2ToxGroupPacket`, the kind enum, header size/version), used by
both `V2TIMManagerImpl` and `RendezvousGroups`. New kind
`kTim2ToxGroupPacketRendezvous = 4`, used for broadcast
(`tox_group_send_custom_packet`, lossless) and private
(`tox_group_send_custom_private_packet`, lossless). Payload opaque to
tim2tox. **One boundary everywhere: the complete frame (6-byte header +
payload) is ≤ 1200 bytes**, i.e. the payload handed to
`tim2tox_ffi_rendezvous_send` is ≤ 1194 bytes (toxcore's own limit is 1373
for the frame). tim2tox returns `-1` above that; toxee measures the frame
before calling. Kind 4 is accepted only in registered rendezvous groups;
in a rendezvous group every other kind is dropped; kind 4 elsewhere is
dropped. Drops are counted (`tim2tox_ffi_rendezvous_drop_count`).

Native per-sender budget (enforced in `RendezvousGroups` *before* any
event is queued): per (group, NGC peer key) at most **6 packets and
6 KiB per 10 s**; excess dropped and counted. Per group at most **60 peer
events per 10 s** (join/exit coalesced beyond that into one
`rendezvous_peers_changed` line).

### 3.4 Nearby records (toxee)

**Canonical JSON** (`nearby_canonical_json.dart`): objects with keys sorted
by byte value (keys are ASCII), no whitespace, strings escaped only for
`"`, `\`, and control chars < 0x20 (as `\u00XX`), all other code points as
raw UTF-8; **integers only** (no floats, no exponents, no `-0`); arrays
keep the order given below; booleans/null not used. Signatures are Ed25519
over the canonical bytes of the object with the `sig` key removed. Hex is
lower-case. Latitude/longitude travel as **integers in milli-degrees**
(`lat_e3`, `lon_e3`, i.e. rounded to ~111 m).

Presence (broadcast; sent on join, every **60 s**, on change, and once when
a `peer_join` is observed — the last one rate-limited to 1 per 10 s). The
sender sets `exp = now + 180`. Exact serialized form (keys in byte order,
`sig` therefore between `seq` and `sk`; the signature covers the same
object with the `sig` member removed; `avatar` is `""` when unset; `cells`
sorted lexicographically). The blocks below are **schematic**: the `…`
placeholders stand for hex strings of the stated length; the test suite
carries concrete vectors (`test/nearby/vectors/*.json`) produced by the
reference serializer and checked byte-for-byte.

```
{"avatar":"<64hex or empty>","cells":["wx4g0","wx4g1"],"ek":"<64hex>","exp":1760700000,"lat_e3":39905,"lon_e3":116391,"name":"Ann","seq":7,"sig":"<128hex>","sk":"<64hex>","t":"presence","v":1}
```

Intent (private packet), schematic serialized form (`from` is the sender's
**Ed25519 public key**; signature over the object without `sig`):

```
{"box":"<hex>","epk":"<64hex>","from":"<64hex>","n24":"<48hex>","sig":"<128hex>","t":"intent","to":"<64hex>","v":1}
```

**Byte decoding rule:** every hex field is decoded to raw bytes before it
is used in any cryptographic operation: `sk`, `ek`, `epk`, `to`, `from` →
32 bytes; `n24` → 24 bytes (the XChaCha20-Poly1305 nonce); `sig` → 64
bytes; `box` → ciphertext ‖ 16-byte Poly1305 tag (libsodium "combined"
layout, which is `SecretBox.cipherText + SecretBox.mac.bytes` in the
`cryptography` package). Hex is **strictly lower-case**: any upper-case
digit, odd length or non-hex character rejects the record (no
normalisation), so the bytes that were signed and the bytes that are
verified are always the same canonical text.

- `to` is the **recipient's X25519 public key**, i.e. the `ek` of the
  recipient's current presence record; the sender copies it from that
  record together with the recipient's `sk`. A pending intent tracks both
  (`target sk`, `target ek`); the recipient accepts an intent only if `to`
  equals its own current session `ek`, and the receiver-side binding check
  of §3.4 uses the (`sk`, `ek`) pair that the sending NGC peer key
  published in its presence (`from` must equal that `sk`).
- `key = HKDF-SHA256(ikm = X25519(epk_sk, bytes(to)), salt = bytes(n24), info = "toxee/nearby/v1/intent" (UTF-8), length 32)`.
- `aad` = the canonical bytes of the object
  `{"epk":"<epk>","from":"<from>","t":"intent","to":"<to>","v":1}` (the
  intent with `box`, `n24` and `sig` removed), i.e. literally
  `{"epk":"…","from":"…","t":"intent","to":"…","v":1}`.
- `box = XChaCha20-Poly1305(key, nonce = bytes(n24), aad, plaintext)`, emitted as hex of ciphertext ‖ tag.
- plaintext = canonical `{"addr":"<76hex>","exp":<unix s>,"msg":"<text>","n":"<32hex>"}`
  with `msg` ≤ 140 code points **and** ≤ 280 UTF-8 bytes; the sender sets
  `exp = now + 600`.
- The complete frame (6-byte header + intent JSON) is measured **before**
  sending; > 1200 bytes → the UI shortens `msg` or refuses.

**Accept** = the Tox friend request itself:
`tox_friend_add(addr, "toxee-nearby:" + n + " " + msg)`.

**Validation (receiver side):**

| Check | Presence | Intent |
|---|---|---|
| Signature | under `sk` | under `from` |
| Expiry | sender `now+180`; receiver accepts `now-60 < exp ≤ now+240` | sender `now+600`; receiver accepts inner `now < exp ≤ now+900` |
| Freshness | `seq` > last seen for `sk` | `n` not in consumed set |
| Sender binding | first record binds (`sk`, `ek`) ↔ NGC peer key for the session; a different pair from the same peer key is allowed at most 3 times / 10 min (then dropped) | accepted only if `from` == the `sk` currently bound to the sending NGC peer key **and** `to` == my current `ek` |
| Rate | 1 record / 10 s per NGC peer key | 3 intents / h per NGC peer key; 5 sent intents / h locally |
| Size | frame ≤ 1200 bytes | frame ≤ 1200 bytes, `msg` bounds above |

All rate keys are the **toxcore-authenticated NGC peer key** (the only
identity a stranger cannot rotate for free within a connection), never the
self-chosen `sk`. The address-to-sender binding is not proven (accepted
limit, research note §3); the one-tap confirm shows the requester's 64-hex
public key.

**Initiator side:** pending intent = `{n, exp, target sk, target ek, card snapshot}`;
on a friend application whose `addWording` starts with `toxee-nearby:` and
whose `n` matches a pending, unexpired intent → consume `n`, show the
confirm card (name snapshot + sender public key) → confirm calls the
existing `acceptFriendApplication(pubkey)`. If the account's
*auto-accept friends* preference is on, the existing native gate accepts
every request first, including this one, and the card is informational.
Expired/unknown nonces leave the application as an ordinary one. Consumed
nonces are kept until `exp`. Pending intents are cancelled by *rotate my
Tox ID*, by stop, and by account switch.

Local block list: `sk` (session) and Tox public key (existing persisted
list).

## 4. Changes by layer

### 4.1 toxcore — new fork `agentx-icu/c-toxcore`, branch `agentx/group-new-with-seed`, base `v0.2.23-rc.1`

| File | Change |
|---|---|
| `toxcore/crypto_core.{h,c}` | `bool create_extended_keypair_from_seed(Extended_Public_Key*, Extended_Secret_Key*, const uint8_t seed[crypto_sign_SEEDBYTES])`; `create_extended_keypair` becomes "draw seed, call it, memzero" |
| `toxcore/group_chats.{h,c}` | `gc_group_add` → thin wrapper over new `gc_group_add_with_seed(..., const uint8_t *seed /*nullable*/)`; keypair step uses the seed when non-null; nothing else changes |
| `toxcore/tox_private.{h,c}` | `#define TOX_GROUP_SEED_SIZE 32`; `Tox_Group_Number tox_group_new_with_seed(Tox*, Tox_Group_Privacy_State, const uint8_t group_name[], size_t, const uint8_t name[], size_t, const uint8_t seed[TOX_GROUP_SEED_SIZE], Tox_Err_Group_New*)` with the same `tox_lock/unlock` discipline and error mapping as `tox_group_new` in `tox.c`; `seed == NULL` → `TOX_ERR_GROUP_NEW_INIT` |
| `auto_tests/group_seeded_test.c`, `auto_tests/CMakeLists.txt` (`auto_test(group_seeded)`), `auto_tests/Makefile.inc` | two `Tox` instances, same seed → equal `tox_group_get_chat_id`; different seeds → different; `tox_group_new` stays random (two calls differ); `NULL` seed → `INIT` error. No network |

Upstream PR to `TokTok/c-toxcore` with the same commit; toxee does not wait.

### 4.2 tim2tox — C++

Files: `source/Tim2ToxGroupPacket.{h,cpp}` (new, extracted),
`source/RendezvousGroups.{h,cpp}` (new, ≤ 500 LOC), `source/CMakeLists.txt`
(`TIM2TOX_CORE_SRCS` += both), `source/V2TIMManagerImpl.{h,cpp}`,
`source/V2TIMGroupManagerImpl.cpp`, `source/ToxManager.{h,cpp}`.

- `ToxManager::createGroupWithSeed(seed, privacy, name, nick, err)` and
  `getGroupPeerPublicKey` (exists), `getGroupName` (exists), `deleteGroup`
  (exists, = leave).
- **`RendezvousGroups`** (member of `V2TIMManagerImpl`, **own**
  `rendezvous_mutex_`, never held across a ToxManager call):
  - registry `{group_number → {chat_id, cell, state, peers: peer_id → pk,
    budgets, timers}}`; `Owns(group_number)` is lock-free-cheap (atomic
    snapshot of the group-number set) for the hot callback path;
  - `JoinOrFound(seed, name, nick)`, `Leave(chat_id)`, `LeaveAll()`,
    `SendBroadcast(chat_id, bytes)`, `SendPrivate(chat_id, peer_pk, bytes)`
    (peer id from the **own peer map**, filled in `OnPeerJoin` via
    `tox_group_peer_get_public_key` — no `ResolveGroupPeerIdForKey`),
    `PeerCount(chat_id)`, `Tick()` (30 s join→found, 90 s watchdog, back-offs;
    driven from the existing iterate timer);
  - call pattern for every Tox call: copy what is needed under
    `rendezvous_mutex_` → unlock → `AcquireToxSession()` pin → call →
    re-lock to record the result (mirrors `V2TIMManagerImpl.cpp:2228-2242`).
- **Isolation at the callback layer.** Every ToxManager group callback
  lambda registered in `V2TIMManagerImpl` — the pre-`initialize()` block
  (`V2TIMManagerImpl.cpp:905-935`: message, custom_packet,
  custom_private_packet, private_message) **and** the post-init block
  (`:1050-1160`: self_join, join_fail, peer_join (+PeerConfirmed), peer_exit,
  peer_name, peer_status, topic, privacy_state, voice_state, moderation) —
  starts with
  `if (rendezvous_.Owns(group_number)) { rendezvous_.OnXxx(...); return; }`
  **before** any readiness bookkeeping. The **group invite** callback
  (`setGroupInviteGroupCallback`, `V2TIMManagerImpl.cpp:1174-1310`) has no
  group number yet; it drops the invite (log only, no listener, no
  auto-accept) when `invite_data_length ≥ 32` and the first 32 bytes — the
  chat_id, as toxcore packs it (`group_chats.c:7742, 7920`) — equal a
  registered rendezvous chat_id, or when `invited_group_name` carries the
  `toxee-nearby/v1/` prefix and the chat_id matches the derivation of
  §3.2. This happens before any of the ordinary readiness bookkeeping (`group_wire_readiness_`,
  `fresh_group_joins_`, `accepted_invites_`, `AnnounceGroupIdentities`).
  The same predicate guards `HandleGroupSelfJoin` (defence in depth, see
  restore below), `RejoinKnownGroups`, `AnnounceGroupIdentities`,
  `GetJoinedGroupList` (`V2TIMGroupManagerImpl.cpp:942-1125`, through a
  public `V2TIMManagerImpl::IsRendezvousGroupNumber`), and the member/peer
  caches. Conference (old API) handlers are unaffected.
- **Restore hygiene** (crash left rendezvous groups in savedata): in the
  init restore loop (`V2TIMManagerImpl.cpp:1106-1121`) a restored group is
  treated as rendezvous **only if** its name has the prefix **and** the
  cell parsed from the name is a valid geohash **and**
  `chat_id == create_extended_keypair_from_seed(SHA-256("toxee/nearby/v1|" + cell)).sig_pk`
  (the §3.2 literal; computed in-process, no toxcore API needed). In the
  init restore loop (plain code in `InitSDK`, not a callback) such groups
  are left inline and never registered. The same test runs in
  `HandleGroupSelfJoin`, which **is** reached from the toxcore self-join
  callback (`V2TIMManagerImpl.cpp:1131-1148`): there the group is only
  marked and the `tox_group_leave` is queued with `PostToEventThread` (as
  the self-kick path does at `:10687`), never issued inside the callback.
  A user group that merely has the same name fails the chat_id test and is
  untouched.
- **Save ordering and admission**: `RendezvousGroups` has its own
  admission flag `accepting_` (atomic). `UnInitSDK` first sets
  `accepting_ = false`, then runs `rendezvous_.LeaveAll()` through
  `RunOnEventThread<bool>` (the task returns `true` as an execution
  sentinel; inline when already on the event thread). `LeaveAll()` is
  idempotent and guarded by `rendezvous_mutex_`; when the call does not
  yield `true` (the 10 s cancellation, `V2TIMManagerImpl.h:517-552`, or an
  event loop that already exited from its catch block, `:2174-2214`),
  `UnInitSDK` calls `LeaveAll()` inline on its own thread — safe because
  `accepting_` is already false, toxcore is built with
  `experimental_thread_safety` and every Tox call goes through the
  ToxManager lock.
  **Lifecycle barrier for admitted operations** (a `ToxSessionGuard` pin
  does not block `UnInitSDK`, `V2TIMManagerImpl.h:344-356`): every
  rendezvous operation that follows the unlock → pin → Tox-call pattern
  increments an `inflight_` counter under `rendezvous_mutex_` before it
  unlocks and decrements it after it has recorded its result; `LeaveAll()`
  first waits (condition variable, bounded 5 s) for `inflight_ == 0`, then
  snapshots and leaves. The bounded wait is not the barrier; the
  **generation** is: `RendezvousGroups` keeps a `generation_` counter that
  `LeaveAll()` increments (under `rendezvous_mutex_`, before it snapshots)
  and `InitSDK` increments again when it re-enables `accepting_`. Every
  admitted operation captures, under `rendezvous_mutex_`, the generation
  **and the session epoch** it was admitted under (`GetSessionEpoch()`,
  `V2TIMManagerImpl.h:377-403`). The check happens **before** the Tox call
  as well as after: having obtained a pin with `AcquireToxSession()`, the
  operation compares the pin's session epoch with the captured one and
  calls `Expired()`; a mismatch drops the pin and records nothing — it never
  touches a later session's Tox instance. A multi-call sequence (join →
  found, or a send retry) rechecks `Expired()` between calls. After the
  call it re-locks and compares the generation: a mismatch means the
  operation outlived its session — it then leaves any group it just
  created or joined (same pin, if still valid) and records **nothing**. So
  a stale operation can never publish into a later session, whether or not
  the 5 s wait expired. The session
  epoch stamped on event lines (`enqueue_text_line_for_instance`) is the
  second guard on the Dart side. Either way the leaves are done, and every pending
  rendezvous timer/back-off is cleared, before `UnInitSDK` continues to
  `running_ = false` (`V2TIMManagerImpl.cpp:2270`),
  `closeAdmission()` and the final save (`:2315-2338`). `Tick()`, the
  callbacks' state recording and every FFI entry point return at once when
  `!accepting_`, so nothing queued (`:2174-2192`) can rejoin a cell during
  shutdown; `accepting_` is set true again by `InitSDK` after the restore
  loop. Entry points that pass the flag pin the session with
  `AcquireToxSession()`; a refused pin is a no-op return, never a retry. Periodic `PersistToxProfile` may
  still capture live rendezvous groups — covered by the restore test above
  (documented, not prevented). `ResetGroupSessionState` clears the
  registry.
- **Events**: `V2TIMManagerImpl::SetRendezvousEventSink(std::function<void(std::string)>)`;
  the FFI layer installs a sink that calls
  `G.simple_listener.enqueue_text_line_for_instance(GetInstanceIdFromManager(manager_impl), line)`
  (same producer-bridge pattern as the file-control callback,
  `tim2tox_ffi.cpp:1040-1075`), so lines are instance-stamped at the source
  and need no change in `event_line_parser.cpp`. The sink is installed in
  `tim2tox_ffi_init_with_path` (and the instance-scoped init) **before**
  `InitSDK` (`tim2tox_ffi.cpp:1993-1995`), so restore-time
  `rendezvous_left` lines are not lost; as a second guard the manager
  buffers up to 64 lines produced while no sink is installed and flushes
  them on install. Lines:
  - `rendezvous_joined:<chat_id>:<founded 0|1>`
  - `rendezvous_left:<chat_id>:<kicked|failed|stale|left|full>`
  - `rendezvous_peer:<chat_id>:<peer_pk>:<join|exit>`
  - `rendezvous_peers_changed:<chat_id>:<count>` (coalesced form)
  - `rendezvous_full:<chat_id>`
  - `rendezvous_packet:<chat_id>:<peer_pk>:<b|p>:<hex payload>`
  `text_queue::Classify` maps `rendezvous_packet:` to **kChat** (evictable),
  the control lines stay kState (bounded by the native budgets of §3.3).

### 4.3 tim2tox — FFI (`ffi/tim2tox_ffi.{h,cpp}`, `dart/lib/ffi/tim2tox_ffi.dart`)

```
int tim2tox_ffi_rendezvous_join(const unsigned char* seed32, const char* name, const char* nick); // 1 accepted (outcome via events), 0 not inited / bad args
int tim2tox_ffi_rendezvous_leave(const char* chat_id_hex);                                       // 1 left, 0 unknown
int tim2tox_ffi_rendezvous_leave_all(void);                                                      // number left, -1 not inited
int tim2tox_ffi_rendezvous_send(const char* chat_id_hex, const char* peer_pk_hex_or_null,
                                const unsigned char* data, int len);                             // 1 sent, 0 not sent, -1 too large, -2 unknown peer, -3 unknown group
int tim2tox_ffi_rendezvous_peer_count(const char* chat_id_hex);                                  // >= 0, -1 unknown
int tim2tox_ffi_rendezvous_drop_count(void);                                                     // cumulative native drops
int tim2tox_ffi_dht_announce_capable_count(void);                                                // tox_dht_get_num_closelist_announce_capable, -1 not inited
```

All act on the current instance (`IsCurrentInstanceInited()` /
`GetCurrentInstance()`), like `tim2tox_ffi_join_group`; auto_tests reach
them through `runWithInstance`. Dart bindings mirror the C types
(`Pointer<Uint8>`, `Pointer<Utf8>`, `Int32`). `abi_audit.py` + manual
width check.

### 4.4 tim2tox — Dart (`dart/lib/`)

- `dart/lib/service/rendezvous_transport.dart` (new): `join/leave/leaveAll/
  send/peerCount/dhtAnnounceCapable` and `Stream<RendezvousEvent>` parsed
  from the `rendezvous_*` lines. `FfiChatService`'s poll loop forwards
  those prefixes to the transport **before** the message branches (no
  history ingestion, no conversation side effects).
- **No `createLocationMessage` work on the platform.** On native the SDK
  builds the location message purely in Dart
  (`v2_tim_message_manager.dart:276-289` → `TIMMessageManager.createLocationMessage`,
  `tim_message_manager.dart:250-262`: `V2TimMessage` with `locationElem`
  and a temp id); only web routes to `TencentCloudChatSdkPlatform`, which
  toxee does not ship. `TencentCloudChatMessageDataTools.sendMessage`
  inserts the optimistic row and calls `sendMessage(id, …)`, which finds it
  in `messageData` and the existing branch at
  `tim2tox_sdk_platform.dart:6329` serialises it, for C2C and group alike
  (the same route stickers take). A test asserts this end to end with the
  fake platform.

### 4.5 toxee — app

New `lib/nearby/` (each file ≤ 500 LOC):

| File | Responsibility |
|---|---|
| `geohash.dart` | encode / decode / neighbours / bounds (pure Dart) |
| `geocell_planner.dart` | §3.1 join set, hysteresis, overflow; pure function `(fix, state) → plan` |
| `nearby_canonical_json.dart` | §3.4 serializer + property tests |
| `nearby_crypto.dart` | session keys (Ed25519 + X25519), sign/verify, HKDF, XChaCha20-Poly1305 box (via `cryptography`) |
| `nearby_records.dart` | codecs + the validation table of §3.4 |
| `nearby_service.dart` | state machine: planner ↔ transport, peer table, budgets, intents, nonce store, lifecycle hooks; `ChangeNotifier` |
| `nearby_friend_request.dart` | friend-application matching → confirm card → `acceptFriendApplication` |
| `location_source.dart` | `geolocator` wrapper: permission state, one fix, periodic fixes; Android `forceLocationManager: true` (no Play Services) |
| `location_permission_helper.dart` | request / explain / open-Settings flow; prompts on macOS and Linux too (does **not** reuse the call helper's desktop skip) |
| `location_sender.dart` | F1 send path: master check → permission → fix → `TencentImSDKPlugin.v2TIMManager.getMessageManager().createLocationMessage(...)` → `TencentCloudChatMessageDataTools.sendMessage(createdMessage:, userID:, groupID:)` (the same seam the UIKit message controller uses, `tencent_cloud_chat_message_controller.dart:156`: optimistic row + `sendMessageFinalPhase`) for **C2C and groups**; does not go through `_sendMedia`, whose group guard at `home_page.dart:791-794` stays |

Wiring (kept within the complexity pins — current headroom: `home_page.dart`
3 lines, `home_page_bootstrap.dart` 0, `prefs.dart` 3,
`settings_page_build.dart` 8 to the 500 limit, `settings_page.dart` 101,
`add_friend_dialog.dart` 30):

- **Desktop attachment option**: extract the whole
  `_buildDesktopInputOptions` (`home_page.dart:893-1031`) into
  `lib/ui/home/desktop_input_options.dart` (deliberate split) and add the
  *Location* item there; `home_page.dart` shrinks.
- **Mobile attachment option**: `buildToxeeMobileAttachmentOptions` gains
  `onLocation` + `locationLabel` + `locationEnabled` parameters; the
  `additionalAttachmentOptionsForMobile` closure body in
  `home_page_bootstrap.dart:638-660` moves into `mobile_attachment_policy.dart`
  (`buildToxeeMobileAttachmentClosure(...)`), so the bootstrap file loses
  lines rather than gaining them.
- **Bubble**: `lib/ui/widgets/location_message_bubble.dart`, returned from
  the existing `messageItemBuilder` override (`home_page_bootstrap.dart:776`)
  for `V2TIM_ELEM_TYPE_LOCATION` (a 3-line branch; the override's body is
  otherwise untouched). *Open in Maps*: `geo:lat,lon?q=lat,lon` (Android),
  `maps://?ll=lat,lon&q=label` (iOS/macOS), `https://www.openstreetmap.org/?mlat=&mlon=#map=16/lat/lon`
  (Linux/Windows); *Copy* copies `lat, lon`.
- **Prefs**: new part file `lib/util/prefs/location_prefs.dart`
  (`getLocationEnabled/setLocationEnabled`, `getNearbyVisible/setNearbyVisible`,
  account-scoped via `_scopedKey`, default `false`); `prefs.dart` gains one
  `part` line; `prefs_interfaces.dart` / `prefs_impl.dart` gain the four
  signatures.
- **Settings**: `SettingsPage` gains **optional** `locationEnabled`,
  `onLocationEnabledChanged`, `nearbyVisible`, `onNearbyVisibleChanged`
  (`settings_page.dart:168-194`; nullable, default `null` → the two rows are
  not built, so existing callers and tests compile unchanged; HomePage
  passes them); the two existing switch rows in
  `settings_page_build.dart` and the new two move together into
  `lib/ui/settings/settings_toggle_rows.dart` (desktop) and the mobile rows
  into `settings_page_mobile_widgets.dart` only if it stays ≤ 500 LOC,
  otherwise into `settings_mobile_toggle_rows.dart`. Keys
  `UiKeys.settingsLocationSwitch`, `UiKeys.settingsNearbyVisibleSwitch`.
  Master on → permission request; denial → revert + explain→Settings
  dialog; master off → `NearbyService.stop()` and nearby row disabled.
- **Ownership / teardown**: `NearbyController` is a process singleton with
  the `IrcAppManager` shape (`attach(service)` at HomePage bootstrap,
  `shutdownSession(service)` that stops nearby, cancels intents, removes
  the friendship listener and drops the service reference). Account
  teardown gets a new stage `AccountTeardownStage.nearbyShutdown`
  (`lib/util/account_teardown_failure.dart:9`) executed in
  `AccountService` **before** `serviceDisposal` (`account_service.dart:188`),
  mirroring `ircSessionShutdown`; HomePage `dispose` and
  `AppLifecycleState.paused` call `stop()` as well. The nearby page and
  `SettingsPage` read the singleton; nothing holds a service after
  `shutdownSession`.
- **Friend application hook**: a `V2TimFriendshipListener` is registered
  from `NearbyController.attach()` (called once next to the auto-accept
  load at `home_page_bootstrap.dart:1029`, one line) and removed on dispose.
- **Nearby entry**: `AddFriendDialog` gains an optional `onOpenNearby`
  callback (shown as a *People nearby* button when non-null); both callers
  (`home_page.dart:1980`, `home_page_bootstrap.dart:1133` →
  `_showAddFriendDialog`) pass it; the two `NewEntryButton` registrations
  are unchanged.
- **Nearby UI**: `lib/ui/nearby/nearby_page.dart` (peer cards: name, avatar
  placeholder, "~N m / km", status header: locating / joining / N people /
  DHT not ready when `dhtAnnounceCapable == 0` / cell unavailable),
  `nearby_confirm_card.dart`, `nearby_privacy_notice.dart` (shown once when
  visibility is first enabled). *Say hi* → message sheet (counter shows the
  byte budget) → intent. *Block* → session `sk` block + Tox pubkey block
  when known. *Rotate my Tox ID* → existing nospam rotation + cancel pending
  intents.

Platform plumbing:

- `pubspec.yaml`: `geolocator` (version from `flutter pub add` on the Mac);
  `msix_config.capabilities` += `location`.
- Android manifest: `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`; no
  foreground-service type.
- iOS: `NSLocationWhenInUseUsageDescription` in `Info.plist` + the six
  `ios/Runner/*.lproj/InfoPlist.strings`.
- macOS: `NSLocationUsageDescription` + `NSLocationWhenInUseUsageDescription`
  in `Info.plist` + the six `macos/Runner/*.lproj/InfoPlist.strings`;
  `com.apple.security.personal-information.location` in
  `DebugProfile.entitlements` and `Release.entitlements`.
- Linux: `geolocator_linux` (GeoClue over D-Bus, pure Dart); Windows:
  `geolocator_windows`.
- l10n: new keys in all seven ARB files; `arb_completeness_test` gate.
- Complexity: every touched pinned file ends ≤ its pin; splits above are
  the only new files from existing code; `--write-baseline` is used only to
  record shrinks.

### 4.6 Documentation

- toxee: `doc/reference/LOCATION_AND_NEARBY.md` + `.zh-CN.md`; §7 in
  `CALLING_AND_EXTENSIONS.md` + `.zh-CN.md`; rows in
  `MOBILE_DEVICE_FEATURES.md` + `.zh-CN.md` (P8 location permission,
  B-row "nearby pauses in background", N-row DHT announce traffic).
- tim2tox: `doc/architecture/RENDEZVOUS_GROUPS.md` + `.zh-CN.md`
  (isolation contract, events, FFI, budgets, restore rule),
  `README_BUILD*.md` (toxcore fork), `CLAUDE.md` layout lines.
- Plan docs English-only.

## 5. Tests

toxcore fork: `auto_tests/group_seeded_test.c` (registered, see 4.1).

tim2tox:
- gtest `test/Tim2ToxGroupPacketTest.cpp` (moved framing: wrap/unwrap,
  kind 4, size limits) and `test/RendezvousGroupsTest.cpp` (registry,
  `Owns`, budgets, coalescing, restore rule incl. prefix-collision with a
  wrong chat_id, event line formatting) — both added to `test/CMakeLists.txt`
  with `add_executable` + `gtest_discover_tests`; plus a source-regression
  check that every callback lambda in the list of 4.2 contains the
  `rendezvous_.Owns` guard.
- Dart `dart/test/rendezvous_transport_event_test.dart` (parsing, no
  history ingestion) — also listed in `PHASE14_UNIT` (Tier 1).
- auto_tests `scenario_rendezvous_group_test.dart` in **`PHASE4_GROUP`**
  (runs in Tier 2 CI, phases 1-10,12-14): A joins seed S → founds; B joins
  S → joins; B's broadcast reaches A; A's private packet reaches B only;
  peer events; `GetJoinedGroupList` excludes the group on both; B leaves →
  A sees exit; a saved profile containing a rendezvous group is loaded by
  a fresh instance and the group is left on init; flooding from B beyond
  the budget is dropped and counted; a second account on the same instance
  id does not receive A's events (session scoping).

toxee (`flutter test`):
- `test/nearby/`: `geohash_test`, `geocell_planner_test` (join set,
  hysteresis, overflow, cap 4), `nearby_canonical_json_test`,
  `nearby_crypto_test` (sign/verify, box round trip, tamper, wrong `to`),
  `nearby_records_test` (every row of the validation table, Unicode
  boundary of `msg` at 140 code points / 280 bytes / frame 1200 bytes,
  expiry bounds, replay, binding, rates), `nearby_service_test` (fake
  transport: join/found, peer table, intent → nonce → confirm, block,
  stop on pause / switch off / account switch, cancel on rotate),
  `nearby_friend_request_test`, `location_sender_test` (C2C and group,
  master off, permission denied).
- `test/location_message_bubble_test.dart` (renders at 320 pt, maps URL per
  platform, copy); `test/settings_location_switch_test.dart` (anchors,
  gating, revert on denial); prefs defaults in
  `account_toggle_persistence_test.dart`; `settings_anchor_test.dart` + the
  two keys; `android_call_manifest_test`-style checks for the new
  permission strings (manifest, both plists, entitlements, msix capability).

Gates: `flutter analyze lib tool test integration_test`,
`dart run tool/check_complexity.dart`, `python3 tool/check_source_contracts.py`,
`flutter test`, tim2tox gtest build (`-DTIM2TOX_BUILD_TESTS=ON`), Tier 1
(`RUN_VIRTUAL=1 ./run_tests_ordered.sh 1,3,12 14`) plus a local run of the
new phase-4 scenario, `abi_audit.py`, and a packaged Windows build for the
msix capability (on the Windows VM, see runbook memory).

## 6. Delivery order, review points, PRs

Each numbered step ends with a codex review of its diff before the next
starts.

1. toxcore fork + branch; local `build_ffi.sh`; gtest.
2. tim2tox `agentx/rendezvous-groups`: `.gitmodules` URL →
   `agentx-icu/c-toxcore`, gitlink → fork commit; framing extraction;
   `RendezvousGroups`; callback guards; FFI; Dart transport;
   `createLocationMessage`; tests. Push branch.
3. toxee `agentx/location-nearby` (this worktree, branch renamed): gitlink
   → tim2tox branch commit (staged immediately); F1 → F2 → F3 → platform
   plumbing → docs → tests; local gates.
4. toxee PR → CI green (`submodule_verify` needs step 2 pushed).
5. tim2tox PR → merge → re-pin toxee gitlink → CI → merge toxee.
6. Cleanup: remote branches and both worktrees; the toxcore fork stays.

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Two founders of one cell within 30 s | Shared state ignored; convergence covered by the phase-4 scenario; watchdog re-plans |
| Hostile founder locks / churns a cell | Back-off + `unavailable` state; UI explains |
| Rendezvous group leaks into the group list / history after a crash | chat_id-verified leave on restore + callback-layer guards + source-regression test |
| Flood from a cell member | Native per-peer budgets before the queue; `rendezvous_packet:` evictable; Dart rates on top |
| Presence / intent spoofing | Signatures, NGC-peer-key binding and rates; accepted limits documented |
| Address disclosure via intent | Consent sheet names the recipient; 5/h; rotate-ID cancels pending intents |
| Battery / data | Foreground only; 60 s fixes; ≤ 4 cells; idle stop |
| `geolocator` platform builds | Android `forceLocationManager`; macOS entitlement + strings; Windows msix `location`; Linux pure-Dart D-Bus; verified in `build-packages.yml` |
| Complexity ratchet | Splits listed in 4.5; new code only in new files |
| toxcore fork drift | Single additive private API; upstream PR; `README_BUILD` note |

## 8. Mobile checklist answers (`MOBILE_DEVICE_FEATURES.md`)

1 Size: lists/cards, widget-tested at 320 pt. 2 Safe areas: standard
scaffolds. 3 Large text: bubble wraps. 4 Lifecycle: nearby stops on pause
and on account switch; location message is one-shot. 5 Background: nothing
runs in background. 6 Audio / 7 Camera: n/a. 8 Permissions: new helper with
explain→Settings and revert; revocation mid-use ends nearby (P2 process
kill). 9 Network: NGC over relays as today. 10 Cross-platform peers: JSON
records, `__location__` envelope. 11 Single instance: unaffected.
12 Parity: shared Dart/C++; platform files are permission strings only.

## 9. r0 → r1 change log (codex findings)

| # | Finding (r0) | Resolution in r1 |
|---|---|---|
| B1 | `CRYPTO_SIGN_SEED_SIZE` does not exist | `crypto_sign_SEEDBYTES` internally, `TOX_GROUP_SEED_SIZE` in `tox_private.h` (4.1) |
| B2 | new sources/tests not in explicit CMake lists | `source/CMakeLists.txt` and `test/CMakeLists.txt` entries named (4.2, 5) |
| H1 | toxcore test unregistered | `auto_test(group_seeded)` + `Makefile.inc` (4.1) |
| H2 | wrong handler names, `HandleGroupPeerConfirmed` and callback-level readiness missed | guards moved to the callback lambdas, full list (4.2) |
| H3 | `GetJoinedGroupList` lives in `V2TIMGroupManagerImpl.cpp` | file added, predicate exposed (4.2) |
| H4 | self-kick not observable via peer_exit | cell-health model: moderation target self, join_fail, SELF_DISCONNECTED burst, watchdog (3.2) |
| H5 | framing helpers are `static` in `V2TIMManagerImpl.cpp` | extracted `Tim2ToxGroupPacket.{h,cpp}` (3.3) |
| H6 | lock inversion with `mutex_` / ToxManager | own mutex, snapshot→unlock→pin→call (4.2) |
| H7 | event lines carry no instance id | producer bridge via `SetRendezvousEventSink` + `enqueue_text_line_for_instance` (4.2) |
| H8 | `ResolveGroupPeerIdForKey` probes 0..255 and relies on a cache rendezvous does not fill | own peer map from `OnPeerJoin` (4.2) |
| H9 | name-prefix leave could hit a user group | chat_id re-derivation required (4.2) |
| H10 | save ordering / `ResetGroupSessionState` | `LeaveAll` before final save; registry cleared; periodic save covered by restore rule (4.2) |
| H11 | 140-char Unicode `msg` can exceed 1200/1373 | code-point and byte bounds, frame preflight (3.4) |
| H12 | canonical JSON / nonce / AAD underspecified | full serializer spec, integer-only numbers, HKDF salt, AAD (3.4) |
| H13 | unbounded `exp` | bounded windows for presence and intent (3.4) |
| H14 | `from` ambiguous; no sender binding | public key stated; binding to NGC peer key; rates keyed by NGC peer key (3.4) |
| H15 | queue flooding before Dart limits | native per-peer budgets; `rendezvous_packet:` classified kChat (3.3, 4.2) |
| H16 | `_sendMedia` rejects groups | dedicated `location_sender.dart` (4.5) |
| M1 | attachment/dialog seams lack callbacks | parameters and callers named; closure extraction (4.5) |
| M2 | `SettingsPage` props / ownership / teardown | props, `NearbyController`, teardown hooks (4.5) |
| H17 | complexity pins (`home_page` 3 lines headroom etc.) | explicit splits per file (4.5) |
| H18 | Windows msix `location`, macOS `InfoPlist.strings` | both added (4.5) |
| M3 | no FFI for announce-capable count | `tim2tox_ffi_dht_announce_capable_count` (4.3) |
| H19 | Tier 1 placement; missing tests | phase 4 + phase 14 placement; test list extended (5) |

## 10. r1 → r2 change log (codex findings)

| # | Finding (r1) | Resolution in r2 |
|---|---|---|
| H1 | canonical examples not canonical; avatar placeholder invalid | exact serialized forms with byte-ordered keys, `sig` in place, `""` avatar (3.4) |
| H2 | AAD had keys but no values | AAD = canonical bytes of `{epk,from,t,to,v}` with values, spelled out (3.4) |
| H3 | 1200-byte limit stated for payload and for frame | one boundary: frame ≤ 1200, payload ≤ 1194, FFI returns −1 (3.3) |
| H4 | leave/re-plan from inside callbacks | callbacks record only; `Tick()` on the event thread via `PostToEventThread` (3.2) |
| H5 | teardown ownership vs `HomeSessionController` / `account_service.dart:188` | `NearbyController` singleton, `nearbyShutdown` stage before `serviceDisposal` (4.5) |
| M1 | pre-init callback block not guarded | both blocks listed and guarded (4.2) |
| M2 | event sink installed after `InitSDK` | installed before `InitSDK` + 64-line buffer (4.2) |
| M3 | admission race around `running_` | `LeaveAll` before `running_=false`; entry points check `running_` + pin (4.2) |
| M4 | presence `exp` sender value missing | `exp = now + 180` (3.4) |
| M5 | restore seed literal | literal string used (4.2) |
| M6 | `createLocationMessage` vs `sendMessage` lookup | superseded in r3: native creation is pure Dart in the SDK; send through `TencentCloudChatMessageDataTools.sendMessage` (4.4, 4.5) |
| M7 | `SettingsPage` constructor | new props optional/nullable; rows hidden when null (4.5) |

## 11. r2 → r3 change log (codex findings)

| # | Finding (r2) | Resolution in r3 |
|---|---|---|
| H1 | hex fields not decoded before HKDF/X25519/AEAD; `n24` literal 48 bytes | byte-decoding rule, lengths, combined ciphertext‖tag layout (3.4) |
| H2 | `LeaveAll` while `running_` true lets `Tick()` rejoin | `accepting_` gate set first; `LeaveAll` synchronous on the event thread; all entries return when not accepting (4.2) |
| M1 | invite callback outside `Owns()` | invite dropped by chat_id (first 32 bytes) or prefix+derivation (4.2) |
| M2 | native `createLocationMessage` never reaches the platform | platform work removed; SDK's pure-Dart creation + DataTools send documented (4.4) |
| L1 | "exact" examples with ellipses | labelled schematic; concrete vectors in `test/nearby/vectors/` (3.4) |

## 12. r3 → r4 change log (codex findings)

| # | Finding (r3) | Resolution in r4 |
|---|---|---|
| H1 | restore leave inside the self-join callback | callback marks; leave queued with `PostToEventThread`; inline only in the `InitSDK` restore loop (4.2) |
| H2 | `RunOnEventThread` may cancel after 10 s / loop may have exited | `LeaveAll` idempotent; inline fallback on the `UnInitSDK` thread when the task did not run (4.2) |
| M1 | case-insensitive hex vs canonical bytes | strictly lower-case hex, no normalisation (3.4) |
| M2 | `to` unspecified; intents tracked `sk` only | `to` = recipient `ek`; intents track (`sk`,`ek`); receiver checks `to == own ek`; binding uses the published pair (3.4) |

## 13. r4 → r5 change log (codex findings)

| # | Finding (r4) | Resolution in r5 |
|---|---|---|
| H1 | `RunOnEventThread<void>` cannot report cancellation | `RunOnEventThread<bool>` with an execution sentinel; inline fallback when not `true` (4.2) |
| H2 | `accepting_` does not drain admitted operations | `inflight_` counter + bounded wait in `LeaveAll`; late operations leave what they created (4.2) |
| M1 | pending intent tuple still omitted `target ek` | tuple updated (3.4) |

## 14. r5 → r6 change log (codex findings)

| # | Finding (r5) | Resolution in r6 |
|---|---|---|
| H1 | bounded wait is not a barrier; a stale admitted operation can publish after re-init | per-operation generation capture + check at record time; mismatched operations leave and record nothing (4.2) |

## 15. r6 → r7 change log (codex findings)

| # | Finding (r6) | Resolution in r7 |
|---|---|---|
| H1 | generation checked only after the Tox call; a paused operation could pin the next session's instance | session epoch captured at admission, verified against the pin plus `Expired()` before every Tox call and between calls (4.2) |
