# S78 — Record + send a voice message

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on network=online friends=1(paired, both online) history=empty`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — record dialog gates on a real mic (`AudioRecorder.hasPermission()`, `tencent_cloud_chat_message_input_recording_desktop.dart:73`) AND delivery confirmation needs a second live toxee receiving the sound file over the DHT (Fixture C).
**Status**: end-to-end delivery is covered by the Fixture C gate `tool/mcp_test/run_fixture_c_voice_msg.sh` (a voice message is an audio file send: l3_send_file with a .ogg name → mediaKind='audio' on the sender, auto-accepted with mediaKind='audio' on the receiver; validated live 2026-06-01). The MOBILE record UI half is additionally covered at the widget layer (L1): the production `TencentCloudChatMessageInputRecording` state machine (start → recording-state render → slide-to-cancel-no-send → normal-release voice-message path) and the press-and-hold mic affordance in `TencentCloudChatMessageInputMobile` are driven directly with the `record` plugin MethodChannel stubbed (no real microphone).

**Covered-by** (mobile record UI, L1): `test/ui/mobile/mobile_voice_record_real_ui_test.dart`

## Precondition
- Feature IS implemented (see Notes for send chain).
- A, B in separate macOS Containers, distinct `CFBundleIdentifier` (A=`com.toxee.app`, B=`com.toxee.b.app`).
- A and B friends and both Online; else audio takes the offline-queue branch.
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`.
- macOS mic TCC for `com.toxee.app` pre-granted (desktop never prompts in-app; same gate as S65).
- Desktop voice only on macOS/Windows (`_desktopVoiceSupported`, `tencent_cloud_chat_message_input_desktop.dart:389-392`).

## Driver
1. A: poll sidebar `\nOnline` ≤60s; baseline `official.get_runtime_errors({})`.
2. A: tap `UiKeys.sidebarChats`; open B's conversation row (no `conv_<friendId>` key — match ref/label).
3. A: tap desktop mic button (`Icons.mic`, `tencent_cloud_chat_message_input_desktop.dart:394-419`); no key (Notes).
4. `_DesktopVoiceRecorderDialog` mounts, auto-starts (`:67` post-frame `_start`). Hold ≥1s, confirm/send → `_stop(send:true)` (`:121`) pops `RecordInfo` (`:151`).
5. B: poll snapshot ≤60s for received audio bubble. Do NOT `sleep`.

## Assertions
- A1: dialog shows recording UI — `Icons.mic` + elapsed counter (`:184`,`:197-199`); on denied mic shows `'Microphone permission denied'` (`:77`) and MUST NOT proceed.
- A2: on send, `sendVoiceMessage(voicePath, duration)` fires (`tencent_cloud_chat_message_input_desktop.dart:402-405`) → `createVoiceMessage` (`tencent_cloud_chat_message_sdk.dart:236`) → `createSoundMessage` (`tim2tox_sdk_platform.dart:4465`) builds `V2TIM_ELEM_TYPE_SOUND` (`:4490`).
- A3: send log is verbatim `[Tim2ToxSdkPlatform] Sending sound message: <path> (duration=<n> ms)` (`tim2tox_sdk_platform.dart:5210`). See Notes: `<n>` is whole SECONDS despite the `ms` label. Duration encoded into transfer filename `..__dur<n>.m4a` (`:5240`).
- A4: A surfaces outgoing audio bubble (`soundElem` set; `tencent_cloud_chat_message_sound.dart` renders duration).
- A5 (B-side): ≤60s B's snapshot shows audio bubble; `soundElem.duration` recovered from `__dur` token (decoder `tim2tox_sdk_platform.dart:293-294`, applied at `:922-950`).
- A6: `get_runtime_errors` matches Step-1 baseline both sessions.

## Notes
- Implemented end-to-end: record dialog `tencent_cloud_chat_message_input_recording_desktop.dart`, wiring `tencent_cloud_chat_message_input_desktop.dart:394-419`, send `tim2tox_sdk_platform.dart:4465` + `:5210` (audio as Tox file transfer, duration smuggled in filename). `messageInputBuilder` (`home_page_bootstrap.dart:449`) does NOT strip the mic button.
- The `(duration=<n> ms)` log label and the `__dur{ms}` filename marker (`:5212`/`:5240`) are a production mislabel: `<n>` is whole SECONDS (recorder `(_elapsedMs/1000).ceil()`, `tencent_cloud_chat_message_input_recording_desktop.dart:148` → `RecordInfo.duration` → `soundElem.duration`).
- Media-spike pin: Step 4 needs a real mic; dialog hard-stops on `hasPermission()==false` (`:73`), no `RecordInfo` override seam today. Wanted: injectable recorder/`RecordInfo` stub.
- Fixture-C pin: A5 needs a second live toxee on the DHT (`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`). Echo peer is NOT a substitute — echoes c2c text, not file transfers (S21).
- Wanted UiKeys (none today): mic/record button, `conv_<friendId>`, `messageItem_<msgId>`.
