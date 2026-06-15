# Chat UI Restyle — Pixel-Level Design Spec

**Goal:** Restyle the entire toxee app (all pages, desktop + mobile, light + dark) to pixel-faithfully match a clean enterprise-chat reference design. All color values below were sampled directly from the reference screenshots and are authoritative.

> **NAMING RULE (hard):** Do NOT write the product name of the reference design (or any of its brand names) in any code, comment, string, commit message, branch, or filename. Refer to it only as "the reference design" / "the reference screenshots". Use the neutral token source `DesignTokens` and describe colors by their hex/role.

**Two product decisions already made (do NOT deviate):**
1. **Message alignment stays conventional**: self bubble RIGHT-aligned (pale-blue), other LEFT-aligned (gray). Do NOT left-align self. Just apply the new colors/shape/typography.
2. **Desktop left sidebar keeps its current ~100px width** (recolor + new selected-state only; do NOT shrink to a thin rail).

**How theming flows (read before editing):**
- UIKit widgets (`third_party/chat-uikit-flutter/**`) get colors from a global singleton theme. They read `colorTheme.<slot>` inside `TencentCloudChatThemeWidget(build: (ctx, colorTheme, textStyle) => ...)`. Slot values are already wired to the new palette in `lib/util/app_theme_config.dart → createYouthfulThemeModel()`. **Changing a slot recolors every widget that uses it — no per-widget edit needed.** Only touch a UIKit widget when it (a) hardcodes a `Color(...)`/`Colors.x`, or (b) needs a shape/spacing/layout change the theme can't express.
- toxee pages (`lib/**`) use Flutter `Theme.of(context).colorScheme` (now an explicit, exact scheme) + Material component themes + `DesignTokens` constants.
- **UIKit code cannot import toxee `lib/`.** In UIKit use `colorTheme.<slot>` (or a local `const Color`). In toxee use `DesignTokens` / `Theme.of(context)`.

The foundation (tokens + theme model + color schemes) is DONE in: `lib/util/design_tokens.dart`, `lib/util/app_theme_config.dart`, `lib/main.dart`. Build on it.

---

## 1. Color Tokens (sampled — mirror of `DesignTokens`)

### Brand / accent
- primary `#3370FF`, primaryPressed `#245BDB`, primaryHover `#5089FB`, onPrimary `#FFFFFF`
- link/@mention: light `#3370FF`, dark `#6BA0FF`

### Text
| | Light | Dark |
|---|---|---|
| primary | `#1F2329` | `#E6E8EB` |
| secondary | `#646A73` | `#9AA0A6` |
| tertiary/placeholder | `#8F959E` | `#6B7178` |
| disabled | `#BBBFC4` | `#55585C` |

### Surfaces — Light
scaffold/chat/list/card `#FFFFFF` · desktop rail `#EBEEF5` · selected conv `#E5ECF4` · pinned `#F2F6FF` · hover `#F2F3F5` · input field `#F2F3F5` · settings page `#F5F6F8`

### Surfaces — Dark
scaffold/chat `#1A1A1A` · desktop rail `#29303C` · desktop list `#1C1C1E` · desktop chat `#151515` · selected conv `#21314A` · hover `#26262A` · input area `#262626` · input field `#2E2E2E` · card `#232427`

### Message bubbles
| | Light bg / text | Dark bg / text |
|---|---|---|
| self (RIGHT) | `#E8F0FE` / `#1F2329` | `#15315F` / `#E6E8EB` |
| other (LEFT) | `#F3F4F6` / `#1F2329` | `#26292E` / `#E6E8EB` |
- Bubble radius **12px uniform**. Padding 10v/12h. Max width ≈ 68% of message area. No visible border.
- @mention inside bubble: blue (link). Quoted reply: 2px left bar `#8F959E` + muted `回复 <name>: …` line in secondary text, 13px.

