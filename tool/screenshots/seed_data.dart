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
// dialogue can be re-written without touching orchestration. The copy is
// per-locale ([SeedScript]): a Chinese UI captured over English names and
// dialogue reads as a half-translated product, so each locale the pipeline
// captures (`--locales`) carries its own names, group, conversation AND
// avatars (the avatar PNGs draw the name's initials — "A"/"WH" tiles on a
// Chinese contact list read as untranslated). Only the public keys are shared.
// English lives here, Chinese in seed_data_zh.dart.

import 'seed_data_zh.dart';

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
    required this.avatarFile,
  });

  final String pubKey;
  final String nickname;
  final String statusMessage;

  /// PNG under tool/screenshots/assets/ installed as this peer's avatar, so
  /// the seeded list is not N copies of the same placeholder.
  final String avatarFile;
}

/// One pending inbound friend request.
class Applicant {
  const Applicant({
    required this.pubKey,
    required this.nickname,
    required this.wording,
  });

  final String pubKey;
  final String nickname;
  final String wording;
}

/// One scripted C2C line. [fromHero] true = the hero (self) sent it; false =
/// the peer sent it. Rendered as a DELIVERED bubble either way.
class C2cLine {
  const C2cLine(this.fromHero, this.text);
  final bool fromHero;
  final String text;
}

/// Everything one locale's capture seeds.
class SeedScript {
  const SeedScript({
    required this.heroNickname,
    required this.heroStatusMessage,
    required this.alex,
    required this.sofia,
    required this.kenta,
    required this.applicants,
    required this.withAlex,
    required this.withSofia,
    required this.withKenta,
    required this.groupName,
    required this.groupAvatarFile,
    required this.groupScript,
  });

  /// The hero account registered live on each platform (its real Tox ID is
  /// assigned at registration; only the nickname/status are seed inputs).
  final String heroNickname;
  final String heroStatusMessage;

  /// Alex is the hero's C2C partner; Alex + Sofia are the extra group members
  /// whose injected lines must resolve to a name; Kenta adds a day-old thread.
  final Persona alex, sofia, kenta;

  /// The "new friend" applicants — deliberately NOT friends, so they surface
  /// on the New-Contacts page. THREE of them: a single row left three quarters
  /// of the phone screen an empty grey slab, and the page is meant to show
  /// that requests are approved one by one. Wordings must be short enough to
  /// survive the two-line clamp next to the Accept/Decline buttons on a 412pt
  /// phone.
  final List<Applicant> applicants;

  /// Hero ↔ Alex is the hero shot (the last ~8 lines are what the chat pane
  /// shows). Sofia's thread lands earlier today and Kenta's the day before
  /// (that row then shows a date instead of a time), so the conversation list
  /// has more than one real row.
  final List<C2cLine> withAlex, withSofia, withKenta;

  final String groupName;

  /// Group avatar PNG under tool/screenshots/assets/.
  final String groupAvatarFile;

  /// Group chatter — (senderPubKey | 'self', text). Every line is injected via
  /// l3_inject_group_text as delivered history with a spaced timestamp; 'self'
  /// resolves to the hero's id (a delivered self bubble — the real send path
  /// would park the line as pending in the offline seed environment and render
  /// a spinner). Others use their seeded-friend key so the name resolves.
  final List<(String, String)> groupScript;

  List<Persona> get friends => [alex, sofia, kenta];
}

/// The locales the pipeline can capture (the `l3_set_setting languageCode`
/// value each one is shot in is the key itself).
const seedScripts = {'en': seedEn, 'zh': seedZh};

// Deterministic 64-hex public keys (8 groups of 8) for the seeded peers. They
// are intentionally fake-but-valid: distinct from each other and from any real
// account, accepted verbatim by tox_friend_add_norequest. VALID means the last
// byte is < 0x80: toxcore's public_key_valid() rejects a curve25519 key whose
// top bit is set, and tox_friend_add_norequest then fails — which is exactly
// how Sofia's original key (…40AB) silently never became a friend, so her
// conversation rendered the raw key as its title.
const keyAlex =
    '8F2A1C7D4E9B0356A1D8F24C6B3E9075C2A4F18D5E7B0C93D6A180F42B9C3E57';
const keySofia =
    'B6C4019E7A2D58F30C9147BE6A35D082F41C9D5E70A8B264E3F1097C5D82402B';
const keyKenta =
    'C8013D6F9B47A2E05C8F1340A96BD27E4F0581CA3D9E76B240178FC5E9A3B602';
const keyApplicant1 =
    'D4A37F015C8E29B6403DA17FE8259C04B6F381DA9027E5C4136A80FB5E29D743';
const keyApplicant2 =
    'A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F01';
const keyApplicant3 =
    '0F1E2D3C4B5A69788796A5B4C3D2E1F00F1E2D3C4B5A69788796A5B4C3D2E1F0';

/// English copy with light emoji — reads as a real weekend-hike plan that
/// matches the group.
const seedEn = SeedScript(
  heroNickname: 'Mia',
  heroStatusMessage: 'Hiking, coffee, and P2P chat',
  alex: Persona(
    pubKey: keyAlex,
    nickname: 'Alex Chen',
    statusMessage: 'On the trail somewhere',
    avatarFile: 'avatar_alex.png',
  ),
  sofia: Persona(
    pubKey: keySofia,
    nickname: 'Sofia 🌸',
    statusMessage: 'Probably reading',
    avatarFile: 'avatar_sofia.png',
  ),
  kenta: Persona(
    pubKey: keyKenta,
    nickname: 'Kenta 健太',
    statusMessage: '東京 ⇄ everywhere',
    avatarFile: 'avatar_kenta.png',
  ),
  applicants: [
    Applicant(
      pubKey: keyApplicant1,
      nickname: 'Jordan Lee',
      wording: 'Jordan from the Saturday trail crew 🥾',
    ),
    Applicant(
      pubKey: keyApplicant2,
      nickname: 'Priya N.',
      wording: 'We met at the trailhead last weekend!',
    ),
    Applicant(
      pubKey: keyApplicant3,
      nickname: 'Tomás',
      wording: 'Adding you for the lake route photos 📷',
    ),
  ],
  withAlex: [
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
  ],
  withSofia: [
    C2cLine(false, 'Did you see the forecast for Saturday? ☀️'),
    C2cLine(true, 'Clear until mid-afternoon. Perfect.'),
    C2cLine(false, 'Bringing the good trail mix then 🥜'),
  ],
  withKenta: [
    C2cLine(true, 'Kenta! Are you back in town this month?'),
    C2cLine(false, 'Landing Friday 🛬 Save me a seat on the next hike'),
    C2cLine(true, 'Done. Weekend Hikers group incoming 🏔'),
  ],
  groupName: 'Weekend Hikers 🏔',
  groupAvatarFile: 'avatar_group.png',
  groupScript: [
    ('self', 'Made us a group for Saturday 🏔'),
    (keyAlex, 'Excellent. 7am at the north lot?'),
    (keySofia, 'In! Bringing trail mix 🥜'),
    ('self', '7am works. Weather says clear until 3pm'),
    (keyAlex, 'I\'ve got the map + first aid kit'),
    (keySofia, 'Someone please bring a real camera 📷'),
    ('self', 'On it. Lakeside lunch at the halfway point?'),
    (keyAlex, 'Approved 🙌'),
  ],
);
