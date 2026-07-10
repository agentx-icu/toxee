import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'i18n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Search conversations by nickname, group name, or message content
  ///
  /// In en, this message translates to:
  /// **'Search by nickname / group / message'**
  String get searchConversations;

  /// No description provided for @searchContacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get searchContacts;

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResults;

  /// No description provided for @enterKeywordToSearch.
  ///
  /// In en, this message translates to:
  /// **'Enter a keyword to search'**
  String get enterKeywordToSearch;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @searchSectionMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get searchSectionMessages;

  /// No description provided for @searchSectionConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get searchSectionConversations;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchHint;

  /// No description provided for @messageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} messages'**
  String messageCount(int count);

  /// No description provided for @searchChatHistory.
  ///
  /// In en, this message translates to:
  /// **'Search Chat History'**
  String get searchChatHistory;

  /// No description provided for @searchResultsCount.
  ///
  /// In en, this message translates to:
  /// **'There are {count} results for \"{keyword}\"'**
  String searchResultsCount(int count, String keyword);

  /// No description provided for @openChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get openChat;

  /// No description provided for @relatedChats.
  ///
  /// In en, this message translates to:
  /// **'{count} related chats'**
  String relatedChats(int count);

  /// Label for new item button
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newItem;

  /// No description provided for @addFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get addFriend;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get createGroup;

  /// Label for friend user ID input field
  ///
  /// In en, this message translates to:
  /// **'Friend User ID (hex)'**
  String get friendUserId;

  /// No description provided for @groupNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Group name (optional)'**
  String get groupNameOptional;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get typeMessage;

  /// No description provided for @messageToGroup.
  ///
  /// In en, this message translates to:
  /// **'Message to group'**
  String get messageToGroup;

  /// No description provided for @selfId.
  ///
  /// In en, this message translates to:
  /// **'Self ID'**
  String get selfId;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// No description provided for @japanese.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get japanese;

  /// No description provided for @korean.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get korean;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get simplifiedChinese;

  /// No description provided for @traditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get traditionalChinese;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @statusMessage.
  ///
  /// In en, this message translates to:
  /// **'Status message'**
  String get statusMessage;

  /// No description provided for @saveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save Profile'**
  String get saveProfile;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @friendRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent'**
  String get friendRequestSent;

  /// No description provided for @joinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get joinGroup;

  /// No description provided for @groupId.
  ///
  /// In en, this message translates to:
  /// **'Group ID'**
  String get groupId;

  /// No description provided for @createAndOpen.
  ///
  /// In en, this message translates to:
  /// **'Create & Open'**
  String get createAndOpen;

  /// No description provided for @joinAndOpen.
  ///
  /// In en, this message translates to:
  /// **'Join & Open'**
  String get joinAndOpen;

  /// No description provided for @knownGroups.
  ///
  /// In en, this message translates to:
  /// **'Known groups'**
  String get knownGroups;

  /// No description provided for @selectAChat.
  ///
  /// In en, this message translates to:
  /// **'Select a chat'**
  String get selectAChat;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// Setting to automatically accept incoming friend requests
  ///
  /// In en, this message translates to:
  /// **'Auto-accept friend requests'**
  String get autoAcceptFriendRequests;

  /// No description provided for @autoAcceptFriendRequestsDesc.
  ///
  /// In en, this message translates to:
  /// **'Accept incoming friend requests automatically'**
  String get autoAcceptFriendRequestsDesc;

  /// Setting to automatically accept incoming group invitations
  ///
  /// In en, this message translates to:
  /// **'Auto-accept group invitations'**
  String get autoAcceptGroupInvites;

  /// No description provided for @autoAcceptGroupInvitesDesc.
  ///
  /// In en, this message translates to:
  /// **'Accept incoming group invitations automatically'**
  String get autoAcceptGroupInvitesDesc;

  /// No description provided for @bootstrapNodes.
  ///
  /// In en, this message translates to:
  /// **'Bootstrap Nodes'**
  String get bootstrapNodes;

  /// No description provided for @currentNode.
  ///
  /// In en, this message translates to:
  /// **'Current Node'**
  String get currentNode;

  /// No description provided for @viewAndTestNodes.
  ///
  /// In en, this message translates to:
  /// **'View and Test Nodes'**
  String get viewAndTestNodes;

  /// No description provided for @currentlyOnlineNoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Currently online, no need to reconnect'**
  String get currentlyOnlineNoReconnect;

  /// No description provided for @addOrCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Add / Create Group'**
  String get addOrCreateGroup;

  /// No description provided for @joinGroupById.
  ///
  /// In en, this message translates to:
  /// **'Join Group by ID'**
  String get joinGroupById;

  /// No description provided for @enterGroupId.
  ///
  /// In en, this message translates to:
  /// **'Please enter Group ID'**
  String get enterGroupId;

  /// No description provided for @requestMessage.
  ///
  /// In en, this message translates to:
  /// **'Request Message'**
  String get requestMessage;

  /// No description provided for @groupAlias.
  ///
  /// In en, this message translates to:
  /// **'Local Group Name (optional)'**
  String get groupAlias;

  /// No description provided for @joinAction.
  ///
  /// In en, this message translates to:
  /// **'Send Join Request'**
  String get joinAction;

  /// No description provided for @joinSuccess.
  ///
  /// In en, this message translates to:
  /// **'Join request sent'**
  String get joinSuccess;

  /// No description provided for @joinFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to join group'**
  String get joinFailed;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get groupName;

  /// No description provided for @enterGroupName.
  ///
  /// In en, this message translates to:
  /// **'Please enter Group Name'**
  String get enterGroupName;

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get createAction;

  /// No description provided for @createSuccess.
  ///
  /// In en, this message translates to:
  /// **'Group created'**
  String get createSuccess;

  /// No description provided for @createFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create group'**
  String get createFailed;

  /// Banner / snackbar message shown when a group join request was queued because the device is offline
  ///
  /// In en, this message translates to:
  /// **'Offline — join request will be sent when you reconnect'**
  String get joinQueued;

  /// Inline banner inside Add/Create Group dialog when not connected
  ///
  /// In en, this message translates to:
  /// **'Offline — group operations will be queued and processed when you reconnect.'**
  String get offlineBanner;

  /// Label above the Public/Private/Conference segmented selector
  ///
  /// In en, this message translates to:
  /// **'Group Type'**
  String get groupType;

  /// Segmented-button label for a Tox public group (DHT-announced)
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get publicGroup;

  /// Segmented-button label for a Tox private group (invitation-only)
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privateGroup;

  /// Description shown below the segmented selector when Public is chosen
  ///
  /// In en, this message translates to:
  /// **'Public group — discoverable on the DHT and joinable by anyone with the chat ID.'**
  String get publicGroupHint;

  /// Description shown below the segmented selector when Private is chosen
  ///
  /// In en, this message translates to:
  /// **'Private group — invitation-only, not announced on the DHT.'**
  String get privateGroupHint;

  /// Description shown below the segmented selector when Conference is chosen
  ///
  /// In en, this message translates to:
  /// **'Legacy conference — older protocol, no roles or persistence.'**
  String get conferenceHint;

  /// Empty-state subtitle on the search screen before any keyword is entered
  ///
  /// In en, this message translates to:
  /// **'Search contacts, groups, and messages'**
  String get searchHintBody;

  /// Empty-state subtitle on the search screen when the keyword returned no matches
  ///
  /// In en, this message translates to:
  /// **'Try a shorter keyword or check spelling'**
  String get noResultsFoundHint;

  /// No description provided for @createdGroupId.
  ///
  /// In en, this message translates to:
  /// **'New Group ID'**
  String get createdGroupId;

  /// No description provided for @copyId.
  ///
  /// In en, this message translates to:
  /// **'Copy ID'**
  String get copyId;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @addFailed.
  ///
  /// In en, this message translates to:
  /// **'Add failed'**
  String get addFailed;

  /// No description provided for @enterId.
  ///
  /// In en, this message translates to:
  /// **'Please enter Tox ID'**
  String get enterId;

  /// No description provided for @invalidLength.
  ///
  /// In en, this message translates to:
  /// **'Invalid ID length'**
  String get invalidLength;

  /// No description provided for @invalidCharacters.
  ///
  /// In en, this message translates to:
  /// **'Can only contain hexadecimal characters'**
  String get invalidCharacters;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @addContactHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the peer Tox address.'**
  String get addContactHint;

  /// Validator error shown in AddFriend dialog when input is not exactly 76 hex chars
  ///
  /// In en, this message translates to:
  /// **'Tox address must be 76 hexadecimal characters'**
  String get addFriendInvalidToxIdHint;

  /// No description provided for @verificationMessage.
  ///
  /// In en, this message translates to:
  /// **'Verification Message'**
  String get verificationMessage;

  /// Default message for friend request
  ///
  /// In en, this message translates to:
  /// **'Hello, I\'d like to add you as a friend.'**
  String get defaultFriendRequestMessage;

  /// Error message when friend request message exceeds maximum length
  ///
  /// In en, this message translates to:
  /// **'Friend request message cannot exceed 921 characters'**
  String get friendRequestMessageTooLong;

  /// Error message when message is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter a message'**
  String get enterMessage;

  /// Empty state shown when a group has zero loaded members
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get noGroupMembers;

  /// No description provided for @autoAcceptedNewFriendRequest.
  ///
  /// In en, this message translates to:
  /// **'Auto-accepted new friend request'**
  String get autoAcceptedNewFriendRequest;

  /// Text shown on QR code card
  ///
  /// In en, this message translates to:
  /// **'Scan QR code to add me as contact'**
  String get scanQrCodeToAddContact;

  /// Button text to generate QR code card
  ///
  /// In en, this message translates to:
  /// **'Generate Card'**
  String get generateCard;

  /// Label for custom text input field below QR code
  ///
  /// In en, this message translates to:
  /// **'Custom card text'**
  String get customCardText;

  /// No description provided for @userId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get userId;

  /// No description provided for @saveImage.
  ///
  /// In en, this message translates to:
  /// **'Save Image'**
  String get saveImage;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @fileCopiedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'File copied successfully'**
  String get fileCopiedSuccessfully;

  /// No description provided for @idCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'ID copied to clipboard'**
  String get idCopiedToClipboard;

  /// Loading message shown when initializing Tox connection
  ///
  /// In en, this message translates to:
  /// **'Establishing encrypted channel...'**
  String get establishingEncryptedChannel;

  /// Message shown when checking user information during startup
  ///
  /// In en, this message translates to:
  /// **'Checking user information...'**
  String get checkingUserInfo;

  /// Message shown when initializing the service during startup
  ///
  /// In en, this message translates to:
  /// **'Initializing service...'**
  String get initializingService;

  /// Message shown when logging in during startup
  ///
  /// In en, this message translates to:
  /// **'Logging in...'**
  String get loggingIn;

  /// Message shown when initializing SDK during startup
  ///
  /// In en, this message translates to:
  /// **'Initializing SDK...'**
  String get initializingSDK;

  /// Message shown when updating profile during startup
  ///
  /// In en, this message translates to:
  /// **'Updating profile...'**
  String get updatingProfile;

  /// Message shown when initialization is completed
  ///
  /// In en, this message translates to:
  /// **'Initialization completed!'**
  String get initializationCompleted;

  /// Message shown when loading friends information during startup
  ///
  /// In en, this message translates to:
  /// **'Loading friends...'**
  String get loadingFriends;

  /// Label shown for steps that are currently in progress
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get inProgress;

  /// Label shown for steps that have been completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// Button label to send personal QR code card
  ///
  /// In en, this message translates to:
  /// **'Personal Card'**
  String get personalCard;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'toxee'**
  String get appTitle;

  /// No description provided for @startChat.
  ///
  /// In en, this message translates to:
  /// **'Start Chat'**
  String get startChat;

  /// No description provided for @pasteServerUserId.
  ///
  /// In en, this message translates to:
  /// **'Paste the server User ID here'**
  String get pasteServerUserId;

  /// No description provided for @groupProfile.
  ///
  /// In en, this message translates to:
  /// **'Group Profile'**
  String get groupProfile;

  /// No description provided for @invalidGroupId.
  ///
  /// In en, this message translates to:
  /// **'Invalid group ID'**
  String get invalidGroupId;

  /// Bootstrap node maintainer label
  ///
  /// In en, this message translates to:
  /// **'Maintainer: {maintainer}'**
  String maintainer(String maintainer);

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// Error message with error details
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error(String error);

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// Error message when save operation fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save: {error}'**
  String failedToSave(String error);

  /// Error message when copy operation fails
  ///
  /// In en, this message translates to:
  /// **'Copy failed: {error}'**
  String copyFailed(String error);

  /// Error message when avatar update fails
  ///
  /// In en, this message translates to:
  /// **'Failed to update avatar: {error}'**
  String failedToUpdateAvatar(String error);

  /// No description provided for @failedToLoadQr.
  ///
  /// In en, this message translates to:
  /// **'Failed to load QR'**
  String get failedToLoadQr;

  /// No description provided for @helloFromToxee.
  ///
  /// In en, this message translates to:
  /// **'Hello from toxee'**
  String get helloFromToxee;

  /// Error message when attachment fails
  ///
  /// In en, this message translates to:
  /// **'Attach failed: {error}'**
  String attachFailed(String error);

  /// No description provided for @autoFriendRequestFromToxee.
  ///
  /// In en, this message translates to:
  /// **'Auto friend request from toxee'**
  String get autoFriendRequestFromToxee;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @reconnectConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Will reconnect using the selected bootstrap node. Continue?'**
  String get reconnectConfirmMessage;

  /// No description provided for @reconnectedWaiting.
  ///
  /// In en, this message translates to:
  /// **'Re-logged in, waiting for connection...'**
  String get reconnectedWaiting;

  /// No description provided for @reconnectWithThisNode.
  ///
  /// In en, this message translates to:
  /// **'Reconnect with this node'**
  String get reconnectWithThisNode;

  /// No description provided for @friendOfflineCannotSendFile.
  ///
  /// In en, this message translates to:
  /// **'Friend is offline. Cannot send file. Please wait until they are online.'**
  String get friendOfflineCannotSendFile;

  /// No description provided for @friendOfflineSendCardFailed.
  ///
  /// In en, this message translates to:
  /// **'Friend is offline. Failed to send personal card.'**
  String get friendOfflineSendCardFailed;

  /// No description provided for @friendOfflineSendImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Friend is offline. Failed to send image.'**
  String get friendOfflineSendImageFailed;

  /// No description provided for @friendOfflineSendVideoFailed.
  ///
  /// In en, this message translates to:
  /// **'Friend is offline. Failed to send video.'**
  String get friendOfflineSendVideoFailed;

  /// No description provided for @friendOfflineSendFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Friend is offline. Failed to send file.'**
  String get friendOfflineSendFileFailed;

  /// No description provided for @userNotInFriendList.
  ///
  /// In en, this message translates to:
  /// **'User is not in your friend list.'**
  String get userNotInFriendList;

  /// Error message when send operation fails
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String sendFailed(String error);

  /// No description provided for @myId.
  ///
  /// In en, this message translates to:
  /// **'My ID'**
  String get myId;

  /// No description provided for @sendPersonalCardToGroup.
  ///
  /// In en, this message translates to:
  /// **'Send Personal Card to Group'**
  String get sendPersonalCardToGroup;

  /// No description provided for @personalCardSent.
  ///
  /// In en, this message translates to:
  /// **'Personal Card sent'**
  String get personalCardSent;

  /// No description provided for @sentPersonalCardToGroup.
  ///
  /// In en, this message translates to:
  /// **'Sent Personal Card to group'**
  String get sentPersonalCardToGroup;

  /// No description provided for @bootstrapNodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Bootstrap Nodes'**
  String get bootstrapNodesTitle;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Last ping time for bootstrap node
  ///
  /// In en, this message translates to:
  /// **'Last ping: {seconds}s ago'**
  String lastPing(String seconds);

  /// Button text to test current bootstrap node
  ///
  /// In en, this message translates to:
  /// **'Test Node'**
  String get testNode;

  /// Button text for account deletion
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// Confirmation message for account deletion
  ///
  /// In en, this message translates to:
  /// **'Your account and all data will be permanently deleted and cannot be recovered. Please proceed with caution.'**
  String get deleteAccountConfirmMessage;

  /// Confirmation button text for account deletion
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteAccountEnterPasswordToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Enter your account password to confirm deletion.'**
  String get deleteAccountEnterPasswordToConfirm;

  /// No description provided for @deleteAccountTypeWordToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type the word shown below to confirm deletion.'**
  String get deleteAccountTypeWordToConfirm;

  /// No description provided for @deleteAccountConfirmWordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Type the following word in the box below to confirm: {word}'**
  String deleteAccountConfirmWordPrompt(String word);

  /// No description provided for @deleteAccountWrongWord.
  ///
  /// In en, this message translates to:
  /// **'The word you entered is incorrect.'**
  String get deleteAccountWrongWord;

  /// Applications page title
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get applications;

  /// Message shown on applications page when no apps are available
  ///
  /// In en, this message translates to:
  /// **'More applications coming soon...'**
  String get applicationsComingSoon;

  /// Title for notification sound setting
  ///
  /// In en, this message translates to:
  /// **'Notification Sound'**
  String get notificationSound;

  /// Description for notification sound setting
  ///
  /// In en, this message translates to:
  /// **'Play sound for new messages, friend requests, and group requests'**
  String get notificationSoundDesc;

  /// No description provided for @downloadsDirectory.
  ///
  /// In en, this message translates to:
  /// **'Downloads Directory'**
  String get downloadsDirectory;

  /// No description provided for @selectDownloadsDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select Downloads Directory'**
  String get selectDownloadsDirectory;

  /// No description provided for @changeDownloadsDirectory.
  ///
  /// In en, this message translates to:
  /// **'Change Downloads Directory'**
  String get changeDownloadsDirectory;

  /// No description provided for @downloadsDirectoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Set the default directory for file downloads. Received files, audio, and videos will be saved to this directory.'**
  String get downloadsDirectoryDesc;

  /// No description provided for @downloadsDirectorySet.
  ///
  /// In en, this message translates to:
  /// **'Downloads directory set'**
  String get downloadsDirectorySet;

  /// No description provided for @downloadsDirectoryReset.
  ///
  /// In en, this message translates to:
  /// **'Downloads directory reset to default'**
  String get downloadsDirectoryReset;

  /// No description provided for @failedToSelectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Failed to select directory'**
  String get failedToSelectDirectory;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @autoDownloadSizeLimit.
  ///
  /// In en, this message translates to:
  /// **'Auto Download Size Limit'**
  String get autoDownloadSizeLimit;

  /// No description provided for @sizeLimitInMB.
  ///
  /// In en, this message translates to:
  /// **'Size Limit (MB)'**
  String get sizeLimitInMB;

  /// No description provided for @autoDownloadSizeLimitDesc.
  ///
  /// In en, this message translates to:
  /// **'Files smaller than this size and all images will be downloaded automatically. Files larger than this size require manual download via the download button.'**
  String get autoDownloadSizeLimitDesc;

  /// No description provided for @autoDownloadSizeLimitSet.
  ///
  /// In en, this message translates to:
  /// **'Auto download size limit set to'**
  String get autoDownloadSizeLimitSet;

  /// No description provided for @invalidSizeLimit.
  ///
  /// In en, this message translates to:
  /// **'Invalid size limit, please enter a number between 1 and 10000'**
  String get invalidSizeLimit;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Button text to open route selection page
  ///
  /// In en, this message translates to:
  /// **'Route Selection'**
  String get routeSelection;

  /// Online status text
  ///
  /// In en, this message translates to:
  /// **'ONLINE'**
  String get online;

  /// Offline status text
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get offline;

  /// Error message when trying to select offline node
  ///
  /// In en, this message translates to:
  /// **'Can only select online nodes'**
  String get canOnlySelectOnlineNode;

  /// Error message when trying to select untested node
  ///
  /// In en, this message translates to:
  /// **'Can only select successfully tested nodes, please test the node first'**
  String get canOnlySelectTestedNode;

  /// Title for node switch confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Switch Node'**
  String get switchNode;

  /// Confirmation message for node switch
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to switch to node {node}? Reconnection is required after switching.'**
  String switchNodeConfirm(String node);

  /// Message shown after successful node switch
  ///
  /// In en, this message translates to:
  /// **'Node switched, reconnecting...'**
  String get nodeSwitched;

  /// Tooltip for node selection button
  ///
  /// In en, this message translates to:
  /// **'Select this node'**
  String get selectThisNode;

  /// Error message when node switch fails
  ///
  /// In en, this message translates to:
  /// **'Node switch failed: {error}'**
  String nodeSwitchFailed(String error);

  /// Title for IRC Channel application
  ///
  /// In en, this message translates to:
  /// **'IRC Channel'**
  String get ircChannelApp;

  /// Description for IRC Channel application
  ///
  /// In en, this message translates to:
  /// **'Connect IRC channels to Tox groups for message synchronization'**
  String get ircChannelAppDesc;

  /// Button text to install an application
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// Button text to uninstall an application
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get uninstall;

  /// Message shown when IRC app is installed
  ///
  /// In en, this message translates to:
  /// **'IRC Channel app installed'**
  String get ircAppInstalled;

  /// Message shown when IRC app is uninstalled
  ///
  /// In en, this message translates to:
  /// **'IRC Channel app uninstalled'**
  String get ircAppUninstalled;

  /// Title for uninstall confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Uninstall IRC Channel App'**
  String get uninstallIrcApp;

  /// Confirmation message for uninstalling IRC app
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to uninstall the IRC Channel app? All IRC channels will be removed and you will leave all IRC groups.'**
  String get uninstallIrcAppConfirm;

  /// Button text to add an IRC channel
  ///
  /// In en, this message translates to:
  /// **'Add Channel'**
  String get addIrcChannel;

  /// Label for list of IRC channels
  ///
  /// In en, this message translates to:
  /// **'IRC Channels'**
  String get ircChannels;

  /// IRC channel connection status: disconnected
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get ircStatusDisconnected;

  /// IRC channel connection status: connecting
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get ircStatusConnecting;

  /// IRC channel connection status: connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get ircStatusConnected;

  /// IRC channel connection status: authenticating
  ///
  /// In en, this message translates to:
  /// **'Authenticating'**
  String get ircStatusAuthenticating;

  /// IRC channel connection status: reconnecting
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get ircStatusReconnecting;

  /// IRC channel connection status: error
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get ircStatusError;

  /// Title for IRC server configuration section
  ///
  /// In en, this message translates to:
  /// **'IRC Server Configuration'**
  String get ircServerConfig;

  /// Label for IRC server address input
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get ircServer;

  /// Label for IRC server port input
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get ircPort;

  /// Label for SASL authentication toggle
  ///
  /// In en, this message translates to:
  /// **'Use SASL Authentication'**
  String get ircUseSasl;

  /// Description for SASL authentication option
  ///
  /// In en, this message translates to:
  /// **'Use Tox public key for SASL authentication (requires NickServ registration)'**
  String get ircUseSaslDesc;

  /// Error message when IRC server address is empty
  ///
  /// In en, this message translates to:
  /// **'IRC server address is required'**
  String get ircServerRequired;

  /// Success message when IRC configuration is saved
  ///
  /// In en, this message translates to:
  /// **'IRC configuration saved'**
  String get ircConfigSaved;

  /// Message shown when IRC channel is added
  ///
  /// In en, this message translates to:
  /// **'IRC channel added: {channel}'**
  String ircChannelAdded(String channel);

  /// Error message when adding IRC channel fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add IRC channel'**
  String get ircChannelAddFailed;

  /// Shown when the channel/group was created but the live IRC connection could not be started (e.g. IRC not available on this platform)
  ///
  /// In en, this message translates to:
  /// **'Channel {channel} added, but the IRC connection could not be established'**
  String ircChannelAddedNotConnected(String channel);

  /// Shown after install when the native IRC client library could not be loaded on this platform
  ///
  /// In en, this message translates to:
  /// **'IRC app installed, but live IRC is unavailable on this device'**
  String get ircAppInstalledNoLibrary;

  /// Message shown when IRC channel is removed
  ///
  /// In en, this message translates to:
  /// **'IRC channel removed: {channel}'**
  String ircChannelRemoved(String channel);

  /// Title for remove channel confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Remove IRC Channel'**
  String get removeIrcChannel;

  /// Confirmation message for removing IRC channel
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove {channel}? You will leave the corresponding group.'**
  String removeIrcChannelConfirm(String channel);

  /// Button text to remove an item
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Button text and dialog title for joining IRC channel
  ///
  /// In en, this message translates to:
  /// **'Join IRC Channel'**
  String get joinIrcChannel;

  /// Label for IRC channel name input field
  ///
  /// In en, this message translates to:
  /// **'IRC Channel Name'**
  String get ircChannelName;

  /// Placeholder text for IRC channel input
  ///
  /// In en, this message translates to:
  /// **'#channel'**
  String get ircChannelHint;

  /// Description text for IRC channel dialog
  ///
  /// In en, this message translates to:
  /// **'Enter the IRC channel name (e.g., #channel). A Tox group will be created for this channel.'**
  String get ircChannelDesc;

  /// Validation error message for empty IRC channel name
  ///
  /// In en, this message translates to:
  /// **'Please enter IRC channel name'**
  String get enterIrcChannel;

  /// Validation error message for invalid IRC channel format
  ///
  /// In en, this message translates to:
  /// **'IRC channel must start with # or &'**
  String get invalidIrcChannel;

  /// Button text to join
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// Error message when trying to join IRC channel without installing the app
  ///
  /// In en, this message translates to:
  /// **'Please install the IRC Channel app from the Applications page first'**
  String get ircAppNotInstalled;

  /// Label for IRC channel password input field
  ///
  /// In en, this message translates to:
  /// **'Channel Password'**
  String get ircChannelPassword;

  /// Placeholder text for IRC channel password input
  ///
  /// In en, this message translates to:
  /// **'Leave empty if no password'**
  String get ircChannelPasswordHint;

  /// Label for custom IRC nickname input field
  ///
  /// In en, this message translates to:
  /// **'Custom IRC Nickname'**
  String get ircCustomNickname;

  /// Hint text for custom IRC nickname input field
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use auto-generated nickname'**
  String get ircCustomNicknameHint;

  /// Error message when account deletion fails
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account: {error}'**
  String deleteAccountFailed(String error);

  /// Message shown when directory selection is not supported on the platform
  ///
  /// In en, this message translates to:
  /// **'Directory selection is not supported on this platform'**
  String get directorySelectionNotSupported;

  /// Error message when friend request sending fails
  ///
  /// In en, this message translates to:
  /// **'Failed to send friend request: {error}'**
  String failedToSendFriendRequest(String error);

  /// Error message when file does not exist
  ///
  /// In en, this message translates to:
  /// **'File does not exist'**
  String get fileDoesNotExist;

  /// Error message when file is empty
  ///
  /// In en, this message translates to:
  /// **'File is empty'**
  String get fileIsEmpty;

  /// Error message when file sending fails
  ///
  /// In en, this message translates to:
  /// **'Failed to send {label}: {error}'**
  String failedToSendFile(String label, String error);

  /// Message shown when there are no message receivers
  ///
  /// In en, this message translates to:
  /// **'No receivers yet'**
  String get noReceivers;

  /// Title for message receivers dialog
  ///
  /// In en, this message translates to:
  /// **'Message Receivers ({count})'**
  String messageReceivers(String count);

  /// Button text to close dialog
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Warning message when selecting untested node
  ///
  /// In en, this message translates to:
  /// **'Note: This node has not been tested and may not be connectable.'**
  String get nodeNotTestedWarning;

  /// Warning message when selecting failed node
  ///
  /// In en, this message translates to:
  /// **'Note: This node test failed and may not be connectable.'**
  String get nodeTestFailedWarning;

  /// Error message when nickname is too long
  ///
  /// In en, this message translates to:
  /// **'Nickname too long'**
  String get nicknameTooLong;

  /// Validation error when nickname field is empty
  ///
  /// In en, this message translates to:
  /// **'Nickname cannot be empty'**
  String get nicknameCannotBeEmpty;

  /// Error message when status message is too long
  ///
  /// In en, this message translates to:
  /// **'Status message too long'**
  String get statusMessageTooLong;

  /// Caption under the register password-strength bar for a weak password
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get passwordStrengthWeak;

  /// Caption under the register password-strength bar for a fair password
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get passwordStrengthFair;

  /// Caption under the register password-strength bar for a good password
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get passwordStrengthGood;

  /// Caption under the register password-strength bar for a strong password
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get passwordStrengthStrong;

  /// Title for manual node input section
  ///
  /// In en, this message translates to:
  /// **'Manual Node Input'**
  String get manualNodeInput;

  /// Label for node host input field
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get nodeHost;

  /// Label for node port input field
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get nodePort;

  /// Label for node public key input field
  ///
  /// In en, this message translates to:
  /// **'Public Key'**
  String get nodePublicKey;

  /// Button text to set manually entered node as current
  ///
  /// In en, this message translates to:
  /// **'Set as Current Node'**
  String get setAsCurrentNode;

  /// Message shown when node test succeeds
  ///
  /// In en, this message translates to:
  /// **'Node test successful'**
  String get nodeTestSuccess;

  /// Message shown when node test fails
  ///
  /// In en, this message translates to:
  /// **'Node test failed'**
  String get nodeTestFailed;

  /// Message shown when node test cannot run before login (no live FFI session)
  ///
  /// In en, this message translates to:
  /// **'Test unavailable before login'**
  String get nodeTestUnavailableBeforeLogin;

  /// Snackbar text shown when starting the local LAN bootstrap service fails
  ///
  /// In en, this message translates to:
  /// **'Failed to start bootstrap service'**
  String get failedToStartBootstrapService;

  /// Error message when node information is invalid
  ///
  /// In en, this message translates to:
  /// **'Please enter valid node information (host, port, and public key)'**
  String get invalidNodeInfo;

  /// Message shown when node is successfully set as current
  ///
  /// In en, this message translates to:
  /// **'Node set as current successfully'**
  String get nodeSetSuccess;

  /// Title for bootstrap node mode selection
  ///
  /// In en, this message translates to:
  /// **'Bootstrap Node Mode'**
  String get bootstrapNodeMode;

  /// Manual bootstrap node mode option
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manualMode;

  /// Auto bootstrap node mode option that fetches from web
  ///
  /// In en, this message translates to:
  /// **'Auto (Fetch from Web)'**
  String get autoMode;

  /// Description for manual mode
  ///
  /// In en, this message translates to:
  /// **'Manually specify bootstrap node information'**
  String get manualModeDesc;

  /// Description for auto mode
  ///
  /// In en, this message translates to:
  /// **'Automatically fetch and use bootstrap nodes from web'**
  String get autoModeDesc;

  /// Prefix text for auto mode description with clickable link
  ///
  /// In en, this message translates to:
  /// **'Automatically fetch and use bootstrap nodes from '**
  String get autoModeDescPrefix;

  /// LAN bootstrap node mode option
  ///
  /// In en, this message translates to:
  /// **'LAN Mode'**
  String get lanMode;

  /// Description for LAN mode
  ///
  /// In en, this message translates to:
  /// **'Use local network bootstrap service'**
  String get lanModeDesc;

  /// Button text to start local bootstrap service
  ///
  /// In en, this message translates to:
  /// **'Start Local Bootstrap Service'**
  String get startLocalBootstrapService;

  /// Button text to stop local bootstrap service
  ///
  /// In en, this message translates to:
  /// **'Stop Local Bootstrap Service'**
  String get stopLocalBootstrapService;

  /// Label for bootstrap service status
  ///
  /// In en, this message translates to:
  /// **'Service Status'**
  String get bootstrapServiceStatus;

  /// Status text when service is running
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get serviceRunning;

  /// Status text when service is stopped
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get serviceStopped;

  /// Button text to scan LAN bootstrap services
  ///
  /// In en, this message translates to:
  /// **'Scan LAN Bootstrap Services'**
  String get scanLanBootstrapServices;

  /// Title for LAN bootstrap scan page
  ///
  /// In en, this message translates to:
  /// **'LAN Bootstrap Services'**
  String get scanLanBootstrapServicesTitle;

  /// Label for scan port input field
  ///
  /// In en, this message translates to:
  /// **'Scan Port'**
  String get scanPort;

  /// Button text to start scanning
  ///
  /// In en, this message translates to:
  /// **'Start Scan'**
  String get startScan;

  /// Progress text for scanning alive IPs
  ///
  /// In en, this message translates to:
  /// **'Scanning alive IPs: {current}/{total}'**
  String scanningAliveIPs(int current, int total);

  /// Progress text for probing bootstrap services
  ///
  /// In en, this message translates to:
  /// **'Probing bootstrap services: {current}/{total}'**
  String probingBootstrapServices(int current, int total);

  /// Text shown when scanning
  ///
  /// In en, this message translates to:
  /// **'Scanning...'**
  String get scanning;

  /// Text shown when probing
  ///
  /// In en, this message translates to:
  /// **'Probing...'**
  String get probing;

  /// Text showing number of alive IPs found
  ///
  /// In en, this message translates to:
  /// **'Alive IPs found: {count}'**
  String aliveIPsFound(int count);

  /// Message when no alive IPs are found
  ///
  /// In en, this message translates to:
  /// **'No alive IPs found'**
  String get noAliveIPsFound;

  /// Message when bootstrap service is found
  ///
  /// In en, this message translates to:
  /// **'Bootstrap service found'**
  String get bootstrapServiceFound;

  /// Message when no bootstrap service is found
  ///
  /// In en, this message translates to:
  /// **'No bootstrap service'**
  String get noBootstrapService;

  /// Message when no bootstrap services are found during scan
  ///
  /// In en, this message translates to:
  /// **'No services found'**
  String get noServicesFound;

  /// Button text to use service as bootstrap node
  ///
  /// In en, this message translates to:
  /// **'Use as Bootstrap Node'**
  String get useAsBootstrapNode;

  /// Label for IP address
  ///
  /// In en, this message translates to:
  /// **'IP Address'**
  String get ipAddress;

  /// Label for probe status
  ///
  /// In en, this message translates to:
  /// **'Probe Status'**
  String get probeStatus;

  /// Button tooltip to probe single IP
  ///
  /// In en, this message translates to:
  /// **'Probe this IP'**
  String get probeSingleIP;

  /// Text shown when probing an IP
  ///
  /// In en, this message translates to:
  /// **'Probing {ip}...'**
  String probingIP(String ip);

  /// Button tooltip to refresh alive IPs list
  ///
  /// In en, this message translates to:
  /// **'Refresh Alive IPs'**
  String get refreshAliveIPs;

  /// Title for alive IPs list
  ///
  /// In en, this message translates to:
  /// **'Alive IPs List'**
  String get aliveIPsList;

  /// Status text when IP has not been probed
  ///
  /// In en, this message translates to:
  /// **'Not probed yet'**
  String get notProbedYet;

  /// Message when probe succeeds
  ///
  /// In en, this message translates to:
  /// **'Bootstrap service found'**
  String get probeSuccess;

  /// Message when probe fails
  ///
  /// In en, this message translates to:
  /// **'No bootstrap service'**
  String get probeFailed;

  /// Status text when bootstrap service is running
  ///
  /// In en, this message translates to:
  /// **'Bootstrap service running: {ip}:{port}'**
  String bootstrapServiceRunning(String ip, int port);

  /// Button text to log out
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// Confirmation message when logging out
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logOutConfirm;

  /// Label for auto login setting
  ///
  /// In en, this message translates to:
  /// **'Auto Login'**
  String get autoLogin;

  /// Status text when auto login is enabled
  ///
  /// In en, this message translates to:
  /// **'Auto Login: Enabled'**
  String get autoLoginEnabled;

  /// Status text when auto login is disabled
  ///
  /// In en, this message translates to:
  /// **'Auto Login: Disabled'**
  String get autoLoginDisabled;

  /// Description for auto login feature
  ///
  /// In en, this message translates to:
  /// **'After enabling, you will be automatically logged in when you start the application.'**
  String get autoLoginDesc;

  /// Button text to disable auto login
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// Button text to enable auto login
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// Button text to login
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// Button text to register
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// Label for register new account list item
  ///
  /// In en, this message translates to:
  /// **'Register new account'**
  String get registerNewAccount;

  /// Display name when account has no nickname
  ///
  /// In en, this message translates to:
  /// **'Unnamed Account'**
  String get unnamedAccount;

  /// Title for account information section
  ///
  /// In en, this message translates to:
  /// **'Account Info'**
  String get accountInfo;

  /// Title for account management section
  ///
  /// In en, this message translates to:
  /// **'Account Management'**
  String get accountManagement;

  /// Label for local accounts list
  ///
  /// In en, this message translates to:
  /// **'Local Accounts'**
  String get localAccounts;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String showMore(int count);

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// Label for current account
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// Label for last login time
  ///
  /// In en, this message translates to:
  /// **'Last Login'**
  String get lastLogin;

  /// Button text to switch account
  ///
  /// In en, this message translates to:
  /// **'Switch Account'**
  String get switchAccount;

  /// Button text to export account
  ///
  /// In en, this message translates to:
  /// **'Export Account'**
  String get exportAccount;

  /// Export format option: profile only
  ///
  /// In en, this message translates to:
  /// **'Profile (.tox)'**
  String get exportOptionProfileTox;

  /// No description provided for @exportOptionProfileToxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'qTox compatible, profile only'**
  String get exportOptionProfileToxSubtitle;

  /// Export format option: full backup
  ///
  /// In en, this message translates to:
  /// **'Full Backup (.zip)'**
  String get exportOptionFullBackup;

  /// No description provided for @exportOptionFullBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Profile + chat history + settings'**
  String get exportOptionFullBackupSubtitle;

  /// Button text to import account
  ///
  /// In en, this message translates to:
  /// **'Import Account'**
  String get importAccount;

  /// Button text to set password
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get setPassword;

  /// Title for change password dialog
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// Prompt for password when exporting account
  ///
  /// In en, this message translates to:
  /// **'Enter password to export account'**
  String get enterPasswordToExport;

  /// Prompt for password when importing account
  ///
  /// In en, this message translates to:
  /// **'Enter password to import account'**
  String get enterPasswordToImport;

  /// Prompt for password for specific account
  ///
  /// In en, this message translates to:
  /// **'Enter password for account \"{nickname}\"'**
  String enterPasswordForAccount(String nickname);

  /// Error message for invalid password
  ///
  /// In en, this message translates to:
  /// **'Invalid password'**
  String get invalidPassword;

  /// Success message when account is exported
  ///
  /// In en, this message translates to:
  /// **'Account exported successfully to: {filePath}'**
  String accountExportedSuccessfully(String filePath);

  /// Success message when account is imported
  ///
  /// In en, this message translates to:
  /// **'Account imported successfully'**
  String get accountImportedSuccessfully;

  /// Success message when password is set
  ///
  /// In en, this message translates to:
  /// **'Password set successfully'**
  String get passwordSetSuccessfully;

  /// Success message when password is removed
  ///
  /// In en, this message translates to:
  /// **'Password removed'**
  String get passwordRemoved;

  /// Error message when account switch fails
  ///
  /// In en, this message translates to:
  /// **'Failed to switch account: {error}'**
  String failedToSwitchAccount(String error);

  /// Error message when account export fails
  ///
  /// In en, this message translates to:
  /// **'Failed to export account: {error}'**
  String failedToExportAccount(String error);

  /// Error message when account import fails
  ///
  /// In en, this message translates to:
  /// **'Failed to import account: {error}'**
  String failedToImportAccount(String error);

  /// Error message when setting password fails
  ///
  /// In en, this message translates to:
  /// **'Failed to set password: {error}'**
  String failedToSetPassword(String error);

  /// Error message when no account is available to export
  ///
  /// In en, this message translates to:
  /// **'No account to export'**
  String get noAccountToExport;

  /// Error message when no account is selected
  ///
  /// In en, this message translates to:
  /// **'No account selected'**
  String get noAccountSelected;

  /// Title for dialog when account already exists
  ///
  /// In en, this message translates to:
  /// **'Account Already Exists'**
  String get accountAlreadyExists;

  /// Message when account already exists
  ///
  /// In en, this message translates to:
  /// **'An account with this ID already exists. Do you want to update it?'**
  String get accountAlreadyExistsMessage;

  /// Button text to update account
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// Confirmation message when switching account
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to switch to \"{nickname}\"? You will be logged out of the current account.'**
  String switchAccountConfirm(String nickname);

  /// Title for saved accounts list
  ///
  /// In en, this message translates to:
  /// **'Saved Accounts'**
  String get savedAccounts;

  /// Hint text for account selection
  ///
  /// In en, this message translates to:
  /// **'Tap to select, double-tap to quick login'**
  String get tapToSelectDoubleTapToLogin;

  /// Hint text: tap saved account to log in
  ///
  /// In en, this message translates to:
  /// **'Tap to log in'**
  String get tapToLogIn;

  /// Tooltip for switch account button
  ///
  /// In en, this message translates to:
  /// **'Switch to this account'**
  String get switchToThisAccount;

  /// Label for password input field
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Label for new password input
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// Label for confirm password input
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// Hint for password input when changing password
  ///
  /// In en, this message translates to:
  /// **'Leave empty to remove password'**
  String get leaveEmptyToRemovePassword;

  /// Error message when passwords don't match
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// Text for never logged in
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// Text for just logged in
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// Text for days ago
  ///
  /// In en, this message translates to:
  /// **'{count} day{plural} ago'**
  String daysAgo(int count, String plural);

  /// Text for hours ago
  ///
  /// In en, this message translates to:
  /// **'{count} hour{plural} ago'**
  String hoursAgo(int count, String plural);

  /// Text for minutes ago
  ///
  /// In en, this message translates to:
  /// **'{count} minute{plural} ago'**
  String minutesAgo(int count, String plural);

  /// Message when trying to switch to current account
  ///
  /// In en, this message translates to:
  /// **'This account is already logged in'**
  String get thisAccountIsAlreadyLoggedIn;

  /// Title on upgrade required screen
  ///
  /// In en, this message translates to:
  /// **'Please upgrade the app'**
  String get upgradeRequiredTitle;

  /// Message on upgrade required screen
  ///
  /// In en, this message translates to:
  /// **'Your data was saved by a newer version of the app (data version: {storedVersion}). This version supports up to {currentVersion}. Please install the latest update to continue.'**
  String upgradeRequiredMessage(int storedVersion, int currentVersion);

  /// App title on upgrade required screen
  ///
  /// In en, this message translates to:
  /// **'toxee'**
  String get upgradeAppTitle;

  /// Tooltip to hide sidebar
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// SnackBar message when user presses back once; press again to exit app
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackAgainToExit;

  /// Error page title when startup fails
  ///
  /// In en, this message translates to:
  /// **'Startup Failed'**
  String get startupFailed;

  /// Fallback when error message is null
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// Button to go to login from startup error
  ///
  /// In en, this message translates to:
  /// **'Go to Login'**
  String get goToLogin;

  /// Group type option for conference
  ///
  /// In en, this message translates to:
  /// **'Conference'**
  String get conference;

  /// Default message when requesting to join a group
  ///
  /// In en, this message translates to:
  /// **'Hi, please invite me into this group'**
  String get defaultJoinRequestMessage;

  /// No description provided for @userNotFoundPleaseRegister.
  ///
  /// In en, this message translates to:
  /// **'User not found. Please register first.'**
  String get userNotFoundPleaseRegister;

  /// No description provided for @nicknameDoesNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Nickname does not match. Please use the registered nickname or register a new account.'**
  String get nicknameDoesNotMatch;

  /// No description provided for @accountAlreadyExistsPleaseLogin.
  ///
  /// In en, this message translates to:
  /// **'Account already exists. Please login instead or use a different nickname.'**
  String get accountAlreadyExistsPleaseLogin;

  /// No description provided for @profileNotFoundImportRestore.
  ///
  /// In en, this message translates to:
  /// **'Profile not found for this account. Please import or restore backup.'**
  String get profileNotFoundImportRestore;

  /// No description provided for @failedToInitializeTIMManager.
  ///
  /// In en, this message translates to:
  /// **'Failed to initialize TIMManager SDK'**
  String get failedToInitializeTIMManager;

  /// No description provided for @failedToGetToxId.
  ///
  /// In en, this message translates to:
  /// **'Failed to get Tox ID'**
  String get failedToGetToxId;

  /// No description provided for @failedToGenerateToxId.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate Tox ID'**
  String get failedToGenerateToxId;

  /// No description provided for @registrationCouldNotCreateProfile.
  ///
  /// In en, this message translates to:
  /// **'Registration could not create a unique profile. Please try again.'**
  String get registrationCouldNotCreateProfile;

  /// No description provided for @importedAccount.
  ///
  /// In en, this message translates to:
  /// **'Imported Account'**
  String get importedAccount;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @sendingToGroupsNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Sending {label} to groups is not supported yet'**
  String sendingToGroupsNotSupported(String label);

  /// No description provided for @noLabelSelected.
  ///
  /// In en, this message translates to:
  /// **'No {label} selected'**
  String noLabelSelected(String label);

  /// No description provided for @searchSummary.
  ///
  /// In en, this message translates to:
  /// **'Found {contacts} contacts, {groups} groups, {messages} message threads'**
  String searchSummary(int contacts, int groups, int messages);

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed, showing partial results'**
  String get searchFailed;

  /// No description provided for @callVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get callVideoCall;

  /// No description provided for @callAudioCall.
  ///
  /// In en, this message translates to:
  /// **'Audio call'**
  String get callAudioCall;

  /// No description provided for @callReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get callReject;

  /// No description provided for @callAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get callAccept;

  /// No description provided for @callRemoteVideo.
  ///
  /// In en, this message translates to:
  /// **'Remote video'**
  String get callRemoteVideo;

  /// No description provided for @callUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get callUnmute;

  /// No description provided for @callMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get callMute;

  /// No description provided for @callVideoOff.
  ///
  /// In en, this message translates to:
  /// **'Video off'**
  String get callVideoOff;

  /// No description provided for @callVideoOn.
  ///
  /// In en, this message translates to:
  /// **'Video on'**
  String get callVideoOn;

  /// No description provided for @callSpeakerOff.
  ///
  /// In en, this message translates to:
  /// **'Speaker off'**
  String get callSpeakerOff;

  /// No description provided for @callSpeakerOn.
  ///
  /// In en, this message translates to:
  /// **'Speaker on'**
  String get callSpeakerOn;

  /// No description provided for @callHangUp.
  ///
  /// In en, this message translates to:
  /// **'Hang up'**
  String get callHangUp;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @callPermissionMicrophoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to continue the call.'**
  String get callPermissionMicrophoneRequired;

  /// No description provided for @callPermissionCameraRequired.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required to continue the call.'**
  String get callPermissionCameraRequired;

  /// No description provided for @callPermissionMicrophoneCameraRequired.
  ///
  /// In en, this message translates to:
  /// **'Microphone and camera permissions are required to continue the call.'**
  String get callPermissionMicrophoneCameraRequired;

  /// No description provided for @callFailedGroupUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Group calls are not supported yet.'**
  String get callFailedGroupUnsupported;

  /// No description provided for @callFailedSignaling.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the call. Please try again.'**
  String get callFailedSignaling;

  /// No description provided for @callFailedMediaChannel.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t establish the call\'s media channel.'**
  String get callFailedMediaChannel;

  /// No description provided for @callVideoUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Video calls aren\'t available on this platform yet (no camera support).'**
  String get callVideoUnsupportedPlatform;

  /// No description provided for @callAudioInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Audio output changed or was interrupted during the call.'**
  String get callAudioInterrupted;

  /// No description provided for @callCalling.
  ///
  /// In en, this message translates to:
  /// **'Calling...'**
  String get callCalling;

  /// No description provided for @callMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get callMinimize;

  /// No description provided for @callReturnToCall.
  ///
  /// In en, this message translates to:
  /// **'Return to call'**
  String get callReturnToCall;

  /// No description provided for @callQualityGood.
  ///
  /// In en, this message translates to:
  /// **'Good connection'**
  String get callQualityGood;

  /// No description provided for @callQualityMedium.
  ///
  /// In en, this message translates to:
  /// **'Fair connection'**
  String get callQualityMedium;

  /// No description provided for @callQualityPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor connection'**
  String get callQualityPoor;

  /// No description provided for @callQualityUnknown.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get callQualityUnknown;

  /// No description provided for @callQualityLabel.
  ///
  /// In en, this message translates to:
  /// **'Call quality'**
  String get callQualityLabel;

  /// No description provided for @unreadMessagesSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count} unread messages'**
  String unreadMessagesSemantics(int count);

  /// No description provided for @matchingMessagesSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count} matching messages'**
  String matchingMessagesSemantics(int count);

  /// Online status label (title case)
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// Offline status label (title case)
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// Empty state title when no IRC channels are joined
  ///
  /// In en, this message translates to:
  /// **'No IRC channels'**
  String get noIrcChannels;

  /// Empty state subtitle for IRC channels
  ///
  /// In en, this message translates to:
  /// **'Join a channel to get started'**
  String get joinChannelToGetStarted;

  /// No description provided for @ircUsersCount.
  ///
  /// In en, this message translates to:
  /// **'Users ({count})'**
  String ircUsersCount(int count);

  /// No description provided for @ircNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No users'**
  String get ircNoUsers;

  /// Tooltip on the show/hide button next to a password field
  ///
  /// In en, this message translates to:
  /// **'Toggle password visibility'**
  String get passwordVisibility;

  /// Concrete example placeholder for the nickname field
  ///
  /// In en, this message translates to:
  /// **'e.g. Alice'**
  String get nicknameHintExample;

  /// Tooltip on a disabled audio-route button when the OS handles routing
  ///
  /// In en, this message translates to:
  /// **'Audio route managed by system on this platform'**
  String get callAudioRouteSystem;

  /// Tooltip on the copy button for a full Tox ID
  ///
  /// In en, this message translates to:
  /// **'Copy full ID'**
  String get copyFullToxId;

  /// Theme mode option: follow system setting
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Theme mode option: light
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Theme mode option: dark
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Inline label prefix shown before an ID value
  ///
  /// In en, this message translates to:
  /// **'ID:'**
  String get idLabel;

  /// Screen reader label for the error banner live region
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String errorBannerLabel(String message);

  /// No description provided for @searchResultContactSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}, contact'**
  String searchResultContactSemantics(String name);

  /// No description provided for @searchResultGroupSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}, group'**
  String searchResultGroupSemantics(String name);

  /// No description provided for @searchResultMessageSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}, message'**
  String searchResultMessageSemantics(String name);

  /// No description provided for @searchResultConversationSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}, conversation'**
  String searchResultConversationSemantics(String name);

  /// No description provided for @importNoFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get importNoFileSelected;

  /// No description provided for @importCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get importCancelled;

  /// No description provided for @importedAccountDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Imported account'**
  String get importedAccountDefaultName;

  /// No description provided for @failedToImport.
  ///
  /// In en, this message translates to:
  /// **'Failed to import: {error}'**
  String failedToImport(String error);

  /// Empty-state shown in the chat detail pane of the master-detail layout on tablet/desktop before any conversation is selected
  ///
  /// In en, this message translates to:
  /// **'Select a conversation to start chatting'**
  String get selectConversationEmptyState;

  /// Tooltip on the New Entry button (compose/start a new conversation)
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get newConversationTooltip;

  /// Context-menu action — pin a conversation to the top of the list
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinConversation;

  /// Context-menu action — remove a conversation from the pinned section
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinConversation;

  /// Context-menu action — clear the unread badge on a conversation
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markConversationAsRead;

  /// Title of the confirmation dialog when deleting a conversation
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get deleteConversationTitle;

  /// Body of the confirmation dialog when deleting a conversation
  ///
  /// In en, this message translates to:
  /// **'This will remove \"{name}\" from your chat list. Message history stays on disk.'**
  String deleteConversationBody(String name);

  /// Title of the first-run wizard shown after successful registration, prompting the user to back up their .tox file
  ///
  /// In en, this message translates to:
  /// **'Save your account file'**
  String get firstRunBackupWizardTitle;

  /// Body text of the first-run backup wizard explaining the data-loss consequence
  ///
  /// In en, this message translates to:
  /// **'Your account lives only on this device. Save the .tox file somewhere safe (cloud storage, password manager, USB stick). Without it, losing this device means losing your account and all your contacts permanently.'**
  String get firstRunBackupWizardBody;

  /// Primary action button on the first-run backup wizard — opens the file save dialog
  ///
  /// In en, this message translates to:
  /// **'Export now'**
  String get firstRunBackupWizardExportNow;

  /// Secondary action on the first-run backup wizard — opens the data-loss-consequence confirmation
  ///
  /// In en, this message translates to:
  /// **'I\'ll do it later'**
  String get firstRunBackupWizardLater;

  /// Title of the secondary confirmation when the user picks "I'll do it later" on the first-run backup wizard
  ///
  /// In en, this message translates to:
  /// **'Skip backup?'**
  String get firstRunBackupWizardDismissTitle;

  /// Body text of the data-loss confirmation when dismissing the first-run backup wizard
  ///
  /// In en, this message translates to:
  /// **'If you lose this device, you will lose your account and all contacts. There is no recovery.'**
  String get firstRunBackupWizardDismissBody;

  /// Destructive confirmation button on the dismiss-the-wizard dialog
  ///
  /// In en, this message translates to:
  /// **'I understand, continue'**
  String get firstRunBackupWizardDismissConfirm;

  /// Error message shown inline in the first-run backup wizard when the export call fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your account file: {error}'**
  String firstRunBackupWizardExportFailed(String error);

  /// Top-level action on the login page — restores an account from a .tox file (e.g. after device loss)
  ///
  /// In en, this message translates to:
  /// **'Restore from .tox file'**
  String get restoreFromToxFile;

  /// Toast message after a successful .tox restore
  ///
  /// In en, this message translates to:
  /// **'Restored account: {nickname}'**
  String restoreFromToxFileSuccess(String nickname);

  /// Error shown when the user picks a file that isn't a valid .tox profile
  ///
  /// In en, this message translates to:
  /// **'This file doesn\'t look like a valid Tox profile.'**
  String get restoreFromToxFileInvalidFile;

  /// AppBar title on the pairing-host (sender) page
  ///
  /// In en, this message translates to:
  /// **'Pair another device'**
  String get pairDeviceHostTitle;

  /// AppBar title on the pairing-client (receiver) page
  ///
  /// In en, this message translates to:
  /// **'Pair with another device'**
  String get pairDeviceClientTitle;

  /// No description provided for @pairingHostInstructions.
  ///
  /// In en, this message translates to:
  /// **'Open toxee on your other device, choose \"Pair with another device\", and scan this QR code.'**
  String get pairingHostInstructions;

  /// No description provided for @pairingClientScanInstructions.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at the QR code on your other device.'**
  String get pairingClientScanInstructions;

  /// No description provided for @pairingClientPasteInstructions.
  ///
  /// In en, this message translates to:
  /// **'Camera scanning isn\'t supported on this device. Paste the pairing URL shown on your other device below.'**
  String get pairingClientPasteInstructions;

  /// No description provided for @pairingPasteUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Pairing URL'**
  String get pairingPasteUrlLabel;

  /// No description provided for @pairingConnectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get pairingConnectButton;

  /// No description provided for @pairingWaitingForPeer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the other device to connect…'**
  String get pairingWaitingForPeer;

  /// No description provided for @pairingVerifyCodeHeader.
  ///
  /// In en, this message translates to:
  /// **'Verify both devices show the same code'**
  String get pairingVerifyCodeHeader;

  /// No description provided for @pairingVerifyCodeInstructions.
  ///
  /// In en, this message translates to:
  /// **'If the code matches what\'s shown on your other device, tap below. If they differ, cancel — someone may be intercepting the connection.'**
  String get pairingVerifyCodeInstructions;

  /// No description provided for @pairingCodesMatch.
  ///
  /// In en, this message translates to:
  /// **'The codes match'**
  String get pairingCodesMatch;

  /// No description provided for @pairingHostCompleted.
  ///
  /// In en, this message translates to:
  /// **'Account sent. The other device now has your account.'**
  String get pairingHostCompleted;

  /// No description provided for @pairingClientCompleted.
  ///
  /// In en, this message translates to:
  /// **'Account received. You\'re paired.'**
  String get pairingClientCompleted;

  /// No description provided for @pairingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Pairing cancelled.'**
  String get pairingCancelled;

  /// No description provided for @pairingTimeout.
  ///
  /// In en, this message translates to:
  /// **'Pairing timed out — try again.'**
  String get pairingTimeout;

  /// No description provided for @pairingNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Network error during pairing: {detail}'**
  String pairingNetworkError(String detail);

  /// No description provided for @pairingProtocolError.
  ///
  /// In en, this message translates to:
  /// **'Pairing handshake failed: {detail}'**
  String pairingProtocolError(String detail);

  /// No description provided for @pairingInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'That QR code isn\'t a valid pairing invitation: {detail}'**
  String pairingInvalidUrl(String detail);

  /// No description provided for @pairingDecryptFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t decrypt the received profile. The pairing may have been tampered with — try again on a network you trust.'**
  String get pairingDecryptFailed;

  /// No description provided for @pairingNoLanInterface.
  ///
  /// In en, this message translates to:
  /// **'No LAN network detected. Connect to WiFi or Ethernet and try again.'**
  String get pairingNoLanInterface;

  /// Settings → Devices entry on the host (sender) flow
  ///
  /// In en, this message translates to:
  /// **'Pair this account to another device'**
  String get pairThisAccountToAnotherDevice;

  /// Login page entry on the client (receiver) flow
  ///
  /// In en, this message translates to:
  /// **'Pair with another device that has my account'**
  String get pairWithAnotherDevice;

  /// Settings section header for device-pairing
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesSectionTitle;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Title of the persistent Android foreground-service notification while the app is in the background keeping Tox polling alive.
  ///
  /// In en, this message translates to:
  /// **'Toxee is running'**
  String get runtimeForegroundTitle;

  /// Body of the persistent Android foreground-service notification (dataSync mode).
  ///
  /// In en, this message translates to:
  /// **'Staying connected so you can receive messages and calls.'**
  String get runtimeForegroundBody;

  /// Action button on the persistent foreground-service notification that opens system notification settings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get runtimeForegroundSettingsLabel;

  /// Title of the elevated foreground-service notification shown while a Toxee call is in progress.
  ///
  /// In en, this message translates to:
  /// **'Call in progress'**
  String get runtimeForegroundCallTitle;

  /// Body of the elevated foreground-service notification shown while a Toxee call is in progress.
  ///
  /// In en, this message translates to:
  /// **'Toxee is keeping your call connected.'**
  String get runtimeForegroundCallBody;

  /// Title variant of the in-call foreground notification including the remote caller's name.
  ///
  /// In en, this message translates to:
  /// **'Call with {name}'**
  String runtimeForegroundCallBodyWithCaller(String name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
