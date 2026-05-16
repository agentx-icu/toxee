// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get chats => 'チャット';

  @override
  String get contacts => '連絡先';

  @override
  String get requests => 'リクエスト';

  @override
  String get groups => 'グループ';

  @override
  String get settings => '設定';

  @override
  String get searchConversations => 'ニックネーム / グループ / メッセージで検索';

  @override
  String get searchContacts => '連絡先を検索';

  @override
  String get searchResults => '検索結果';

  @override
  String get enterKeywordToSearch => 'キーワードを入力して検索';

  @override
  String get noResultsFound => '結果が見つかりません';

  @override
  String get searchSectionMessages => 'メッセージ';

  @override
  String get searchSectionConversations => '会話';

  @override
  String get searchHint => '検索...';

  @override
  String messageCount(int count) {
    return '$count 件のメッセージ';
  }

  @override
  String get searchChatHistory => 'チャット履歴を検索';

  @override
  String searchResultsCount(int count, String keyword) {
    return '「$keyword」の検索結果が $count 件あります';
  }

  @override
  String get openChat => 'チャットを開く';

  @override
  String relatedChats(int count) {
    return '$count 件の関連メッセージ';
  }

  @override
  String get newItem => '新規';

  @override
  String get addFriend => '友達を追加';

  @override
  String get createGroup => 'グループを作成';

  @override
  String get friendUserId => '友達のユーザーID（16進数）';

  @override
  String get groupNameOptional => 'グループ名（オプション）';

  @override
  String get typeMessage => 'メッセージを入力';

  @override
  String get messageToGroup => 'グループにメッセージ';

  @override
  String get selfId => '自分のID';

  @override
  String get appearance => '外観';

  @override
  String get light => 'ライト';

  @override
  String get dark => 'ダーク';

  @override
  String get language => '言語';

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
  String get profile => 'プロフィール';

  @override
  String get nickname => 'ニックネーム';

  @override
  String get statusMessage => 'ステータスメッセージ';

  @override
  String get saveProfile => 'プロフィールを保存';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'キャンセル';

  @override
  String get group => 'グループ';

  @override
  String get file => 'ファイル';

  @override
  String get audio => 'オーディオ';

  @override
  String get friendRequestSent => '友達リクエストを送信しました';

  @override
  String get joinGroup => 'グループに参加';

  @override
  String get groupId => 'グループID';

  @override
  String get createAndOpen => '作成して開く';

  @override
  String get joinAndOpen => '参加して開く';

  @override
  String get knownGroups => '既知のグループ';

  @override
  String get selectAChat => 'チャットを選択';

  @override
  String get photo => '写真';

  @override
  String get video => '動画';

  @override
  String get autoAcceptFriendRequests => '友達リクエストを自動承認';

  @override
  String get autoAcceptFriendRequestsDesc => '受信した友達リクエストを自動的に承認';

  @override
  String get autoAcceptGroupInvites => 'グループ招待を自動承認';

  @override
  String get autoAcceptGroupInvitesDesc => '受信したグループ招待を自動的に承認';

  @override
  String get bootstrapNodes => 'Bootstrapノード';

  @override
  String get currentNode => '現在使用中のノード';

  @override
  String get viewAndTestNodes => 'ノードを表示してテスト';

  @override
  String get currentlyOnlineNoReconnect => '現在オンラインです。再接続の必要はありません';

  @override
  String get addOrCreateGroup => '追加 / グループを作成';

  @override
  String get joinGroupById => 'IDでグループに参加';

  @override
  String get enterGroupId => 'グループIDを入力してください';

  @override
  String get requestMessage => 'リクエストメッセージ';

  @override
  String get groupAlias => 'ローカルグループ名（オプション）';

  @override
  String get joinAction => '参加リクエストを送信';

  @override
  String get joinSuccess => '参加リクエストを送信しました';

  @override
  String get joinFailed => 'グループへの参加に失敗しました';

  @override
  String get groupName => 'グループ名';

  @override
  String get enterGroupName => 'グループ名を入力してください';

  @override
  String get createAction => 'グループを作成';

  @override
  String get createSuccess => 'グループを作成しました';

  @override
  String get createFailed => 'グループの作成に失敗しました';

  @override
  String get createdGroupId => '新しいグループID';

  @override
  String get copyId => 'IDをコピー';

  @override
  String get copied => 'クリップボードにコピーしました';

  @override
  String get addFailed => '追加に失敗しました';

  @override
  String get enterId => 'Tox IDを入力してください';

  @override
  String get invalidLength => 'IDは64または76文字の16進数である必要があります';

  @override
  String get invalidCharacters => '16進数の文字のみを含めることができます';

  @override
  String get paste => '貼り付け';

  @override
  String get addContactHint => '友達のTox ID（64または76文字の16進数）を入力してください。';

  @override
  String get verificationMessage => '確認メッセージ';

  @override
  String get defaultFriendRequestMessage => 'こんにちは、友達として追加したいです。';

  @override
  String get friendRequestMessageTooLong => '友達リクエストメッセージは921文字を超えることはできません';

  @override
  String get enterMessage => 'メッセージを入力してください';

  @override
  String get autoAcceptedNewFriendRequest => '新しい友達リクエストを自動承認しました';

  @override
  String get scanQrCodeToAddContact => 'QRコードをスキャンして連絡先に追加';

  @override
  String get generateCard => '名刺を生成';

  @override
  String get customCardText => 'カスタム名刺テキスト';

  @override
  String get userId => 'ユーザーID';

  @override
  String get saveImage => '画像を保存';

  @override
  String get copy => 'コピー';

  @override
  String get fileCopiedSuccessfully => 'ファイルをコピーしました';

  @override
  String get idCopiedToClipboard => 'IDをクリップボードにコピーしました';

  @override
  String get establishingEncryptedChannel => '暗号化チャネルを確立中...';

  @override
  String get checkingUserInfo => 'ユーザー情報を確認中...';

  @override
  String get initializingService => 'サービスを初期化中...';

  @override
  String get loggingIn => 'ログイン中...';

  @override
  String get initializingSDK => 'SDKを初期化中...';

  @override
  String get updatingProfile => 'プロフィールを更新中...';

  @override
  String get initializationCompleted => '初期化が完了しました！';

  @override
  String get loadingFriends => '友達情報を読み込み中...';

  @override
  String get inProgress => '進行中';

  @override
  String get completed => '完了';

  @override
  String get personalCard => '個人カード';

  @override
  String get appTitle => 'toxee';

  @override
  String get startChat => 'チャットを開始';

  @override
  String get pasteServerUserId => 'サーバーのユーザーIDをここに貼り付け';

  @override
  String get groupProfile => 'グループプロフィール';

  @override
  String get invalidGroupId => '無効なグループID';

  @override
  String maintainer(String maintainer) {
    return 'メンテナー: $maintainer';
  }

  @override
  String get success => '成功';

  @override
  String get failed => '失敗';

  @override
  String error(String error) {
    return 'エラー: $error';
  }

  @override
  String get saved => '保存しました';

  @override
  String failedToSave(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String copyFailed(String error) {
    return 'コピーに失敗しました: $error';
  }

  @override
  String failedToUpdateAvatar(String error) {
    return 'アバターの更新に失敗しました: $error';
  }

  @override
  String get failedToLoadQr => 'QRコードの読み込みに失敗しました';

  @override
  String get helloFromToxee => 'toxee からの挨拶';

  @override
  String attachFailed(String error) {
    return '添付に失敗しました: $error';
  }

  @override
  String get autoFriendRequestFromToxee => 'toxee からの自動友達リクエスト';

  @override
  String get reconnect => '再接続';

  @override
  String get reconnectConfirmMessage => '選択したBootstrapノードを使用して再接続します。続行しますか？';

  @override
  String get reconnectedWaiting => '再ログインしました。接続を待機中...';

  @override
  String get reconnectWithThisNode => 'このノードで再接続';

  @override
  String get friendOfflineCannotSendFile => '友達がオフラインです。ファイルを送信できません。オンラインになるまでお待ちください。';

  @override
  String get friendOfflineSendCardFailed => '友達がオフラインです。名刺の送信に失敗しました';

  @override
  String get friendOfflineSendImageFailed => '友達がオフラインです。画像の送信に失敗しました';

  @override
  String get friendOfflineSendVideoFailed => '友達がオフラインです。動画の送信に失敗しました';

  @override
  String get friendOfflineSendFileFailed => '友達がオフラインです。ファイルの送信に失敗しました';

  @override
  String get userNotInFriendList => 'このユーザーは友達リストにありません。';

  @override
  String sendFailed(String error) {
    return '送信に失敗しました: $error';
  }

  @override
  String get myId => '自分のID';

  @override
  String get sendPersonalCardToGroup => '個人カードをグループに送信';

  @override
  String get personalCardSent => '個人カードを送信しました';

  @override
  String get sentPersonalCardToGroup => 'グループに個人カードを送信しました';

  @override
  String get bootstrapNodesTitle => 'Bootstrapノード';

  @override
  String get refresh => '更新';

  @override
  String get retry => '再試行';

  @override
  String lastPing(String seconds) {
    return '最後のping: $seconds秒前';
  }

  @override
  String get testNode => 'ノードをテスト';

  @override
  String get deleteAccount => 'アカウント削除';

  @override
  String get deleteAccountConfirmMessage => 'アカウントとすべてのデータは永久に削除され、復元できません。慎重に操作してください。';

  @override
  String get delete => '削除';

  @override
  String get deleteAccountEnterPasswordToConfirm => '削除を確認するには、現在のアカウントのパスワードを入力してください。';

  @override
  String get deleteAccountTypeWordToConfirm => '削除を確認するには、下に表示されている英単語を正しく入力してください。';

  @override
  String deleteAccountConfirmWordPrompt(String word) {
    return '確認のため、以下の単語を下の欄に入力してください: $word';
  }

  @override
  String get deleteAccountWrongWord => '入力した単語が正しくありません。';

  @override
  String get applications => 'アプリ';

  @override
  String get applicationsComingSoon => 'さらに多くのアプリが近日公開予定...';

  @override
  String get notificationSound => '通知音';

  @override
  String get notificationSoundDesc => '新しいメッセージ、友達申請、グループ申請時に音を再生';

  @override
  String get downloadsDirectory => 'ダウンロードディレクトリ';

  @override
  String get selectDownloadsDirectory => 'ダウンロードディレクトリを選択';

  @override
  String get changeDownloadsDirectory => 'ダウンロードディレクトリを変更';

  @override
  String get downloadsDirectoryDesc => 'ファイルダウンロードのデフォルトディレクトリを設定します。受信したファイル、オーディオ、ビデオはこのディレクトリに保存されます。';

  @override
  String get downloadsDirectorySet => 'ダウンロードディレクトリが設定されました';

  @override
  String get downloadsDirectoryReset => 'ダウンロードディレクトリがデフォルトにリセットされました';

  @override
  String get failedToSelectDirectory => 'ディレクトリの選択に失敗しました';

  @override
  String get reset => 'リセット';

  @override
  String get autoDownloadSizeLimit => '自動ダウンロードサイズ制限';

  @override
  String get sizeLimitInMB => 'サイズ制限 (MB)';

  @override
  String get autoDownloadSizeLimitDesc => 'このサイズより小さいファイルとすべての画像は自動的にダウンロードされます。このサイズより大きいファイルは手動でダウンロードボタンをクリックする必要があります。';

  @override
  String get autoDownloadSizeLimitSet => '自動ダウンロードサイズ制限が設定されました';

  @override
  String get invalidSizeLimit => '無効なサイズ制限です。1〜10000の数字を入力してください';

  @override
  String get save => '保存';

  @override
  String get routeSelection => 'ルート選択';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get canOnlySelectOnlineNode => 'オンラインノードのみ選択できます';

  @override
  String get canOnlySelectTestedNode => 'テストに成功したノードのみ選択できます。まずノードをテストしてください';

  @override
  String get switchNode => 'ノードを切り替え';

  @override
  String switchNodeConfirm(String node) {
    return 'ノード $node に切り替えますか？切り替え後、再接続が必要です。';
  }

  @override
  String get nodeSwitched => 'ノードが切り替えられました。再接続中...';

  @override
  String get selectThisNode => 'このノードを選択';

  @override
  String nodeSwitchFailed(String error) {
    return 'ノードの切り替えに失敗しました: $error';
  }

  @override
  String get ircChannelApp => 'IRCチャンネル';

  @override
  String get ircChannelAppDesc => 'IRCチャンネルをToxグループに接続してメッセージを同期';

  @override
  String get install => 'インストール';

  @override
  String get uninstall => 'アンインストール';

  @override
  String get ircAppInstalled => 'IRCチャンネルアプリがインストールされました';

  @override
  String get ircAppUninstalled => 'IRCチャンネルアプリがアンインストールされました';

  @override
  String get uninstallIrcApp => 'IRCチャンネルアプリをアンインストール';

  @override
  String get uninstallIrcAppConfirm => 'IRCチャンネルアプリをアンインストールしてもよろしいですか？すべてのIRCチャンネルが削除され、すべてのIRCグループから退出します。';

  @override
  String get addIrcChannel => 'チャンネルを追加';

  @override
  String get ircChannels => 'IRCチャンネル';

  @override
  String get ircServerConfig => 'IRCサーバー設定';

  @override
  String get ircServer => 'サーバー';

  @override
  String get ircPort => 'ポート';

  @override
  String get ircUseSasl => 'SASL認証を使用';

  @override
  String get ircUseSaslDesc => 'SASL認証にTox公開鍵を使用（NickServ登録が必要）';

  @override
  String get ircServerRequired => 'IRCサーバーアドレスは必須です';

  @override
  String get ircConfigSaved => 'IRC設定が保存されました';

  @override
  String ircChannelAdded(String channel) {
    return 'IRCチャンネルが追加されました: $channel';
  }

  @override
  String get ircChannelAddFailed => 'IRCチャンネルの追加に失敗しました';

  @override
  String ircChannelRemoved(String channel) {
    return 'IRCチャンネルが削除されました: $channel';
  }

  @override
  String get removeIrcChannel => 'IRCチャンネルを削除';

  @override
  String removeIrcChannelConfirm(String channel) {
    return '$channelを削除してもよろしいですか？対応するグループから退出します。';
  }

  @override
  String get remove => '削除';

  @override
  String get joinIrcChannel => 'IRCチャンネルに参加';

  @override
  String get ircChannelName => 'IRCチャンネル名';

  @override
  String get ircChannelHint => '#チャンネル';

  @override
  String get ircChannelDesc => 'IRCチャンネル名を入力してください（例：#channel）。このチャンネル用にToxグループが作成されます。';

  @override
  String get enterIrcChannel => 'IRCチャンネル名を入力してください';

  @override
  String get invalidIrcChannel => 'IRCチャンネルは#または&で始める必要があります';

  @override
  String get join => '参加';

  @override
  String get ircAppNotInstalled => 'まずアプリケーションページからIRCチャンネルアプリをインストールしてください';

  @override
  String get ircChannelPassword => 'チャンネルパスワード';

  @override
  String get ircChannelPasswordHint => 'パスワードがない場合は空欄のまま';

  @override
  String get ircCustomNickname => 'カスタムIRCニックネーム';

  @override
  String get ircCustomNicknameHint => '空欄のままにすると自動生成されたニックネームを使用';

  @override
  String deleteAccountFailed(String error) {
    return 'アカウントの削除に失敗しました: $error';
  }

  @override
  String get directorySelectionNotSupported => 'このプラットフォームではディレクトリ選択がサポートされていません';

  @override
  String failedToSendFriendRequest(String error) {
    return '友達リクエストの送信に失敗しました: $error';
  }

  @override
  String get fileDoesNotExist => 'ファイルが存在しません';

  @override
  String get fileIsEmpty => 'ファイルが空です';

  @override
  String failedToSendFile(String label, String error) {
    return '$labelの送信に失敗しました: $error';
  }

  @override
  String get noReceivers => '受信者はいません';

  @override
  String messageReceivers(String count) {
    return 'メッセージ受信者 ($count)';
  }

  @override
  String get close => '閉じる';

  @override
  String get nodeNotTestedWarning => '注意: このノードはテストされていません。接続できない可能性があります。';

  @override
  String get nodeTestFailedWarning => '注意: このノードのテストに失敗しました。接続できない可能性があります。';

  @override
  String get nicknameTooLong => 'ニックネームが長すぎます';

  @override
  String get nicknameCannotBeEmpty => 'ニックネームを入力してください';

  @override
  String get statusMessageTooLong => 'ステータスメッセージが長すぎます';

  @override
  String get manualNodeInput => '手動ノード入力';

  @override
  String get nodeHost => 'ホスト';

  @override
  String get nodePort => 'ポート';

  @override
  String get nodePublicKey => '公開鍵';

  @override
  String get setAsCurrentNode => '現在のノードとして設定';

  @override
  String get nodeTestSuccess => 'ノードテスト成功';

  @override
  String get nodeTestFailed => 'ノードテスト失敗';

  @override
  String get invalidNodeInfo => '有効なノード情報（ホスト、ポート、公開鍵）を入力してください';

  @override
  String get nodeSetSuccess => 'ノードが現在のノードとして正常に設定されました';

  @override
  String get bootstrapNodeMode => 'Bootstrapノードモード';

  @override
  String get manualMode => '手動指定';

  @override
  String get autoMode => '自動（ウェブから取得）';

  @override
  String get manualModeDesc => 'Bootstrapノード情報を手動で指定';

  @override
  String get autoModeDesc => 'ウェブから自動的にBootstrapノードを取得して使用';

  @override
  String get autoModeDescPrefix => '自動的に からBootstrapノードを取得して使用';

  @override
  String get lanMode => 'LANモード';

  @override
  String get lanModeDesc => 'ローカルネットワークBootstrapサービスを使用';

  @override
  String get startLocalBootstrapService => 'ローカルBootstrapサービスを開始';

  @override
  String get stopLocalBootstrapService => 'ローカルBootstrapサービスを停止';

  @override
  String get bootstrapServiceStatus => 'サービスステータス';

  @override
  String get serviceRunning => '実行中';

  @override
  String get serviceStopped => '停止';

  @override
  String get scanLanBootstrapServices => 'LAN Bootstrapサービスをスキャン';

  @override
  String get scanLanBootstrapServicesTitle => 'LAN Bootstrapサービス';

  @override
  String get scanPort => 'スキャンポート';

  @override
  String get startScan => 'スキャンを開始';

  @override
  String scanningAliveIPs(int current, int total) {
    return 'アクティブIPをスキャン中: $current/$total';
  }

  @override
  String probingBootstrapServices(int current, int total) {
    return 'Bootstrapサービスをプローブ中: $current/$total';
  }

  @override
  String get scanning => 'スキャン中...';

  @override
  String get probing => 'プローブ中...';

  @override
  String aliveIPsFound(int count) {
    return 'アクティブIPが見つかりました: $count';
  }

  @override
  String get noAliveIPsFound => 'アクティブIPが見つかりませんでした';

  @override
  String get bootstrapServiceFound => 'Bootstrapサービスが見つかりました';

  @override
  String get noBootstrapService => 'Bootstrapサービスが見つかりませんでした';

  @override
  String get noServicesFound => 'サービスが見つかりませんでした';

  @override
  String get useAsBootstrapNode => 'Bootstrapノードとして使用';

  @override
  String get ipAddress => 'IPアドレス';

  @override
  String get probeStatus => 'プローブステータス';

  @override
  String get probeSingleIP => 'このIPをプローブ';

  @override
  String probingIP(String ip) {
    return '$ipをプローブ中...';
  }

  @override
  String get refreshAliveIPs => 'アクティブIPを更新';

  @override
  String get aliveIPsList => 'アクティブIPリスト';

  @override
  String get notProbedYet => 'まだプローブされていません';

  @override
  String get probeSuccess => 'Bootstrapサービスが見つかりました';

  @override
  String get probeFailed => 'Bootstrapサービスが見つかりませんでした';

  @override
  String bootstrapServiceRunning(String ip, int port) {
    return 'Bootstrapサービス実行中: $ip:$port';
  }

  @override
  String get logOut => 'ログアウト';

  @override
  String get logOutConfirm => 'ログアウトしてもよろしいですか？';

  @override
  String get autoLogin => '自動ログイン';

  @override
  String get autoLoginEnabled => '自動ログイン：有効';

  @override
  String get autoLoginDisabled => '自動ログイン：無効';

  @override
  String get autoLoginDesc => '有効にすると、アプリ起動時に自動的にログインします。';

  @override
  String get disable => '無効にする';

  @override
  String get enable => '有効にする';

  @override
  String get login => 'ログイン';

  @override
  String get register => '登録';

  @override
  String get registerNewAccount => '新規アカウント登録';

  @override
  String get unnamedAccount => '名前のないアカウント';

  @override
  String get accountInfo => 'アカウント情報';

  @override
  String get accountManagement => 'アカウント管理';

  @override
  String get localAccounts => 'ローカルアカウント';

  @override
  String showMore(int count) {
    return 'さらに $count 件表示';
  }

  @override
  String get showLess => '折りたたむ';

  @override
  String get current => '現在';

  @override
  String get lastLogin => '最終ログイン';

  @override
  String get switchAccount => 'アカウント切替';

  @override
  String get exportAccount => 'アカウントエクスポート';

  @override
  String get exportOptionProfileTox => 'Profile (.tox)';

  @override
  String get exportOptionProfileToxSubtitle => 'qTox compatible, profile only';

  @override
  String get exportOptionFullBackup => 'Full Backup (.zip)';

  @override
  String get exportOptionFullBackupSubtitle => 'Profile + chat history + settings';

  @override
  String get importAccount => 'アカウントインポート';

  @override
  String get setPassword => 'パスワード設定';

  @override
  String get changePassword => 'パスワード変更';

  @override
  String get enterPasswordToExport => 'アカウントをエクスポートするためのパスワードを入力';

  @override
  String get enterPasswordToImport => 'アカウントをインポートするためのパスワードを入力';

  @override
  String enterPasswordForAccount(String nickname) {
    return 'アカウント \"$nickname\" のパスワードを入力';
  }

  @override
  String get invalidPassword => 'パスワードが正しくありません';

  @override
  String accountExportedSuccessfully(String filePath) {
    return 'アカウントが正常にエクスポートされました: $filePath';
  }

  @override
  String get accountImportedSuccessfully => 'アカウントが正常にインポートされました';

  @override
  String get passwordSetSuccessfully => 'パスワードが正常に設定されました';

  @override
  String get passwordRemoved => 'パスワードが削除されました';

  @override
  String failedToSwitchAccount(String error) {
    return 'アカウントの切替に失敗しました: $error';
  }

  @override
  String failedToExportAccount(String error) {
    return 'アカウントのエクスポートに失敗しました: $error';
  }

  @override
  String failedToImportAccount(String error) {
    return 'アカウントのインポートに失敗しました: $error';
  }

  @override
  String failedToSetPassword(String error) {
    return 'パスワードの設定に失敗しました: $error';
  }

  @override
  String get noAccountToExport => 'エクスポートするアカウントがありません';

  @override
  String get noAccountSelected => 'アカウントが選択されていません';

  @override
  String get accountAlreadyExists => 'アカウントが既に存在します';

  @override
  String get accountAlreadyExistsMessage => 'このIDのアカウントが既に存在します。更新しますか？';

  @override
  String get update => '更新';

  @override
  String switchAccountConfirm(String nickname) {
    return '\"$nickname\" に切り替えますか？現在のアカウントからログアウトされます。';
  }

  @override
  String get savedAccounts => '保存されたアカウント';

  @override
  String get tapToSelectDoubleTapToLogin => 'タップで選択、ダブルタップでクイックログイン';

  @override
  String get tapToLogIn => 'タップしてログイン';

  @override
  String get switchToThisAccount => 'このアカウントに切り替え';

  @override
  String get password => 'パスワード';

  @override
  String get newPassword => '新しいパスワード';

  @override
  String get confirmPassword => 'パスワード確認';

  @override
  String get leaveEmptyToRemovePassword => '空欄にするとパスワードを削除';

  @override
  String get passwordsDoNotMatch => 'パスワードが一致しません';

  @override
  String get never => '未ログイン';

  @override
  String get justNow => 'たった今';

  @override
  String daysAgo(int count, String plural) {
    return '$count 日前';
  }

  @override
  String hoursAgo(int count, String plural) {
    return '$count 時間前';
  }

  @override
  String minutesAgo(int count, String plural) {
    return '$count 分前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => 'このアカウントは既にログインしています';

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
  String get defaultJoinRequestMessage => 'Hi, please invite me into this group';

  @override
  String get userNotFoundPleaseRegister => 'User not found. Please register first.';

  @override
  String get nicknameDoesNotMatch => 'Nickname does not match. Please use the registered nickname or register a new account.';

  @override
  String get accountAlreadyExistsPleaseLogin => 'Account already exists. Please login instead or use a different nickname.';

  @override
  String get profileNotFoundImportRestore => 'Profile not found for this account. Please import or restore backup.';

  @override
  String get failedToInitializeTIMManager => 'Failed to initialize TIMManager SDK';

  @override
  String get failedToGetToxId => 'Failed to get Tox ID';

  @override
  String get failedToGenerateToxId => 'Failed to generate Tox ID';

  @override
  String get registrationCouldNotCreateProfile => 'Registration could not create a unique profile. Please try again.';

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
    return '$contacts件の連絡先、$groups件のグループ、$messages件のメッセージスレッドが見つかりました';
  }

  @override
  String get searchFailed => '検索に失敗しました。部分的な結果を表示しています';

  @override
  String get callVideoCall => 'ビデオ通話';

  @override
  String get callAudioCall => '音声通話';

  @override
  String get callReject => '拒否';

  @override
  String get callAccept => '応答';

  @override
  String get callRemoteVideo => '相手の映像';

  @override
  String get callUnmute => 'ミュート解除';

  @override
  String get callMute => 'ミュート';

  @override
  String get callVideoOff => 'ビデオオフ';

  @override
  String get callVideoOn => 'ビデオオン';

  @override
  String get callSpeakerOff => 'スピーカーオフ';

  @override
  String get callSpeakerOn => 'スピーカーオン';

  @override
  String get callHangUp => '電話を切る';

  @override
  String get callEnded => '通話が終了しました';

  @override
  String get callPermissionMicrophoneRequired => '通話を続けるにはマイクへのアクセス許可が必要です。';

  @override
  String get callPermissionCameraRequired => '通話を続けるにはカメラへのアクセス許可が必要です。';

  @override
  String get callPermissionMicrophoneCameraRequired => '通話を続けるにはマイクとカメラへのアクセス許可が必要です。';

  @override
  String get callAudioInterrupted => '通話中に音声出力が変更されたか、中断されました。';

  @override
  String get callCalling => '発信中...';

  @override
  String get callMinimize => '最小化';

  @override
  String get callReturnToCall => '通話に戻る';

  @override
  String get callQualityGood => '接続良好';

  @override
  String get callQualityMedium => '接続普通';

  @override
  String get callQualityPoor => '接続不良';

  @override
  String get callQualityUnknown => '—';

  @override
  String get callQualityLabel => '通話品質';

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
  String get callAudioRouteSystem => 'Audio route managed by system on this platform';

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
  String get selectConversationEmptyState => 'Select a conversation to start chatting';

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
  String get firstRunBackupWizardBody => 'Your account lives only on this device. Save the .tox file somewhere safe (cloud storage, password manager, USB stick). Without it, losing this device means losing your account and all your contacts permanently.';

  @override
  String get firstRunBackupWizardExportNow => 'Export now';

  @override
  String get firstRunBackupWizardLater => 'I\'ll do it later';

  @override
  String get firstRunBackupWizardDismissTitle => 'Skip backup?';

  @override
  String get firstRunBackupWizardDismissBody => 'If you lose this device, you will lose your account and all contacts. There is no recovery.';

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
  String get restoreFromToxFileInvalidFile => 'This file doesn\'t look like a valid Tox profile.';
}
