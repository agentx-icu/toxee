# Location sharing and "People nearby" — feasibility research

Status: research note, 2026-10-17, revised after codex review (r6).
Branch `agentx/location-nearby-research` (worktree
`~/chat-uikit/toxee-location-nearby`). No code changes.

Question asked: do these three features need a centralised server?

1. Read the current device location of self and of other people, and show it.
2. Location is off by default; a Settings switch turns it on.
3. "People nearby": list people around me and let me send them a friend request.

Short answer:

| Feature | Needs *our own* server? | Needs any third party? | Verdict |
|---|---|---|---|
| 1. Share / show location | **No** | Only for a rendered map (tile or map SDK provider). None if we show coordinates + "Open in Maps" | Rides on existing friend links |
| 2. Default-off switch | **No** | No | Local preference; the pattern exists |
| 3. People nearby | **Not necessarily**, but it needs a *rendezvous* for strangers. (A) our index server; (B) decentralised rendezvous over the Tox DHT via geocell NGC groups; (C) physical proximity (mDNS on the LAN / BLE) | (B) needs a toxcore addition plus new tim2tox/FFI surface; (C) needs new mDNS code and platform plumbing | (B)+(C) are feasible without any server, with inherent limits listed in §3. (A) is the pragmatic choice if radius search, ranking, moderation or reporting are required |

Everything below is evidence and trade-offs. File:line references were
checked against the worktree (toxcore submodule is upstream `v0.2.23-rc.1`,
built unpatched via `add_subdirectory`, `tim2tox/CMakeLists.txt:79`).

---

## 1. Sharing and showing location — no server

### What already exists

- **Wire format.** A location message is a first-class element on the Tox
  link today. `Tim2ToxSdkPlatform` serialises `V2TimLocationElem` (`desc`,
  `longitude`, `latitude`) as a text message with the `__location__:` prefix
  (`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:6329-6358`);
  the receive side turns it back into
  `MessageElemType.V2TIM_ELEM_TYPE_LOCATION` (`LocationTextEnvelope`,
  `third_party/tim2tox/dart/lib/utils/control_message_envelope.dart:31`;
  mapping in `lib/sdk_fake/fake_provider.dart:765-850` and
  `tim2tox_sdk_platform_converters.dart:362`). History persistence, search
  exclusion (`message_search.dart:10`) and the `[Location]` conversation
  preview (fork `tencent_cloud_chat_utils.dart:231`) already handle it.
- **Transport.** Friend traffic is end-to-end encrypted by toxcore. There is
  no application server. Note the honest limit: when UDP is blocked the
  packets pass through a TCP relay (`tox.h:617-629`), and DHT/relay nodes
  see connection metadata (who talks to whom, when, how much), never the
  payload. That is the same exposure every toxee message already has.
- The native side declares `CreateLocationMessage`
  (`V2TIMMessageManagerImpl.h:52`).

### What is missing (all client-side)

| Gap | Where | Note |
|---|---|---|
| Location bubble is a stub | fork `tencent_cloud_chat_message_item_builders.dart:133-139` returns `Text("Location message todo")` | New `message_type_builders/tencent_cloud_chat_message_location.dart` on the fork `v2` branch |
| No composer entry to send a location | fork `attachmentOptions` (`tencent_cloud_chat_message_input_container.dart:822`) | Add an attachment option; the mobile (`…_input_mobile.dart:1189`) and desktop (`…_input_desktop.dart:617`) inputs render the same list |
| No device-location source | `pubspec.yaml` has `permission_handler`, `url_launcher`; nothing for GPS | `geolocator` covers Android, iOS, macOS, Windows, Linux (geoclue2) with one Dart API |
| No location permission plumbing | Android manifest: no `ACCESS_FINE/COARSE_LOCATION` (`AndroidManifest.xml:6-59`); iOS `Info.plist`: no `NSLocationWhenInUseUsageDescription`; macOS: no `com.apple.security.personal-information.location` entitlement (`macos/Runner/Release.entitlements`) and no usage string | Six-language `InfoPlist.strings` exist for the other usage strings; follow that pattern |
| Permission helper does not fit as-is | `lib/call/permission_helper.dart`: `_serialised` (`:39-49`) is the single-flight gate, `_requestSafely` (`:71-95`) the wrapper; the helper **skips runtime requests on macOS/Linux** (`:107-119`) | A location helper must *not* inherit that desktop skip: macOS prompts for CoreLocation, Linux geoclue prompts via the portal |
| "Current location of another person" semantics | Only one-shot messages exist | See *Live location* |