### Semantic / lines
- unread badge `#F54A45` / white text · online `#2BB344`
- bot tag (机器人): light bg `#FFF1D6` text `#B7791F` / dark bg `#3A3320` text `#E0A857`
- 全员 tag: light bg `#E1EAFF` text `#3370FF` / dark bg `#22304F` text `#6BA0FF`
- success `#2BB344`/`#3DCB5E` · warning `#FF8800`/`#FF9D2E` · error `#F54A45`/`#FF6159`
- divider `#E5E6EB`/`#2E3033` · hairline `#EFF0F2`/`#262829` · input border `#DEE0E3`/`#3A3D42`

All of the above exist as `DesignTokens.*` constants — use those, do not re-inline hex in toxee. In UIKit, prefer `colorTheme.<slot>`; only use a local `const Color(0x...)` when no slot fits.

---

## 2. Avatar shapes (rule)
- **Person → CIRCLE** (`borderRadius = size/2`).
- **Group / bot / notification → ROUNDED SQUARE** (squircle, `borderRadius = size * 0.28`).
- Helper: `DesignTokens.avatarRadius(size, isGroup: …)`.
- In UIKit, set radius by conversation/contact type at the call-site (the reusable `TencentCloudChatAvatar` default should become `size*0.28`). Conversation/contact list currently force a full circle — switch to type-based.

---

## 3. Typography & metrics
- Font: platform default (PingFang SC on Apple). No bundled font.
- Weights: titles/names 600, body 400, tab labels 500.
- Sizes (mobile / desktop): conv name 16/15, preview 14/13, time 12, message 16/15, sender name 13, app-bar title 17/16, tab label 11/12.
- Metrics: mobile conv row 72 (avatar 48), desktop conv row 58 (avatar 40), contact row 64 (avatar 44), title bar 48, bottom nav 56+safe (icon 26, label 11), card/dialog radius 12, button radius 8, pill radius 6, h-padding 16 mobile / 12 desktop. **No divider lines between conversation rows** (whitespace separation). 8px grid.

---

## 4. Window chrome (desktop) — owned by main session, do NOT edit in surface agents
Custom 48px draggable title bar; macOS keeps native traffic lights; Windows/Linux keep native-styled caption buttons top-right. Files: `lib/ui/widgets/desktop_window_frame.dart`, `lib/bootstrap/desktop_shell_bootstrap.dart`, `macos/Runner/MainFlutterWindow.swift`, `lib/main.dart`.

---

## 5. Per-surface coverage matrix (owner = parallel agent letter)

**Agent A — UIKit message bubbles + rows** (message pkg): `message_type_builders/*` (text/image/file/video/sound/sticker/merge/tips/custom/custom_c2c_call), `message_list_view/message_row/*`, `message_widgets/tencent_cloud_chat_message_reply_view.dart`. Bubble radius→12 uniform; **keep self RIGHT-aligned**; self/other bg via `colorTheme.selfMessageBubbleColor`/`othersMessageBubbleColor` (already correct); fix hardcoded: text link `Colors.blueAccent`→`colorTheme.primaryColor`, sound `Colors.green`→`colorTheme.primaryColor`, image/file greys→theme, tips `Colors.blueAccent`→primary; quoted-reply reference-style bar+prefix; @mention color→primary.

**Agent B — UIKit conversation + contact lists + avatars** (conversation pkg `conversation_item/list/app_bar/desktop/*/tatal_unread_count`; contact pkg `contact_item/list/app_bar/azlist/group_list/application*/block_list/leading/tab/desktop/*`). Avatar shape by type; row heights/padding §3; remove conversation row divider `Color.fromARGB(8,0,0,0)`; unread badge already themed; selected-row tint `DesignTokens.selectedLight/Dark`; 机器人/全员 tag pills.

**Agent C — UIKit message input + headers** (message pkg `message_input/desktop/*`, `.../mobile/*`, `message_input/{message_reply,forward,select_mode}/*`, `message_header/*`). Fix hint `Color(0xffAEA4A3)`→`colorTheme.secondaryTextColor`; input field fill→theme, radius 8–10; header title 16/600, bottom hairline; toolbar icons→secondary text, send→primary.

