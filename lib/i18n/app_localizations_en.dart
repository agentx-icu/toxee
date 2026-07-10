// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contacts';

  @override
  String get requests => 'Requests';

  @override
  String get groups => 'Groups';

  @override
  String get settings => 'Settings';

  @override
  String get searchConversations => 'Search by nickname / group / message';

  @override
  String get searchContacts => 'Search contacts';

  @override
  String get searchResults => 'Search results';

  @override
  String get enterKeywordToSearch => 'Enter a keyword to search';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get searchSectionMessages => 'Messages';

  @override
  String get searchSectionConversations => 'Conversations';

  @override
  String get searchHint => 'Search...';

  @override
  String messageCount(int count) {
    return '$count messages';
  }

  @override
  String get searchChatHistory => 'Search Chat History';

  @override
  String searchResultsCount(int count, String keyword) {
    return 'There are $count results for \"$keyword\"';
  }

  @override
  String get openChat => 'Open chat';

  @override
  String relatedChats(int count) {
    return '$count related chats';
  }

  @override
  String get newItem => 'New';

  @override
  String get addFriend => 'Add Friend';

  @override
  String get createGroup => 'Create Group';

  @override
  String get friendUserId => 'Friend User ID (hex)';

  @override
  String get groupNameOptional => 'Group name (optional)';

  @override
  String get typeMessage => 'Type a message';

  @override
  String get messageToGroup => 'Message to group';

  @override
  String get selfId => 'Self ID';

  @override
  String get appearance => 'Appearance';

  @override
  String get general => 'General';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get arabic => 'العربية';

  @override
  String get japanese => '日本語';

  @override
  String get korean => '한국어';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get traditionalChinese => '繁體中文';

  @override
  String get profile => 'Profile';

  @override
  String get nickname => 'Nickname';

  @override
  String get statusMessage => 'Status message';

  @override
  String get saveProfile => 'Save Profile';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get group => 'Group';

  @override
  String get file => 'File';

  @override
  String get audio => 'Audio';

  @override
  String get friendRequestSent => 'Friend request sent';

  @override
  String get joinGroup => 'Join group';

  @override
  String get groupId => 'Group ID';

  @override
  String get createAndOpen => 'Create & Open';

  @override
  String get joinAndOpen => 'Join & Open';

  @override
  String get knownGroups => 'Known groups';

  @override
  String get selectAChat => 'Select a chat';

  @override
  String get photo => 'Photo';

  @override
  String get video => 'Video';

  @override
  String get autoAcceptFriendRequests => 'Auto-accept friend requests';

  @override
  String get autoAcceptFriendRequestsDesc =>
      'Accept incoming friend requests automatically';

  @override
  String get autoAcceptGroupInvites => 'Auto-accept group invitations';

  @override
  String get autoAcceptGroupInvitesDesc =>
      'Accept incoming group invitations automatically';

  @override
  String get bootstrapNodes => 'Bootstrap Nodes';

  @override
  String get currentNode => 'Current Node';

  @override
  String get viewAndTestNodes => 'View and Test Nodes';

  @override
  String get currentlyOnlineNoReconnect =>
      'Currently online, no need to reconnect';

  @override
  String get addOrCreateGroup => 'Add / Create Group';

  @override
  String get joinGroupById => 'Join Group by ID';

  @override
  String get enterGroupId => 'Please enter Group ID';

  @override
  String get requestMessage => 'Request Message';

  @override
  String get groupAlias => 'Local Group Name (optional)';

  @override
  String get joinAction => 'Send Join Request';

  @override
  String get joinSuccess => 'Join request sent';

  @override
  String get joinFailed => 'Failed to join group';

  @override
  String get groupName => 'Group Name';

  @override
  String get enterGroupName => 'Please enter Group Name';

  @override
  String get createAction => 'Create Group';

  @override
  String get createSuccess => 'Group created';

  @override
  String get createFailed => 'Failed to create group';

  @override
  String get joinQueued =>
      'Offline — join request will be sent when you reconnect';

  @override
  String get offlineBanner =>
      'Offline — group operations will be queued and processed when you reconnect.';

  @override
  String get groupType => 'Group Type';

  @override
  String get publicGroup => 'Public';

  @override
  String get privateGroup => 'Private';

  @override
  String get publicGroupHint =>
      'Public group — discoverable on the DHT and joinable by anyone with the chat ID.';

  @override
  String get privateGroupHint =>
      'Private group — invitation-only, not announced on the DHT.';

  @override
  String get conferenceHint =>
      'Legacy conference — older protocol, no roles or persistence.';

  @override
  String get searchHintBody => 'Search contacts, groups, and messages';

  @override
  String get noResultsFoundHint => 'Try a shorter keyword or check spelling';

  @override
  String get createdGroupId => 'New Group ID';

  @override
  String get copyId => 'Copy ID';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get addFailed => 'Add failed';

  @override
  String get enterId => 'Please enter Tox ID';

  @override
  String get invalidLength => 'Invalid ID length';

  @override
  String get invalidCharacters => 'Can only contain hexadecimal characters';

  @override
  String get paste => 'Paste';

  @override
  String get addContactHint => 'Enter the peer Tox address.';

  @override
  String get addFriendInvalidToxIdHint =>
      'Tox address must be 76 hexadecimal characters';

  @override
  String get verificationMessage => 'Verification Message';

  @override
  String get defaultFriendRequestMessage =>
      'Hello, I\'d like to add you as a friend.';

  @override
  String get friendRequestMessageTooLong =>
      'Friend request message cannot exceed 921 characters';

  @override
  String get enterMessage => 'Please enter a message';

  @override
  String get noGroupMembers => 'No members yet';

  @override
  String get autoAcceptedNewFriendRequest => 'Auto-accepted new friend request';

  @override
  String get scanQrCodeToAddContact => 'Scan QR code to add me as contact';

  @override
  String get generateCard => 'Generate Card';

  @override
  String get customCardText => 'Custom card text';

  @override
  String get userId => 'User ID';

  @override
  String get saveImage => 'Save Image';

  @override
  String get copy => 'Copy';

  @override
  String get fileCopiedSuccessfully => 'File copied successfully';

  @override
  String get idCopiedToClipboard => 'ID copied to clipboard';

  @override
  String get establishingEncryptedChannel =>
      'Establishing encrypted channel...';

  @override
  String get checkingUserInfo => 'Checking user information...';

  @override
  String get initializingService => 'Initializing service...';

  @override
  String get loggingIn => 'Logging in...';

  @override
  String get initializingSDK => 'Initializing SDK...';

  @override
  String get updatingProfile => 'Updating profile...';

  @override
  String get initializationCompleted => 'Initialization completed!';

  @override
  String get loadingFriends => 'Loading friends...';

  @override
  String get inProgress => 'In Progress';

  @override
  String get completed => 'Completed';

  @override
  String get personalCard => 'Personal Card';

  @override
  String get appTitle => 'toxee';

  @override
  String get startChat => 'Start Chat';

  @override
  String get pasteServerUserId => 'Paste the server User ID here';

  @override
  String get groupProfile => 'Group Profile';

  @override
  String get invalidGroupId => 'Invalid group ID';

  @override
  String maintainer(String maintainer) {
    return 'Maintainer: $maintainer';
  }

  @override
  String get success => 'Success';

  @override
  String get failed => 'Failed';

  @override
  String error(String error) {
    return 'Error: $error';
  }

  @override
  String get saved => 'Saved';

  @override
  String failedToSave(String error) {
    return 'Failed to save: $error';
  }

  @override
  String copyFailed(String error) {
    return 'Copy failed: $error';
  }

  @override
  String failedToUpdateAvatar(String error) {
    return 'Failed to update avatar: $error';
  }

  @override
  String get failedToLoadQr => 'Failed to load QR';

  @override
  String get helloFromToxee => 'Hello from toxee';

  @override
  String attachFailed(String error) {
    return 'Attach failed: $error';
  }

  @override
  String get autoFriendRequestFromToxee => 'Auto friend request from toxee';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get reconnectConfirmMessage =>
      'Will reconnect using the selected bootstrap node. Continue?';

  @override
  String get reconnectedWaiting => 'Re-logged in, waiting for connection...';

  @override
  String get reconnectWithThisNode => 'Reconnect with this node';

  @override
  String get friendOfflineCannotSendFile =>
      'Friend is offline. Cannot send file. Please wait until they are online.';

  @override
  String get friendOfflineSendCardFailed =>
      'Friend is offline. Failed to send personal card.';

  @override
  String get friendOfflineSendImageFailed =>
      'Friend is offline. Failed to send image.';

  @override
  String get friendOfflineSendVideoFailed =>
      'Friend is offline. Failed to send video.';

  @override
  String get friendOfflineSendFileFailed =>
      'Friend is offline. Failed to send file.';

  @override
  String get userNotInFriendList => 'User is not in your friend list.';

  @override
  String sendFailed(String error) {
    return 'Send failed: $error';
  }

  @override
  String get myId => 'My ID';

  @override
  String get sendPersonalCardToGroup => 'Send Personal Card to Group';

  @override
  String get personalCardSent => 'Personal Card sent';

  @override
  String get sentPersonalCardToGroup => 'Sent Personal Card to group';

  @override
  String get bootstrapNodesTitle => 'Bootstrap Nodes';

  @override
  String get refresh => 'Refresh';

  @override
  String get retry => 'Retry';

  @override
  String lastPing(String seconds) {
    return 'Last ping: ${seconds}s ago';
  }

  @override
  String get testNode => 'Test Node';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountConfirmMessage =>
      'Your account and all data will be permanently deleted and cannot be recovered. Please proceed with caution.';

  @override
  String get delete => 'Delete';

  @override
  String get deleteAccountEnterPasswordToConfirm =>
      'Enter your account password to confirm deletion.';

  @override
  String get deleteAccountTypeWordToConfirm =>
      'Type the word shown below to confirm deletion.';

  @override
  String deleteAccountConfirmWordPrompt(String word) {
    return 'Type the following word in the box below to confirm: $word';
  }

  @override
  String get deleteAccountWrongWord => 'The word you entered is incorrect.';

  @override
  String get applications => 'Applications';

  @override
  String get applicationsComingSoon => 'More applications coming soon...';

  @override
  String get notificationSound => 'Notification Sound';

  @override
  String get notificationSoundDesc =>
      'Play sound for new messages, friend requests, and group requests';

  @override
  String get downloadsDirectory => 'Downloads Directory';

  @override
  String get selectDownloadsDirectory => 'Select Downloads Directory';

  @override
  String get changeDownloadsDirectory => 'Change Downloads Directory';

  @override
  String get downloadsDirectoryDesc =>
      'Set the default directory for file downloads. Received files, audio, and videos will be saved to this directory.';

  @override
  String get downloadsDirectorySet => 'Downloads directory set';

  @override
  String get downloadsDirectoryReset => 'Downloads directory reset to default';

  @override
  String get failedToSelectDirectory => 'Failed to select directory';

  @override
  String get reset => 'Reset';

  @override
  String get autoDownloadSizeLimit => 'Auto Download Size Limit';

  @override
  String get sizeLimitInMB => 'Size Limit (MB)';

  @override
  String get autoDownloadSizeLimitDesc =>
      'Files smaller than this size and all images will be downloaded automatically. Files larger than this size require manual download via the download button.';

  @override
  String get autoDownloadSizeLimitSet => 'Auto download size limit set to';

  @override
  String get invalidSizeLimit =>
      'Invalid size limit, please enter a number between 1 and 10000';

  @override
  String get save => 'Save';

  @override
  String get routeSelection => 'Route Selection';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get canOnlySelectOnlineNode => 'Can only select online nodes';

  @override
  String get canOnlySelectTestedNode =>
      'Can only select successfully tested nodes, please test the node first';

  @override
  String get switchNode => 'Switch Node';

  @override
  String switchNodeConfirm(String node) {
    return 'Are you sure you want to switch to node $node? Reconnection is required after switching.';
  }

  @override
  String get nodeSwitched => 'Node switched, reconnecting...';

  @override
  String get selectThisNode => 'Select this node';

  @override
  String nodeSwitchFailed(String error) {
    return 'Node switch failed: $error';
  }

  @override
  String get ircChannelApp => 'IRC Channel';

  @override
  String get ircChannelAppDesc =>
      'Connect IRC channels to Tox groups for message synchronization';

  @override
  String get install => 'Install';

  @override
  String get uninstall => 'Uninstall';

  @override
  String get ircAppInstalled => 'IRC Channel app installed';

  @override
  String get ircAppUninstalled => 'IRC Channel app uninstalled';

  @override
  String get uninstallIrcApp => 'Uninstall IRC Channel App';

  @override
  String get uninstallIrcAppConfirm =>
      'Are you sure you want to uninstall the IRC Channel app? All IRC channels will be removed and you will leave all IRC groups.';

  @override
  String get addIrcChannel => 'Add Channel';

  @override
  String get ircChannels => 'IRC Channels';

  @override
  String get ircStatusDisconnected => 'Disconnected';

  @override
  String get ircStatusConnecting => 'Connecting';

  @override
  String get ircStatusConnected => 'Connected';

  @override
  String get ircStatusAuthenticating => 'Authenticating';

  @override
  String get ircStatusReconnecting => 'Reconnecting';

  @override
  String get ircStatusError => 'Error';

  @override
  String get ircServerConfig => 'IRC Server Configuration';

  @override
  String get ircServer => 'Server';

  @override
  String get ircPort => 'Port';

  @override
  String get ircUseSasl => 'Use SASL Authentication';

  @override
  String get ircUseSaslDesc =>
      'Use Tox public key for SASL authentication (requires NickServ registration)';

  @override
  String get ircServerRequired => 'IRC server address is required';

  @override
  String get ircConfigSaved => 'IRC configuration saved';

  @override
  String ircChannelAdded(String channel) {
    return 'IRC channel added: $channel';
  }

  @override
  String get ircChannelAddFailed => 'Failed to add IRC channel';

  @override
  String ircChannelAddedNotConnected(String channel) {
    return 'Channel $channel added, but the IRC connection could not be established';
  }

  @override
  String get ircAppInstalledNoLibrary =>
      'IRC app installed, but live IRC is unavailable on this device';

  @override
  String ircChannelRemoved(String channel) {
    return 'IRC channel removed: $channel';
  }

  @override
  String get removeIrcChannel => 'Remove IRC Channel';

  @override
  String removeIrcChannelConfirm(String channel) {
    return 'Are you sure you want to remove $channel? You will leave the corresponding group.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get joinIrcChannel => 'Join IRC Channel';

  @override
  String get ircChannelName => 'IRC Channel Name';

  @override
  String get ircChannelHint => '#channel';

  @override
  String get ircChannelDesc =>
      'Enter the IRC channel name (e.g., #channel). A Tox group will be created for this channel.';

  @override
  String get enterIrcChannel => 'Please enter IRC channel name';

  @override
  String get invalidIrcChannel => 'IRC channel must start with # or &';

  @override
  String get join => 'Join';

  @override
  String get ircAppNotInstalled =>
      'Please install the IRC Channel app from the Applications page first';

  @override
  String get ircChannelPassword => 'Channel Password';

  @override
  String get ircChannelPasswordHint => 'Leave empty if no password';

  @override
  String get ircCustomNickname => 'Custom IRC Nickname';

  @override
  String get ircCustomNicknameHint =>
      'Leave empty to use auto-generated nickname';

  @override
  String deleteAccountFailed(String error) {
    return 'Failed to delete account: $error';
  }

  @override
  String get directorySelectionNotSupported =>
      'Directory selection is not supported on this platform';

  @override
  String failedToSendFriendRequest(String error) {
    return 'Failed to send friend request: $error';
  }

  @override
  String get fileDoesNotExist => 'File does not exist';

  @override
  String get fileIsEmpty => 'File is empty';

  @override
  String failedToSendFile(String label, String error) {
    return 'Failed to send $label: $error';
  }

  @override
  String get noReceivers => 'No receivers yet';

  @override
  String messageReceivers(String count) {
    return 'Message Receivers ($count)';
  }

  @override
  String get close => 'Close';

  @override
  String get nodeNotTestedWarning =>
      'Note: This node has not been tested and may not be connectable.';

  @override
  String get nodeTestFailedWarning =>
      'Note: This node test failed and may not be connectable.';

  @override
  String get nicknameTooLong => 'Nickname too long';

  @override
  String get nicknameCannotBeEmpty => 'Nickname cannot be empty';

  @override
  String get statusMessageTooLong => 'Status message too long';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthFair => 'Fair';

  @override
  String get passwordStrengthGood => 'Good';

  @override
  String get passwordStrengthStrong => 'Strong';

  @override
  String get manualNodeInput => 'Manual Node Input';

  @override
  String get nodeHost => 'Host';

  @override
  String get nodePort => 'Port';

  @override
  String get nodePublicKey => 'Public Key';

  @override
  String get setAsCurrentNode => 'Set as Current Node';

  @override
  String get nodeTestSuccess => 'Node test successful';

  @override
  String get nodeTestFailed => 'Node test failed';

  @override
  String get nodeTestUnavailableBeforeLogin => 'Test unavailable before login';

  @override
  String get failedToStartBootstrapService =>
      'Failed to start bootstrap service';

  @override
  String get invalidNodeInfo =>
      'Please enter valid node information (host, port, and public key)';

  @override
  String get nodeSetSuccess => 'Node set as current successfully';

  @override
  String get bootstrapNodeMode => 'Bootstrap Node Mode';

  @override
  String get manualMode => 'Manual';

  @override
  String get autoMode => 'Auto (Fetch from Web)';

  @override
  String get manualModeDesc => 'Manually specify bootstrap node information';

  @override
  String get autoModeDesc =>
      'Automatically fetch and use bootstrap nodes from web';

  @override
  String get autoModeDescPrefix =>
      'Automatically fetch and use bootstrap nodes from ';

  @override
  String get lanMode => 'LAN Mode';

  @override
  String get lanModeDesc => 'Use local network bootstrap service';

  @override
  String get startLocalBootstrapService => 'Start Local Bootstrap Service';

  @override
  String get stopLocalBootstrapService => 'Stop Local Bootstrap Service';

  @override
  String get bootstrapServiceStatus => 'Service Status';

  @override
  String get serviceRunning => 'Running';

  @override
  String get serviceStopped => 'Stopped';

  @override
  String get scanLanBootstrapServices => 'Scan LAN Bootstrap Services';

  @override
  String get scanLanBootstrapServicesTitle => 'LAN Bootstrap Services';

  @override
  String get scanPort => 'Scan Port';

  @override
  String get startScan => 'Start Scan';

  @override
  String scanningAliveIPs(int current, int total) {
    return 'Scanning alive IPs: $current/$total';
  }

  @override
  String probingBootstrapServices(int current, int total) {
    return 'Probing bootstrap services: $current/$total';
  }

  @override
  String get scanning => 'Scanning...';

  @override
  String get probing => 'Probing...';

  @override
  String aliveIPsFound(int count) {
    return 'Alive IPs found: $count';
  }

  @override
  String get noAliveIPsFound => 'No alive IPs found';

  @override
  String get bootstrapServiceFound => 'Bootstrap service found';

  @override
  String get noBootstrapService => 'No bootstrap service';

  @override
  String get noServicesFound => 'No services found';

  @override
  String get useAsBootstrapNode => 'Use as Bootstrap Node';

  @override
  String get ipAddress => 'IP Address';

  @override
  String get probeStatus => 'Probe Status';

  @override
  String get probeSingleIP => 'Probe this IP';

  @override
  String probingIP(String ip) {
    return 'Probing $ip...';
  }

  @override
  String get refreshAliveIPs => 'Refresh Alive IPs';

  @override
  String get aliveIPsList => 'Alive IPs List';

  @override
  String get notProbedYet => 'Not probed yet';

  @override
  String get probeSuccess => 'Bootstrap service found';

  @override
  String get probeFailed => 'No bootstrap service';

  @override
  String bootstrapServiceRunning(String ip, int port) {
    return 'Bootstrap service running: $ip:$port';
  }

  @override
  String get logOut => 'Log Out';

  @override
  String get logOutConfirm => 'Are you sure you want to log out?';

  @override
  String get autoLogin => 'Auto Login';

  @override
  String get autoLoginEnabled => 'Auto Login: Enabled';

  @override
  String get autoLoginDisabled => 'Auto Login: Disabled';

  @override
  String get autoLoginDesc =>
      'After enabling, you will be automatically logged in when you start the application.';

  @override
  String get disable => 'Disable';

  @override
  String get enable => 'Enable';

  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get registerNewAccount => 'Register new account';

  @override
  String get unnamedAccount => 'Unnamed Account';

  @override
  String get accountInfo => 'Account Info';

  @override
  String get accountManagement => 'Account Management';

  @override
  String get localAccounts => 'Local Accounts';

  @override
  String showMore(int count) {
    return 'Show $count more';
  }

  @override
  String get showLess => 'Show less';

  @override
  String get current => 'Current';

  @override
  String get lastLogin => 'Last Login';

  @override
  String get switchAccount => 'Switch Account';

  @override
  String get exportAccount => 'Export Account';

  @override
  String get exportOptionProfileTox => 'Profile (.tox)';

  @override
  String get exportOptionProfileToxSubtitle => 'qTox compatible, profile only';

  @override
  String get exportOptionFullBackup => 'Full Backup (.zip)';

  @override
  String get exportOptionFullBackupSubtitle =>
      'Profile + chat history + settings';

  @override
  String get importAccount => 'Import Account';

  @override
  String get setPassword => 'Set Password';

  @override
  String get changePassword => 'Change Password';

  @override
  String get enterPasswordToExport => 'Enter password to export account';

  @override
  String get enterPasswordToImport => 'Enter password to import account';

  @override
  String enterPasswordForAccount(String nickname) {
    return 'Enter password for account \"$nickname\"';
  }

  @override
  String get invalidPassword => 'Invalid password';

  @override
  String accountExportedSuccessfully(String filePath) {
    return 'Account exported successfully to: $filePath';
  }

  @override
  String get accountImportedSuccessfully => 'Account imported successfully';

  @override
  String get passwordSetSuccessfully => 'Password set successfully';

  @override
  String get passwordRemoved => 'Password removed';

  @override
  String failedToSwitchAccount(String error) {
    return 'Failed to switch account: $error';
  }

  @override
  String failedToExportAccount(String error) {
    return 'Failed to export account: $error';
  }

  @override
  String failedToImportAccount(String error) {
    return 'Failed to import account: $error';
  }

  @override
  String failedToSetPassword(String error) {
    return 'Failed to set password: $error';
  }

  @override
  String get noAccountToExport => 'No account to export';

  @override
  String get noAccountSelected => 'No account selected';

  @override
  String get accountAlreadyExists => 'Account Already Exists';

  @override
  String get accountAlreadyExistsMessage =>
      'An account with this ID already exists. Do you want to update it?';

  @override
  String get update => 'Update';

  @override
  String switchAccountConfirm(String nickname) {
    return 'Are you sure you want to switch to \"$nickname\"? You will be logged out of the current account.';
  }

  @override
  String get savedAccounts => 'Saved Accounts';

  @override
  String get tapToSelectDoubleTapToLogin =>
      'Tap to select, double-tap to quick login';

  @override
  String get tapToLogIn => 'Tap to log in';

  @override
  String get switchToThisAccount => 'Switch to this account';

  @override
  String get password => 'Password';

  @override
  String get newPassword => 'New Password';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get leaveEmptyToRemovePassword => 'Leave empty to remove password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get never => 'Never';

  @override
  String get justNow => 'Just now';

  @override
  String daysAgo(int count, String plural) {
    return '$count day$plural ago';
  }

  @override
  String hoursAgo(int count, String plural) {
    return '$count hour$plural ago';
  }

  @override
  String minutesAgo(int count, String plural) {
    return '$count minute$plural ago';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn =>
      'This account is already logged in';

  @override
  String get upgradeRequiredTitle => 'Please upgrade the app';

  @override
  String upgradeRequiredMessage(int storedVersion, int currentVersion) {
    return 'Your data was saved by a newer version of the app (data version: $storedVersion). This version supports up to $currentVersion. Please install the latest update to continue.';
  }

  @override
  String get upgradeAppTitle => 'toxee';

  @override
  String get hide => 'Hide';

  @override
  String get pressBackAgainToExit => 'Press back again to exit';

  @override
  String get startupFailed => 'Startup Failed';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get goToLogin => 'Go to Login';

  @override
  String get conference => 'Conference';

  @override
  String get defaultJoinRequestMessage =>
      'Hi, please invite me into this group';

  @override
  String get userNotFoundPleaseRegister =>
      'User not found. Please register first.';

  @override
  String get nicknameDoesNotMatch =>
      'Nickname does not match. Please use the registered nickname or register a new account.';

  @override
  String get accountAlreadyExistsPleaseLogin =>
      'Account already exists. Please login instead or use a different nickname.';

  @override
  String get profileNotFoundImportRestore =>
      'Profile not found for this account. Please import or restore backup.';

  @override
  String get failedToInitializeTIMManager =>
      'Failed to initialize TIMManager SDK';

  @override
  String get failedToGetToxId => 'Failed to get Tox ID';

  @override
  String get failedToGenerateToxId => 'Failed to generate Tox ID';

  @override
  String get registrationCouldNotCreateProfile =>
      'Registration could not create a unique profile. Please try again.';

  @override
  String get importedAccount => 'Imported Account';

  @override
  String get unknown => 'Unknown';

  @override
  String sendingToGroupsNotSupported(String label) {
    return 'Sending $label to groups is not supported yet';
  }

  @override
  String noLabelSelected(String label) {
    return 'No $label selected';
  }

  @override
  String searchSummary(int contacts, int groups, int messages) {
    return 'Found $contacts contacts, $groups groups, $messages message threads';
  }

  @override
  String get searchFailed => 'Search failed, showing partial results';

  @override
  String get callVideoCall => 'Video call';

  @override
  String get callAudioCall => 'Audio call';

  @override
  String get callReject => 'Reject';

  @override
  String get callAccept => 'Accept';

  @override
  String get callRemoteVideo => 'Remote video';

  @override
  String get callUnmute => 'Unmute';

  @override
  String get callMute => 'Mute';

  @override
  String get callVideoOff => 'Video off';

  @override
  String get callVideoOn => 'Video on';

  @override
  String get callSpeakerOff => 'Speaker off';

  @override
  String get callSpeakerOn => 'Speaker on';

  @override
  String get callHangUp => 'Hang up';

  @override
  String get callEnded => 'Call ended';

  @override
  String get callPermissionMicrophoneRequired =>
      'Microphone permission is required to continue the call.';

  @override
  String get callPermissionCameraRequired =>
      'Camera permission is required to continue the call.';

  @override
  String get callPermissionMicrophoneCameraRequired =>
      'Microphone and camera permissions are required to continue the call.';

  @override
  String get callFailedGroupUnsupported => 'Group calls are not supported yet.';

  @override
  String get callFailedSignaling =>
      'Couldn\'t start the call. Please try again.';

  @override
  String get callFailedMediaChannel =>
      'Couldn\'t establish the call\'s media channel.';

  @override
  String get callVideoUnsupportedPlatform =>
      'Video calls aren\'t available on this platform yet (no camera support).';

  @override
  String get callAudioInterrupted =>
      'Audio output changed or was interrupted during the call.';

  @override
  String get callCalling => 'Calling...';

  @override
  String get callMinimize => 'Minimize';

  @override
  String get callReturnToCall => 'Return to call';

  @override
  String get callQualityGood => 'Good connection';

  @override
  String get callQualityMedium => 'Fair connection';

  @override
  String get callQualityPoor => 'Poor connection';

  @override
  String get callQualityUnknown => '—';

  @override
  String get callQualityLabel => 'Call quality';

  @override
  String unreadMessagesSemantics(int count) {
    return '$count unread messages';
  }

  @override
  String matchingMessagesSemantics(int count) {
    return '$count matching messages';
  }

  @override
  String get statusOnline => 'Online';

  @override
  String get statusOffline => 'Offline';

  @override
  String get noIrcChannels => 'No IRC channels';

  @override
  String get joinChannelToGetStarted => 'Join a channel to get started';

  @override
  String ircUsersCount(int count) {
    return 'Users ($count)';
  }

  @override
  String get ircNoUsers => 'No users';

  @override
  String get passwordVisibility => 'Toggle password visibility';

  @override
  String get nicknameHintExample => 'e.g. Alice';

  @override
  String get callAudioRouteSystem =>
      'Audio route managed by system on this platform';

  @override
  String get copyFullToxId => 'Copy full ID';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get idLabel => 'ID:';

  @override
  String errorBannerLabel(String message) {
    return 'Error: $message';
  }

  @override
  String searchResultContactSemantics(String name) {
    return '$name, contact';
  }

  @override
  String searchResultGroupSemantics(String name) {
    return '$name, group';
  }

  @override
  String searchResultMessageSemantics(String name) {
    return '$name, message';
  }

  @override
  String searchResultConversationSemantics(String name) {
    return '$name, conversation';
  }

  @override
  String get importNoFileSelected => 'No file selected';

  @override
  String get importCancelled => 'Cancelled';

  @override
  String get importedAccountDefaultName => 'Imported account';

  @override
  String failedToImport(String error) {
    return 'Failed to import: $error';
  }

  @override
  String get selectConversationEmptyState =>
      'Select a conversation to start chatting';

  @override
  String get newConversationTooltip => 'New conversation';

  @override
  String get pinConversation => 'Pin';

  @override
  String get unpinConversation => 'Unpin';

  @override
  String get markConversationAsRead => 'Mark as read';

  @override
  String get deleteConversationTitle => 'Delete conversation?';

  @override
  String deleteConversationBody(String name) {
    return 'This will remove \"$name\" from your chat list. Message history stays on disk.';
  }

  @override
  String get firstRunBackupWizardTitle => 'Save your account file';

  @override
  String get firstRunBackupWizardBody =>
      'Your account lives only on this device. Save the .tox file somewhere safe (cloud storage, password manager, USB stick). Without it, losing this device means losing your account and all your contacts permanently.';

  @override
  String get firstRunBackupWizardExportNow => 'Export now';

  @override
  String get firstRunBackupWizardLater => 'I\'ll do it later';

  @override
  String get firstRunBackupWizardDismissTitle => 'Skip backup?';

  @override
  String get firstRunBackupWizardDismissBody =>
      'If you lose this device, you will lose your account and all contacts. There is no recovery.';

  @override
  String get firstRunBackupWizardDismissConfirm => 'I understand, continue';

  @override
  String firstRunBackupWizardExportFailed(String error) {
    return 'Couldn\'t save your account file: $error';
  }

  @override
  String get restoreFromToxFile => 'Restore from .tox file';

  @override
  String restoreFromToxFileSuccess(String nickname) {
    return 'Restored account: $nickname';
  }

  @override
  String get restoreFromToxFileInvalidFile =>
      'This file doesn\'t look like a valid Tox profile.';

  @override
  String get pairDeviceHostTitle => 'Pair another device';

  @override
  String get pairDeviceClientTitle => 'Pair with another device';

  @override
  String get pairingHostInstructions =>
      'Open toxee on your other device, choose \"Pair with another device\", and scan this QR code.';

  @override
  String get pairingClientScanInstructions =>
      'Point your camera at the QR code on your other device.';

  @override
  String get pairingClientPasteInstructions =>
      'Camera scanning isn\'t supported on this device. Paste the pairing URL shown on your other device below.';

  @override
  String get pairingPasteUrlLabel => 'Pairing URL';

  @override
  String get pairingConnectButton => 'Connect';

  @override
  String get pairingWaitingForPeer =>
      'Waiting for the other device to connect…';

  @override
  String get pairingVerifyCodeHeader =>
      'Verify both devices show the same code';

  @override
  String get pairingVerifyCodeInstructions =>
      'If the code matches what\'s shown on your other device, tap below. If they differ, cancel — someone may be intercepting the connection.';

  @override
  String get pairingCodesMatch => 'The codes match';

  @override
  String get pairingHostCompleted =>
      'Account sent. The other device now has your account.';

  @override
  String get pairingClientCompleted => 'Account received. You\'re paired.';

  @override
  String get pairingCancelled => 'Pairing cancelled.';

  @override
  String get pairingTimeout => 'Pairing timed out — try again.';

  @override
  String pairingNetworkError(String detail) {
    return 'Network error during pairing: $detail';
  }

  @override
  String pairingProtocolError(String detail) {
    return 'Pairing handshake failed: $detail';
  }

  @override
  String pairingInvalidUrl(String detail) {
    return 'That QR code isn\'t a valid pairing invitation: $detail';
  }

  @override
  String get pairingDecryptFailed =>
      'Couldn\'t decrypt the received profile. The pairing may have been tampered with — try again on a network you trust.';

  @override
  String get pairingNoLanInterface =>
      'No LAN network detected. Connect to WiFi or Ethernet and try again.';

  @override
  String get pairThisAccountToAnotherDevice =>
      'Pair this account to another device';

  @override
  String get pairWithAnotherDevice =>
      'Pair with another device that has my account';

  @override
  String get devicesSectionTitle => 'Devices';

  @override
  String get done => 'Done';

  @override
  String get runtimeForegroundTitle => 'Toxee is running';

  @override
  String get runtimeForegroundBody =>
      'Staying connected so you can receive messages and calls.';

  @override
  String get runtimeForegroundSettingsLabel => 'Notification settings';

  @override
  String get runtimeForegroundCallTitle => 'Call in progress';

  @override
  String get runtimeForegroundCallBody =>
      'Toxee is keeping your call connected.';

  @override
  String runtimeForegroundCallBodyWithCaller(String name) {
    return 'Call with $name';
  }
}