### Displaying a location

1. **No network**: `desc` + coordinates in the bubble and *Open in Maps*
   via `url_launcher` (`geo:` Android, `maps://` iOS/macOS, an OSM URL
   elsewhere). No providers, no keys. Enough for an MVP and for the nearby
   list.
2. **Tile map in-app** (`flutter_map` + a tile server): tiles come from a
   third party (OSM tile policy requires a UA and forbids bulk use; mainland
   China needs a domestic provider), and the tile server learns which areas
   this IP looked at.
3. **Platform map SDK** (MapKit / Google Maps / AMap): keys and terms.

Recommendation: ship 1; 2 as an opt-in later. None needs a toxee server.

### Live location ("current" position of a friend)

Option 1 gives *last shared* position. Continuous position of a friend
means the sender pushes updates while sharing is active. Two P2P ways:

- **Periodic location messages** — simplest, pollutes history and the
  conversation list.
- **Control frame** over our registered lossless packet ID 184
  (`Tim2ToxPacketIds.h`; registry PR #4 merged 2026-09-10). This is more
  than adding `Type::kLocationUpdate = 5` to `Tim2ToxControlPacket.h:17-24`:
  the decoder rejects unknown types (`Tim2ToxControlPacket.cpp:18-26,59-62`),
  the native receiver only dispatches receipt/reaction
  (`V2TIMManagerImpl.cpp:2957-2972`), and there is no generic Dart/FFI
  send/receive path for a new control type. Work: encoder/decoder case,
  native dispatch to a new event, FFI export, Dart listener, in-memory
  "friend positions" map. Lossless custom packets are not persisted as
  messages, which is what we want. Shared C++/Dart, so mobile is covered by
  the same code.

Consent: a friend receives my position only while **I** have the switch on
**and** I started sharing in that conversation (per-chat, time-boxed, like
WhatsApp's 15 min / 1 h / 8 h). Never push by default to all friends.

Mobile constraint: background sharing needs the `location` foreground
service type (and `FOREGROUND_SERVICE_LOCATION`) on Android — the current
service declares only `specialUse`/`dataSync`/call types
(`AndroidManifest.xml:39-47,106-113`) — and the `location` background mode
on iOS (today only `audio` + `fetch`, `Info.plist:67-71`). Both are store
policy-sensitive. v1: foreground-only sharing; stop GPS on `paused`.

## 2. Default-off switch — no server

Pattern already exists: per-account bool prefs with a `false` default
(`Prefs.getAutoAcceptFriends/setAutoAcceptFriends`, `lib/util/prefs.dart:809-840`),
rendered as the title/description `Switch` rows on desktop
(`lib/ui/settings/settings_page_build.dart:190-220`, auto-login /
auto-accept rows) and on mobile (`settings_page_mobile_widgets.dart:171-200`;
line 162 is auto-login). Add:

- `Prefs.getLocationSharingEnabled(toxId)` default **false** (and a
  separate `getNearbyVisible(toxId)`, also false — being visible to
  strangers is a bigger step than sharing with a friend);
- the switch next to the privacy rows; turning it **on** triggers the OS
  permission request; a denial turns it back off with the P1b
  "explain → Settings" flow;
- the switch gates *every* producer: composer option, live updates, nearby
  announce. Off ⇒ no position is ever read from the OS.

Nothing here touches a server.

## 3. People nearby — the only part that needs a rendezvous

"Nearby" means *find peers I do not know yet*. Tox has no global index; a
friend link exists only after both sides hold each other's key. Some
rendezvous is unavoidable; the question is whether it must be centralised.

### toxcore primitives (v0.2.23-rc.1)

| Primitive | What it does | Fit |
|---|---|---|
| LAN discovery (`toxcore/LAN_discovery.c`) | Broadcasts the *DHT* public key every 10 s so DHT nodes on one subnet find each other. The DHT key is rotated on every `tox_new` (F6 in `lan_bootstrap_service.dart`) and is **not** the Tox ID | Not "people nearby"; at most a same-network hint |
| Generic DHT announce store (`toxcore/announce.c`) | One ≤512-byte blob per `data_public_key`, ≤900 s, 32×8 slots per node; not in `tox.h` | Single writer per key → cannot hold a cell's member list. Rejected |
| **NGC public groups** (`tox_group_join(chat_id, nick, password?)`, `tox.h:3377-3404`) | Anyone with the 32-byte `chat_id` finds the group's peers through onion announces stored near `chat_id` (`group_onion_announce.c`, 16 announces per group per node, self-refresh every 20 min), then peer exchange spreads the member list. Join never *founds*: with no announced peer the join sits in CONNECTING; a known chat_id only reconnects (`group_chats.c:7656-7662`). Cap `MAX_GC_PEERS_DEFAULT 100` (`group_common.h:48`, enforced `group_chats.c:7282-7285`, full groups refuse unconfirmed peers `:1792-1798`) | **Fits** as a multi-writer rendezvous keyed by a public key, with the caveats below |
| NGC custom private packets (`tox_group_send_custom_private_packet`) | Used by tim2tox for group receipts and identity proofs, but only through hard-coded paths: the sender at `V2TIMManagerImpl.cpp:7802` is receipt-specific and the receiver (`:7643-7665`) accepts only identity proofs or receipts. Requires a live confirmed peer, no offline queue (`tox.h:4524-4552`) | Usable, but a nearby profile/intent packet needs a new native send API, a receive schema, FFI export and Dart routing |

### Option B — decentralised nearby over geocell groups

Idea: one NGC public group per **geocell** (geohash). Everyone with
*nearby visible* on joins the group of their cell (plus neighbours when near
an edge). The group's member list is the nearby list.

Protocol sketch (v2, after review):

1. `cell = geohash(lat, lon, p)`; p = 5 (≈ 4.9 km × 4.9 km) by default,
   p = 6 (≈ 1.2 km × 0.6 km) in dense areas. Coarser = more privacy, fewer
   groups; finer = better "nearby".
2. `seed = SHA-256("toxee/nearby/v1|" + cell)`;
   `(chat_id, chat_sk) = crypto_sign_seed_keypair(seed)` (+ the ed25519 →
   curve25519 conversions `create_extended_keypair` does,
   `crypto_core.c:49-63`). Every client can derive it; no directory.
3. `tox_group_join(chat_id, nick)`. If no peer answers within ~30 s, the
   client *founds* the cell with the same keypair so the next arrival finds
   it. **Not possible on stock toxcore**: `tox_group_new` draws the keypair
   from the RNG (`group_chats.c:7557`) and `tox_group_join` never founds.
   Needed: a seeded-founder entry point (private-API style,
   `tox_group_new_with_seed` reusing `gc_group_add` + founder shared-state
   init with a supplied extended keypair), plus tim2tox `ToxManager`
   wrapper, FFI export and Dart plumbing (`ToxManager.cpp:1333,1377` wrap
   only ordinary new/join). This is toxee's first toxcore patch: carry it in
   a fork of the submodule and propose it upstream.
4. **Presence.** Each member broadcasts a small profile over a custom
   packet: display name, avatar hash, **coarse** position (cell centre or
   rounded to ~100 m), an ephemeral **session keypair** — one Ed25519 key
   for signing and one X25519 key for receiving encrypted replies, both
   fresh per session (or a single Ed25519 key with the ed25519→x25519
   conversion toxcore itself uses in `create_extended_keypair`) — and a
   signature by the Ed25519 key over the record + a monotonically
   increasing sequence number + expiry. **No Tox ID, no long-term key.**
   Records are replaced per session key, dropped at expiry, and rate-limited
   per session key / per NGC peer key. Nothing in a presence record is
   verifiable beyond "the same session key signed it": names, avatars and
   positions are self-reported (see the limits below).
5. **Friend request: only the initiator discloses, and Tox does the binding.**
   This v1 sketch does **not** implement proof-of-possession of a Tox
   identity before the handshake; it avoids trusting identity claims made
   over the cell group and lets the Tox handshake be the proof. A proof *is*
   possible — `tox_self_get_secret_key` is public API and tim2tox already
   seals challenge proofs with it (`SealIdentityProof`,
   `V2TIMManagerImpl.cpp:6690-6712`) — and adding one (A seals a challenge
   to B's session key with A's long-term key; B does the same in an
   explicit accept packet before sending the request) would close points
   (ii) and (iii) below at the price of revealing long-term public keys to
   the chosen peer. Decide this when the protocol is specified, not here.
   - A → B (private packet): "intent" `{A.address (76 hex), nonce, message,
     expiry}` **encrypted to B's session X25519 key** and signed by A's
     session Ed25519 key. Only B can read it. A discloses its address by
     choice, to one chosen peer — the same act as handing someone a QR code.
   - B sees a card (A's profile, message). If B accepts, B calls the
     existing outgoing path `tox_friend_add(A.address, nonce ‖ message)`
     (`V2TIMFriendshipManagerImpl.cpp:694`). Decline ⇒ no friend request is
     sent; B has already received A's address, card and message, and keeps
     them.
   - A receives a normal Tox friend request. The Tox handshake
     authenticates the sender's long-term key. If the request message
     carries a nonce from one of A's still-pending intents (single-use,
     expires with the intent), A shows it as "reply from <card name> you
     contacted nearby" with a **one-tap confirm** that runs the existing
     acceptance path (`tox_friend_add_norequest(pubkey)`, `:1093-1151`).
     Fully automatic acceptance is offered only behind the existing
     auto-accept-friends preference. Any other request is treated as today:
     an ordinary friend application, or auto-accepted if that preference is
     on (it applies to all incoming requests).
   - **Trust limit, stated plainly.** In this v1 sketch no step binds the
     session key, the card or the nonce to a long-term Tox key: the sketch
     deliberately omits the pre-handshake challenge proof described above,
     and strangers share no trust anchor beyond it. The address in the
     intent embeds a long-term public key *claimed by the sender*, but
     without that proof nothing shows the intent's sender owns it. "The person I tapped"
     therefore means exactly "whoever holds that session key". Consequences: (i) a cell member can present any name,
     avatar or position; (ii) B may forward A's nonce to a third party C,
     and the request A then confirms comes from C — the confirm tap and the
     sender's 64-hex public key shown on it (the friend-request callback
     carries the public key, not an address) are the only defence, which is
     why acceptance is not silent; (iii) A can put a *victim's* address in the intent, so B's
     accept sends the victim one unsolicited request (request spam by
     proxy) — slowed by B's consent tap and the per-session rate limit,
     not bounded: sessions can be restarted, one accepted intent can be
     forwarded to many identities, and there is no victim-side or global
     throttle (only the victim's own nospam rotation). A server-based
     nearby has the same (i)–(iii) unless it verifies identities, which Tox
     cannot do for it; what a server adds is the global throttle. Intent
     replay needs explicit consumed-nonce state on A's side in addition to
     expiry.
   - **Residual risk — address disclosure.** A Tox address embeds A's
     current nospam; whoever holds it can send friend requests, or hand it
     to others, until A rotates the nospam (`tox_self_set_nospam`: old
     addresses stop working for *new* requests, existing friendships are
     untouched, and every QR/ID A shared before is invalidated — so the
     rotate action must also cancel or reissue A's pending nearby intents,
     which embed the old address). The consent UI must
     say "your Tox ID will be shared with <name>", the nearby screen should
     offer "rotate my Tox ID" next to the block action, and intents must be
     rate-limited per session (e.g. 5 per hour). The nospam design means
     this risk already exists for every published Tox ID; nearby merely
     adds a new disclosure path, chosen by the discloser.
6. Leaving the cell or switching visibility off ⇒ `tox_group_leave` and
   the session key dies.

Limits that are **inherent** to B (tell the product owner; none has a
server-less fix):

- **Shared founder secret ⇒ no moderation boundary.** toxcore's group
  signing secret is meant for the founder only (`group_common.h:304-305`);
  founder role comes from `shared_state.founder_public_key`
  (`group_chats.c:958-984`) and shared-state updates are checked only
  against the chat key, equal versions accepted (`:2932-2971`). With a
  derivable secret, **every client is founder**: anyone can kick, set a
  password, flip privacy, lower the peer limit, and clients can overwrite
  each other's shared state. Two clients founding the same cell in the same
  window connect through peer exchange (`:1772-1809,8408-8454`) and
  converge nondeterministically rather than partition. Consequences for the
  design: treat cell groups as **untrusted transport only** — never show
  them in the group list, ignore their shared state, name, topic and
  moderation, rejoin/re-found after a kick, and accept that a hostile
  client can disrupt a cell (lock it with a password, churn the state). The
  dual-founder convergence must be covered by an `auto_tests` case before
  shipping; upstream never exercises identical founder keys.
- **Anyone can enumerate a cell** by deriving its chat_id and joining —
  as a scraper could against a central nearby API, but with no rate limit
  or ban. Mitigation is only what step 4 gives: coarse position, ephemeral
  key, no identity in the broadcast, and a clear UI statement "visible to
  people within ~N km while this is on".
- **Positions are self-reported.** Anyone can claim any cell/position
  (Sybil, "teleporting", impersonating a name/avatar). Same as every
  nearby product without attestation; a server does not fix it either,
  it only adds bans.
- **Empty cell ⇒ no group** until someone founds it; the first arrival in
  a quiet area sees an empty list for ~30 s.
- **Capacity.** 100 peers per group. The overflow rule must be explicit
  multi-cell membership, not "switch to p=6": a client that finds its p=5
  cell full joins its own p=6 sub-cell **and stays in the p=5 cell as a
  listener when it can**; peers always publish which cells they are in so
  others know where to look. Precision/overflow rules are part of the
  protocol version string.
- **Mobile cost.** 1–4 extra NGC memberships ⇒ onion announce traffic and
  DHT lookups while visible. NGC announces travel the onion/DHT path, peer
  connections use UDP or TCP relays. Foreground feature: when-in-use
  location permission only; in background Android's `ToxPollingService`
  keeps the Tox instance alive but nearby should pause, iOS suspends it
  anyway (B1).
- **No abuse lever at all**: no reporting, no global block, no age gate.
  Local block lists only.

### Option C — physical proximity, no network rendezvous

- **Same Wi-Fi / LAN via mDNS.** This is **not implemented today**: the
  `_tox._tcp` entry in `ios/Runner/Info.plist:49-56` is a declaration, but
  pairing moves IP/port through the QR code and direct sockets
  (`pairing_lan.dart:6-66`, `pairing_host.dart:85-105`,
  `pairing_client.dart:90-103`), and the LAN bootstrap service is a
  desktop-only DHT bootstrap daemon (`lan_bootstrap_service.dart:213-219`),
  not peer discovery. Work: publish/browse a `_toxee-nearby._udp` record
  carrying the session key + display name (`nsd`/`bonjour` packages or
  `multicast_dns`), iOS Local Network permission is already in place (N4),
  Android needs `NsdManager` (and `NEARBY_WIFI_DEVICES` on API 33+ only if
  we go beyond NSD). Zero DHT traffic, no geolocation, one subnet of reach.
- **BLE / Nearby Connections / MultipeerConnectivity.** True physical
  proximity (~10–50 m), works offline, but platform-specific (no
  Linux/Windows parity), Bluetooth permissions, and Google's Nearby pulls in
  Play Services.

C complements B ("on your network" first, "in your area" second); it is
not a replacement.

### Option A — a central index server

`POST /nearby {cell, session_key, ttl}` + `GET /nearby?cell=`. Fast to
build, precise radius search, server-side rate limits and bans, reporting.
Costs: toxee's first server (it has none today — not even push; the B2 row
in `MOBILE_DEVICE_FEATURES.md` records that a push server was declined to
stay pure P2P), operations, a privacy policy, and a party that sees every
visible user's coarse position. A nearby query does not need push, so B2
is precedent for the *stance*, not a technical dependency. Pick A only if
the product requires radius/ranking/moderation/reporting a DHT cannot give.

## Mobile parity and checklist (CLAUDE.md requirement)

Features 1–3 live in shared Dart (`lib/`, `tim2tox/dart`), shared C++
(`tim2tox/source`) or the fork, so Android/iOS run the same code paths.
Platform-specific work: permission strings/entitlements, the map
deep-links, mDNS plumbing, and any background service type. Review items
from `MOBILE_DEVICE_FEATURES.md`:

| Item | Answer |
|---|---|
| 4 Lifecycle / 5 Background time | Foreground features in v1; stop GPS and nearby on `paused`; no new FGS type or iOS background mode until a later, policy-reviewed step |
| 8 Permissions | New class: location (when-in-use). P1b flow for denial; a denied permission turns the switch off. Do **not** reuse the call helper's desktop skip |
| 9 Network | Location messages/frames: existing friend transport (UDP or TCP relay). Nearby: onion/DHT announces + peer connections, works behind relays like any NGC group |
| 10 Cross-platform peers | `__location__:` envelope and control frame are platform-neutral JSON |
| 11 Single instance | Unaffected |
| 12 Mobile parity | Shared code; desktop: geoclue (Linux), Windows Location API, CoreLocation (macOS, needs the entitlement) — `geolocator` covers all |

Checklist rows to add when implemented: P8 location permission
(when-in-use only, desktop prompts included), §5 row for geocell/mDNS
traffic, §4 row for the explicit "pauses in background" behaviour.

## Suggested delivery order

1. **Feature 1 + 2 MVP** (no toxcore or packet change): `geolocator` +
   permission strings/entitlement; `Prefs` switch default off; composer
   attachment option; real location bubble in the fork with *Open in Maps*;
   tests for the envelope round trip, the switch gating, and the permission
   denial path.
2. **Live location** control frame (`kLocationUpdate`) end to end (C++
   codec + dispatch, FFI, Dart), per-chat time-boxed consent.
3. **Nearby — LAN mode** (Option C): new mDNS publish/browse, the nearby
   UI (list, profile card), and the **intent/accept friend-request
   exchange** from step 5 of Option B over a direct socket. This proves the
   UI and the trust model with no DHT or toxcore work.
4. **Nearby — area mode** (Option B): toxcore seeded-founder API in a fork
   submodule (and an upstream PR), tim2tox generic custom-private-packet
   API (send + typed receive + FFI + Dart), geocell manager with the
   multi-cell overflow rule, `auto_tests` for dual-founder convergence and
   for a hostile founder (kick / password) recovery.

Each step goes through codex review before code, per the working agreement.

Decision needed from the product owner before step 4: accept the inherent
limits of a server-less nearby (enumerable cells, unmoderated cells,
self-reported positions, coarse granularity), or fund Option A.