**Agent D — UIKit profiles + search + reactions + plugins** (message pkg `group_profile_widgets/*`; contact pkg `user_profile_body/group_management/group_member_list/group_member_info/group_add_member/group_transfer_owner/create_group/group_types_selector/start_c2c_chat/start_group_chat/add_contacts*/add_group*`; search pkg all; message_reaction pkg all; vote_plugin `vote_create/vote_message` `Colors.white`→theme; sticker pkg; text_translate; sound_to_text; robot pkg). Buttons→primary; cards radius 12; fix hardcoded whites/greys.

**Agent E — UIKit common widgets** (`tencent_cloud_chat_common/lib/widgets/avatar/tencent_cloud_chat_avatar.dart` default radius `size*0.28`; `empty_page/*`, `shimmer/*`, `desktop_popup/*`, `desktop_column_menu/*`, `modal/bottom_modal.dart`, `operation_bar/*`, `file_icon/*`, `group_member_selector/*`, `contacts_and_groups_picker/*`, `pull_refresh/*`, `drag_area/*`). Do NOT touch `material_app.dart` / theme color files / `text_style.dart` (foundation owns those). Popups/menus radius 8–12, surfaces, dividers; empty/shimmer greys.

**Agent F — toxee home shell + sidebar + bottom nav** (`lib/ui/home_page.dart`, `lib/ui/settings/sidebar.dart`, `lib/ui/widgets/responsive_scaffold.dart`, `lib/util/responsive_layout.dart` metrics only). Sidebar KEEP ~100px: rail bg `DesignTokens.railLight/Dark`, selected = 3px left bar + tinted bg, icon/label colors. Bottom nav: active `primary` icon+label, inactive tertiary, chat badge `#F54A45`, top hairline, height 56+safe. Coordinate macOS title-bar inset with foundation.

**Agent H — toxee auth + onboarding** (`lib/ui/login_page.dart`, `register_page.dart`, `login_settings_page.dart`, `startup_loading_screen.dart`, `upgrade_required_screen.dart`, `ui/widgets/register_password_strength_bar.dart`, `ui/widgets/first_run_backup_wizard.dart`). Surfaces/buttons/inputs; primary CTA radius 8; card radius 12; password-strength bar success/warning/error tokens.

**Agent I — toxee settings + profile + dialogs + applications** (`lib/ui/settings/settings_page.dart`, `settings/bootstrap_nodes_page.dart`, `profile_page.dart`, `applications/applications_page.dart`, `applications/irc_channel_dialog.dart`, `add_friend_dialog.dart`, `add_group_dialog.dart`). Grouped list-row cards radius 12, chevrons, switches primary; destructive (logout/delete) error; dialogs radius 12.

**Agent J — toxee pairing + call + shared widgets + search** (`lib/ui/pairing/*`, `lib/call/*`, `lib/ui/widgets/{connection_status_banner,error_banner,empty_state_widget,loading_shimmer,bottom_sheet_handle}.dart`, `lib/ui/search/*`). Call UI dark stage, accept=success green, reject=error red; banners/empty/shimmer tokens; search list-row + input.

---

## 6. Rules for every agent
1. **No product name** of the reference design in any code/comment/string/filename (see NAMING RULE). Describe by color/role.
2. **Mobile parity is mandatory.** Fix desktop+mobile pairs; shared Dart covers both — say so.
3. Use `colorTheme.<slot>` in UIKit, `DesignTokens`/`Theme.of(context)` in toxee. No new raw hex unless no token fits.
4. Preserve all behavior, ValueKeys/test keys, gestures, a11y labels. RESTYLE only — no logic/structure removal.
5. Keep `flutter analyze lib --no-fatal-warnings --no-fatal-infos` clean. No file grows past 500 LOC.
6. Light AND dark both correct; text contrast ≥4.5:1; touch targets ≥44px; 150–300ms transitions.
7. Report which files you changed + confirm mobile coverage. Run analyze on your changed files before finishing.
