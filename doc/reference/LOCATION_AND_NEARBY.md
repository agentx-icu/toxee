[简体中文](./LOCATION_AND_NEARBY.zh-CN.md)

# Location messages and People nearby

toxee can send your current position to a friend or a group, and can show
you other toxee users who are in the same area so you can send them a friend
request. Neither feature uses a server: location messages travel on the
encrypted friend link, and "People nearby" meets strangers through the Tox
DHT. Both are **off by default**.

## Switches (Settings)

| Switch | Default | What it gates |
|---|---|---|
| **Location** | off | Everything that reads this device's position: the composer's *Location* option and People nearby. While it is off toxee never asks the OS for a position. Turning it on asks for the OS location permission (when-in-use only); a refusal leaves the switch off and explains how to allow it in the system settings. |
| **Visible to people nearby** | off (needs *Location*) | Joining the rendezvous cells of your area and broadcasting a presence record. A privacy notice is shown the first time. |

Both are per account. They turn themselves off when you switch accounts, and
People nearby stops whenever the app goes to the background, when the
nearby page has been closed for five minutes, or when either switch is turned
off.

## Location message

*Composer → Location* (desktop toolbar, mobile attachment sheet). toxee reads
one position fix and sends it as a location message; the receiver sees a
bubble with the coordinates, *Open in Maps* (the OS maps application; no map
provider is contacted by toxee) and *Copy*. Works for friends and groups,
on every platform. The position is as precise as the OS gives it — it is
your choice to send it, like any message.

## People nearby

Entry: *Add contact → People nearby*, or the button under the switches.

What you see: the people within roughly 5 km who also have *Visible to
people nearby* on, with their name and an approximate distance. What they
see of you: your name, avatar hash and your position rounded to about 100 m,
refreshed about once a minute while the page is open. Nearby pauses when
the app goes to the background and starts again when you come back to the
page (or tap refresh); when your area's cell cannot be joined right now the
page says so and keeps retrying in the background.

*Say hi* sends them a request with an optional message (up to 140
characters; the counter shows the bytes that fit in one packet, about 200
for non-Latin text). **This is the only
moment your Tox ID leaves your device**: it is sent, encrypted, to that one
person, after a confirmation. If they accept, they send you an ordinary Tox
friend request; it shows up as a card ("reply from someone nearby") with
their public key, and one tap adds them. If they decline, nothing happens.

When someone nearby says hi to you, you get a card with their name and
message. *Accept* sends them the friend request (their Tox ID was in the
request); *Decline* discards it. *Block* hides a person for the session.

### Limits you should know

These follow from having no server and are not bugs:

- **Anyone can look.** The cells are public groups whose id anyone can
  compute, so anyone in your area can see the same list you see. This is
  why only a coarse position and a per-session key are broadcast, and why
  your Tox ID is never broadcast.
- **Positions are self-reported.** toxee cannot verify where someone really
  is, nor their name or avatar.
- **No global moderation.** There is no reporting or global blocking; block
  lists are local. Requests are rate-limited (5 sent and 3 received per
  person per hour).
- **Sharing your Tox ID is a disclosure.** The person you contacted could
  pass your Tox ID on. If that becomes a problem, a new Tox ID (nospam)
  invalidates the old one; toxee does not offer that from the nearby page
  yet.
- **Foreground only.** Nothing runs in the background, so you are only
  discoverable while the app is open.

## For developers

- Design: `doc/plans/LOCATION_AND_NEARBY_PLAN.md`; feasibility:
  `doc/plans/LOCATION_AND_NEARBY_RESEARCH.md`.
- Transport: tim2tox rendezvous groups,
  [RENDEZVOUS_GROUPS.md](../../third_party/tim2tox/doc/architecture/RENDEZVOUS_GROUPS.md).
- Code: `lib/nearby/` (protocol, state machine, location source,
  permission flow, controller), `lib/ui/nearby/` (pages),
  `lib/ui/widgets/location_message_bubble.dart`,
  `lib/util/prefs/location_prefs.dart`.
- Tests: `test/nearby/`, `test/location_message_bubble_test.dart`,
  `test/location_platform_declarations_test.dart`.
- Mobile checklist rows: B10, N6, P8 in
  [MOBILE_DEVICE_FEATURES.md](MOBILE_DEVICE_FEATURES.md).
