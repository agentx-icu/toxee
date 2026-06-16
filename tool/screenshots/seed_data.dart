// Seed-data definitions for the cross-platform product-screenshot pipeline
// (capture_product_screenshots.dart).
//
// The pipeline drives ONE real toxee instance per platform (desktop / android
// / ipad / ios) and seeds rich demo data LOCALLY via the debug L3 surface —
// no real peer, no P2P handshake. The seed is fully self-contained:
//   - friends are added by public key (tox_friend_add_norequest) with a cached
//     display name (l3_seed_friend);
//   - the C2C conversation is materialized as DELIVERED bubbles in BOTH
//     directions (l3_inject_c2c_text, isSelf toggles direction);
//   - the group is created + back-filled with multi-sender history
//     (l3_create_group + l3_inject_group_text);
//   - a pending inbound friend application is materialized for the
//     "new application" scene (l3_inject_friend_application).
//
// Everything here is DATA, deliberately separated from the driver so the
// dialogue can be re-written without touching orchestration. English copy with
// light emoji — reads as a real weekend-hike plan that matches the group.

/// One seeded peer. [pubKey] is a deterministic, well-formed 64-hex Tox public
/// key used ONLY for local seeding — it never reaches the DHT, so it does not
/// need to correspond to a reachable account; tox_friend_add_norequest stores
/// it verbatim. [nickname] is the display name cached locally so conversations
/// render a real name instead of the raw key.
class Persona {
  const Persona({
    required this.pubKey,
    required this.nickname,
    required this.statusMessage,
  });

  final String pubKey;
  final String nickname;
  final String statusMessage;
}

/// The hero account registered live on each platform (its real Tox ID is
/// assigned at registration; only the nickname/status are seed inputs).
const heroNickname = 'Mia';
const heroStatusMessage = 'Hiking, coffee, and P2P chat';

// Deterministic 64-hex public keys (8 groups of 8) for the seeded peers. They
// are intentionally fake-but-valid: distinct from each other and from any real
// account, accepted verbatim by tox_friend_add_norequest.
const personaAlex = Persona(
  pubKey: '8F2A1C7D4E9B0356A1D8F24C6B3E9075C2A4F18D5E7B0C93D6A180F42B9C3E57',
  nickname: 'Alex Chen',
  statusMessage: 'On the trail somewhere',
);
const personaSofia = Persona(
  pubKey: 'B6C4019E7A2D58F30C9147BE6A35D082F41C9D5E70A8B264E3F1097C5D8240AB',
  nickname: 'Sofia 🌸',
  statusMessage: 'Probably reading',
);
const personaKenta = Persona(
  pubKey: 'C8013D6F9B47A2E05C8F1340A96BD27E4F0581CA3D9E76B240178FC5E9A3B602',
  nickname: 'Kenta 健太',
  statusMessage: '東京 ⇄ everywhere',
);

/// The "new friend" applicant — deliberately NOT a friend, so it surfaces on
/// the New-Contacts page.
const applicantPubKey =
    'D4A37F015C8E29B6403DA17FE8259C04B6F381DA9027E5C4136A80FB5E29D7C3';
const applicantNickname = 'Jordan Lee';
const applicantWording =
    'Hey Mia! Jordan from the Saturday trail crew — let\'s connect 🥾';

/// All seeded FRIENDS (Alex is the hero's C2C partner; Alex + Sofia are the
/// extra group members whose injected lines must resolve to a name).
const seededFriends = [personaAlex, personaSofia, personaKenta];

/// One scripted C2C line. [fromHero] true = the hero (self) sent it; false =
/// the peer sent it. Rendered as a DELIVERED bubble either way.
class C2cLine {
  const C2cLine(this.fromHero, this.text);
  final bool fromHero;
  final String text;
}

/// Hero ↔ Alex conversation — mixed directions, emoji, lands a friendly
/// weekend-hike thread. The last ~8 lines are what the chat pane shows.
const conversationWithAlex = [
  C2cLine(false, 'Hey Mia! Made it back from Patagonia 🎒'),
  C2cLine(true, 'Alex!! Welcome back. How was the W trek?'),
  C2cLine(false, 'Unreal. My knees are filing a formal complaint though'),
  C2cLine(true, 'Haha, worth it 😄'),
  C2cLine(false, 'Lake trail this Saturday? The larches just turned 🍂'),
  C2cLine(true, 'Yes! North loop or the lakeside start?'),
  C2cLine(false, 'Lakeside — trailhead at 7am, back before the rain'),
  C2cLine(true, 'Deal. I\'ll bring the good thermos ☕'),
  C2cLine(false, 'Perfect. Sending the route tonight 🗺️'),
  C2cLine(true, 'See you Saturday 🥾'),
];

/// Group seeded by the hero.
const groupName = 'Weekend Hikers 🏔';

/// Group chatter — (senderPubKey | 'self', text). 'self' goes through the real
/// l3_send_group_text path; everyone else is injected via l3_inject_group_text
/// with their (seeded-friend) public key so the name resolves. `final` (not
/// const) so the lines can reference the persona keys without duplicating them.
final List<(String, String)> groupScript = [
  ('self', 'Made us a group for Saturday 🏔'),
  (personaAlex.pubKey, 'Excellent. 7am at the north lot?'),
  (personaSofia.pubKey, 'In! Bringing trail mix 🥜'),
  ('self', '7am works. Weather says clear until 3pm'),
  (personaAlex.pubKey, 'I\'ve got the map + first aid kit'),
  (personaSofia.pubKey, 'Someone please bring a real camera 📷'),
  ('self', 'On it. Lakeside lunch at the halfway point?'),
  (personaAlex.pubKey, 'Approved 🙌'),
];
