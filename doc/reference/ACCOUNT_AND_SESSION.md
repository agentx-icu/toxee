[简体中文](./ACCOUNT_AND_SESSION.zh-CN.md)

# toxee Account and Session


This document describes the current account lifecycle implementation of toxee, focusing on automatic login, manual login, registration, switching accounts, logging out, deleting accounts, and how to handle password-protected profiles.

## 1. Division of roles

- `AccountService`: Unified encapsulation of account initialization, registration, destruction, and deletion.
- `_StartupGate`: Automatic login portal, responsible for the first screen startup sequence and connection waiting.
- `LoginPage`: Quick login for existing accounts, new account entrance, and account deletion on the login page.
- `AccountSwitcher`: Reuse `AccountService` when switching accounts on the settings page.
- `SettingsPage`: UI entrance for logging out, exporting, and deleting accounts.
- `SessionPasswordStore`: Only save the password of this session in memory to re-encrypt `tox_profile.tox` when exiting.

## 2. Account initialization

The main entrance for existing accounts is `AccountService.initializeServiceForAccount(...)`.

Core steps:

1. Set up the current account `toxId`.
2. Migrate the old directory to a storage structure isolated by account.
3. Parse historical messages, offline queues, received file directories, and avatar directories.
4. Restore or migrate `tox_profile.tox`.
5. If the account has a password, first decrypt the profile and put the password into `SessionPasswordStore`.
6. Create `FfiChatService` and inject `SharedPreferencesAdapter`, `AppLoggerAdapter`, and `BootstrapNodesAdapter`.
7. Execute `init(profileContents: ...)`, `login(...)`, `updateSelfProfile(...)`.
8. Depending on the caller's needs, decide whether to `startPolling()` immediately.

## 3. Startup path

### Automatic login

The current order of `_StartupGate._decide()` in `main.dart` is:

1. Read the automatic login configuration and current account.
2. Restore the account through `AccountService.initializeServiceForAccount(..., startPolling: false)`.
3. Call `FakeUIKit.startWithFfi(service)` to start the UIKit side state in advance.
4. Call `_initTIMManagerSDK()`.
5. Call `service.startPolling()`.
6. Wait for successful connection or timeout.
7. Preload friend and contact status.
8. Navigate to `HomePage(service)`.

### Manual login

There is already an account in `LoginPage` and `AccountService.initializeServiceForAccount(...)` will be reused first. Only historical compatible paths will manually create `FfiChatService` and execute `init()`, `login()`, `updateSelfProfile()`, `startPolling()`.

## 4. Registration path

`AccountService.registerNewAccount(...)` current process:

1. Clear the current account and ensure that the empty state is loaded during new registration.
2. Initialize `FfiChatService` in the temporary directory and generate a new `toxId`.
3. Rename the temporary profile directory to the official account directory.
4. Update nickname and status message.
5. Write the account list, current account and metadata.
6. If a password is set, first encrypt and then decrypt the profile for verification, and then reinitialize the service according to the account isolation directory.
7. Finally start `startPolling()` and return to the new service.

## 5. Switch, exit and delete

### Switch account

`AccountSwitcher.switchAccount(...)` will:

1. Call `AccountService.teardownCurrentSession(...)` to destroy the old session.
2. Verify the target account password.
3. Recall `initializeServiceForAccount(...)` to restore the target account.
4. Navigate to the new `HomePage`.

### Log out

`SettingsPage._logout()` will call `AccountService.teardownCurrentSession(service: widget.service)`, then clear the current account ID and return to the login page.

### Delete account

- Setting page deletion: calling `AccountService.deleteAccountCompletely(...)` will teardown first, then clean up prefs, account list, profile directory and account data directory.
- Login page deletion: Call `AccountService.deleteAccountWithoutService(...)` because there is no running service at this time.

## 6. Session destruction sequence

`AccountService.teardownCurrentSession(...)` The current sequence is as follows:

1. `FakeUIKit.instance.dispose()`
2. If the current Platform is `Tim2ToxSdkPlatform`, first `dispose()`, and then restore to the default `MethodChannelTencentCloudChatSdk`
3. Clear `ChatDataProviderRegistry` and `ChatMessageProviderRegistry`
4. Clean up static caches such as `GroupMemberListDebouncer` and `IrcAppManager`
5. `service.dispose()`
6. If the current session uses a password, re-encrypt `tox_profile.tox` on disk
7. Clean up `SessionPasswordStore`

The key point of this sequence is: `FakeUIKit` must be destroyed before `Tim2ToxSdkPlatform`, otherwise the cleanup of the call bridge and signaling listener will lose dependencies.

## 7. Storage model

Each account has an independent running directory:

- `tox_profile.tox`
- `chat_history/`
- `offline_message_queue.json`
- `avatars/`
- `file_recv/`

These paths are generated uniformly by `AppPaths` to prevent multiple accounts from sharing the same historical data or cache.

Full account backup uses a `.zip` archive containing `tox_profile.tox`, `chat_history/`, `offline_message_queue.json`, `avatars/`, and `metadata.json`. Export rewrites account-local avatar paths to `@account_data/...` and backfills missing `friend_avatar_path_<friendId>` metadata, including runtime files named like `friend_<id>_avatar_<timestamp>.<ext>`. Import preflights archive paths under `chat_history/` and `avatars/`, rejects `../`, absolute paths, Windows drive prefixes, and backslash paths, and only then restores the profile, history, offline queue, and scoped prefs.

## 8. Password and profile encryption

- The password hash is saved in the persistent configuration and used to verify the account password.
- The session plaintext password is only stored in the `SessionPasswordStore` memory and will not be lost to disk.
- If the profile is found to be encrypted when logging in, it will be decrypted first.
- If there is a password for this session when logging out, `tox_profile.tox` will be re-encrypted.
- There will be no re-encryption when deleting the account, because the profile will be deleted directly.

## 9. Related documents

- [HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.md)
- [../architecture/MAINTAINER_ARCHITECTURE.md](../architecture/MAINTAINER_ARCHITECTURE.md)
- [CALLING_AND_EXTENSIONS.md](CALLING_AND_EXTENSIONS.md)
