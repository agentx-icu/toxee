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
  String get general => '一般';

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
  String get joinQueued => 'オフライン — 再接続時に参加リクエストを送信します';

  @override
  String get offlineBanner => 'オフライン — グループ操作はキューに追加され、再接続時に処理されます。';

  @override
  String get groupType => 'グループの種類';

  @override
  String get publicGroup => '公開';

  @override
  String get privateGroup => 'プライベート';

  @override
  String get publicGroupHint =>
      '公開グループ — DHT で検出可能で、チャット ID を知っている人なら誰でも参加できます。';

  @override
  String get privateGroupHint => 'プライベートグループ — 招待制で、DHT には公開されません。';

  @override
  String get conferenceHint => 'レガシーカンファレンス — 古いプロトコル、ロールや永続化はありません。';

  @override
  String get searchHintBody => '連絡先、グループ、メッセージを検索';

  @override
  String get noResultsFoundHint => 'より短いキーワードを試すか、スペルを確認してください';

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
  String get invalidLength => 'IDの長さが正しくありません';

  @override
  String get invalidCharacters => '16進数の文字のみを含めることができます';

  @override
  String get paste => '貼り付け';

  @override
  String get addContactHint => '相手のToxアドレスを入力してください。';

  @override
  String get addFriendInvalidToxIdHint => 'Toxアドレスは76文字の16進数である必要があります';

  @override
  String get verificationMessage => '確認メッセージ';

  @override
  String get defaultFriendRequestMessage => 'こんにちは、友達として追加したいです。';

  @override
  String get friendRequestMessageTooLong => '友達リクエストメッセージは921文字を超えることはできません';

  @override
  String get enterMessage => 'メッセージを入力してください';

  @override
  String get noGroupMembers => 'メンバーはまだいません';

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
  String get friendOfflineCannotSendFile =>
      '友達がオフラインです。ファイルを送信できません。オンラインになるまでお待ちください。';

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
  String get deleteAccountConfirmMessage =>
      'アカウントとすべてのデータは永久に削除され、復元できません。慎重に操作してください。';

  @override
  String get delete => '削除';

  @override
  String get deleteAccountEnterPasswordToConfirm =>
      '削除を確認するには、現在のアカウントのパスワードを入力してください。';

  @override
  String get deleteAccountTypeWordToConfirm =>
      '削除を確認するには、下に表示されている英単語を正しく入力してください。';

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
  String get downloadsDirectoryDesc =>
      'ファイルダウンロードのデフォルトディレクトリを設定します。受信したファイル、オーディオ、ビデオはこのディレクトリに保存されます。';

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
  String get autoDownloadSizeLimitDesc =>
      'このサイズより小さいファイルとすべての画像は自動的にダウンロードされます。このサイズより大きいファイルは手動でダウンロードボタンをクリックする必要があります。';

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
  String get canOnlySelectTestedNode => 'このノードを選択する前に、ブートストラップ要求を送信してください';

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
  String get uninstallIrcAppConfirm =>
      'IRCチャンネルアプリをアンインストールしてもよろしいですか？すべてのIRCチャンネルが削除され、すべてのIRCグループから退出します。';

  @override
  String get addIrcChannel => 'チャンネルを追加';

  @override
  String get ircChannels => 'IRCチャンネル';

  @override
  String get ircStatusDisconnected => '切断';

  @override
  String get ircStatusConnecting => '接続中';

  @override
  String get ircStatusConnected => '接続済み';

  @override
  String get ircStatusAuthenticating => '認証中';

  @override
  String get ircStatusReconnecting => '再接続中';

  @override
  String get ircStatusError => 'エラー';

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
  String ircChannelAddedNotConnected(String channel) {
    return 'チャンネル $channel を追加しましたが、IRC 接続を確立できませんでした';
  }

  @override
  String get ircAppInstalledNoLibrary =>
      'IRC アプリはインストールされましたが、このデバイスではライブ IRC を利用できません';

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
  String get ircChannelDesc =>
      'IRCチャンネル名を入力してください（例：#channel）。このチャンネル用にToxグループが作成されます。';

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
  String get directorySelectionNotSupported =>
      'このプラットフォームではディレクトリ選択がサポートされていません';

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
  String get nodeNotTestedWarning => 'このノードはまだテストされていません。';

  @override
  String get nodeTestFailedWarning => 'このノードは応答しませんでした。利用できない可能性があります。';

  @override
  String get nodeTestInconclusiveWarning =>
      'この端末からはこのノードを検査できないため、利用できるかどうかは不明です。';

  @override
  String get nicknameTooLong => 'ニックネームが長すぎます';

  @override
  String get nicknameCannotBeEmpty => 'ニックネームを入力してください';

  @override
  String get statusMessageTooLong => 'ステータスメッセージが長すぎます';

  @override
  String get passwordStrengthWeak => '弱い';

  @override
  String get passwordStrengthFair => '普通';

  @override
  String get passwordStrengthGood => '良好';

  @override
  String get passwordStrengthStrong => '強い';

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
  String get nodeTestSuccess => 'ノードに到達できました';

  @override
  String get nodeTestUdpUnavailable =>
      'ノードのテストには UDP が必要です。この端末は TCP のみで動作しています';

  @override
  String get nodeTestFailed => 'ノードに到達できません';

  @override
  String get nodeTestUnavailable => 'この端末ではノードテストを実行できません';

  @override
  String get failedToLoadBootstrapNodes => 'ブートストラップノードの読み込みに失敗しました';

  @override
  String get failedToStartBootstrapService => 'ブートストラップサービスの起動に失敗しました';

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
  String get exportOptionProfileTox => 'プロフィール (.tox)';

  @override
  String get exportOptionProfileToxSubtitle => 'qTox 互換、プロフィールのみ';

  @override
  String get exportOptionFullBackup => 'フルバックアップ (.zip)';

  @override
  String get exportOptionFullBackupSubtitle => 'プロフィール + チャット履歴 + 設定';

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
  String daysAgo(int count) {
    return '$count 日前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 時間前';
  }

  @override
  String minutesAgo(int count) {
    return '$count 分前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => 'このアカウントは既にログインしています';

  @override
  String get upgradeRequiredTitle => 'アプリをアップグレードしてください';

  @override
  String upgradeRequiredMessage(int storedVersion, int currentVersion) {
    return 'データは新しいバージョンのアプリで保存されています（データバージョン: $storedVersion）。このバージョンは $currentVersion まで対応しています。続行するには最新のアップデートをインストールしてください。';
  }

  @override
  String get upgradeAppTitle => 'toxee';

  @override
  String get hide => '非表示';

  @override
  String get pressBackAgainToExit => 'もう一度戻るを押すと終了します';

  @override
  String get startupFailed => '起動に失敗しました';

  @override
  String get unknownError => '不明なエラー';

  @override
  String get goToLogin => 'ログインへ';

  @override
  String get conference => 'カンファレンス';

  @override
  String get defaultJoinRequestMessage => 'こんにちは、このグループに招待してください';

  @override
  String get userNotFoundPleaseRegister => 'ユーザーが見つかりません。先に登録してください。';

  @override
  String get nicknameDoesNotMatch =>
      'ニックネームが一致しません。登録済みのニックネームを使用するか、新しいアカウントを登録してください。';

  @override
  String get accountAlreadyExistsPleaseLogin =>
      'アカウントは既に存在します。ログインするか、別のニックネームを使用してください。';

  @override
  String get profileNotFoundImportRestore =>
      'このアカウントのプロフィールが見つかりません。インポートするか、バックアップから復元してください。';

  @override
  String get failedToInitializeTIMManager => 'TIMManager SDK の初期化に失敗しました';

  @override
  String get failedToGetToxId => 'Tox ID の取得に失敗しました';

  @override
  String get failedToGenerateToxId => 'Tox ID の生成に失敗しました';

  @override
  String get registrationCouldNotCreateProfile =>
      '一意のプロフィールを作成できませんでした。もう一度お試しください。';

  @override
  String get importedAccount => 'インポートしたアカウント';

  @override
  String get unknown => '不明';

  @override
  String sendingToGroupsNotSupported(String label) {
    return 'グループへの$labelの送信はまだサポートされていません';
  }

  @override
  String noLabelSelected(String label) {
    return '$labelが選択されていません';
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
  String get callSwitchCamera => 'カメラを切り替え';

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
  String get callPermissionMicrophoneCameraRequired =>
      '通話を続けるにはマイクとカメラへのアクセス許可が必要です。';

  @override
  String get callIncomingNotificationPermissionRequired =>
      '通知の許可を有効にするまで、着信は Toxee 内でのみ鳴ります。';

  @override
  String get callFailedGroupUnsupported => 'グループ通話はまだサポートされていません。';

  @override
  String get callFailedSignaling => '通話を開始できませんでした。もう一度お試しください。';

  @override
  String get callFailedMediaChannel => '通話のメディアチャネルを確立できませんでした。';

  @override
  String get callVideoUnsupportedPlatform =>
      'このプラットフォームではビデオ通話はまだ利用できません（カメラ非対応）。';

  @override
  String get callAudioInterrupted => '通話中に音声出力が変更されたか、中断されました。';

  @override
  String get callCalling => '発信中...';

  @override
  String get callLeaving => '会議から退出しています...';

  @override
  String callReceivedFrames(int count) {
    return '受信フレーム $count';
  }

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
    return '未読メッセージ $count 件';
  }

  @override
  String matchingMessagesSemantics(int count) {
    return '一致するメッセージ $count 件';
  }

  @override
  String get statusOnline => 'オンライン';

  @override
  String get statusOffline => 'オフライン';

  @override
  String get noIrcChannels => 'IRCチャンネルがありません';

  @override
  String get joinChannelToGetStarted => 'チャンネルに参加して始めましょう';

  @override
  String ircUsersCount(int count) {
    return 'ユーザー ($count)';
  }

  @override
  String get ircNoUsers => 'ユーザーがいません';

  @override
  String get passwordVisibility => 'パスワードの表示/非表示';

  @override
  String get nicknameHintExample => '例: Alice';

  @override
  String get callAudioRouteSystem => 'このプラットフォームでは音声出力先はシステムが管理します';

  @override
  String get copyFullToxId => 'ID 全体をコピー';

  @override
  String get themeSystem => 'システム';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get idLabel => 'ID:';

  @override
  String errorBannerLabel(String message) {
    return 'エラー: $message';
  }

  @override
  String searchResultContactSemantics(String name) {
    return '$name、連絡先';
  }

  @override
  String searchResultGroupSemantics(String name) {
    return '$name、グループ';
  }

  @override
  String searchResultMessageSemantics(String name) {
    return '$name、メッセージ';
  }

  @override
  String searchResultConversationSemantics(String name) {
    return '$name、会話';
  }

  @override
  String get importNoFileSelected => 'ファイルが選択されていません';

  @override
  String get importCancelled => 'キャンセルしました';

  @override
  String get recoveryBlockedTitle => 'アカウントの復旧が完了していません';

  @override
  String get recoveryBlockedBody =>
      'toxee は、読み取れない未完了のアカウント復元または削除を検出したため、どのアカウントも開いていません — 続行するとデータが失われるおそれがありました。\n\nアカウントとそのプロフィールは、まだこのデバイスに残っています。再登録やアプリデータの消去は絶対に行わないでください。どちらもデータの損失を確定させてしまいます。修復できるよう、以下の詳細を報告してください。';

  @override
  String get secureStorageUnavailable =>
      'セキュアストレージを利用できないため、toxee はこのアカウントのパスワードを確認できません。通常は一時的な問題です。もう一度試すか、デバイスのキーチェーンのロックを解除してください。';

  @override
  String get recoverLegacyDataAction => '旧バージョンのデータを復旧';

  @override
  String get recoverLegacyDataConfirm =>
      'このデバイスには、toxee が複数アカウントに対応する前のチャット履歴、送信待ちメッセージ、連絡先のアバターが残っています。現在ログインしているアカウントに追加しますか？\n\nこのデータがご自身のものである場合にのみ実行してください。引き継げるのは 1 つのアカウントで 1 回だけです。\n\n統合は次回のログイン時に行われるため、ログアウトされます。';

  @override
  String get recoverLegacyDataClaimed =>
      'このアカウントが旧データを引き継ぎます。統合するには、ログアウトしてから再度ログインしてください — ログイン時に統合することで、現在の履歴と送信待ちメッセージが保持されます。';

  @override
  String get recoverLegacyDataDone => '旧データをこのアカウントに追加しました。';

  @override
  String get recoverLegacyDataUnavailable =>
      'このデータを引き継げませんでした。このデバイス上の別のアカウントに既に属している可能性があります。';

  @override
  String get accountRegistryUnreadable =>
      '保存済みのアカウントを読み取れませんでした。プロフィールはまだこのデバイスに残っています — 再登録せず、アカウントリストを修復できるよう報告してください。';

  @override
  String get importedAccountDefaultName => 'インポートしたアカウント';

  @override
  String failedToImport(String error) {
    return 'インポートに失敗しました: $error';
  }

  @override
  String get selectConversationEmptyState => '会話を選択してチャットを始めましょう';

  @override
  String get newConversationTooltip => '新しい会話';

  @override
  String get pinConversation => 'ピン留め';

  @override
  String get unpinConversation => 'ピン留めを解除';

  @override
  String get markConversationAsRead => '既読にする';

  @override
  String get deleteConversationTitle => '会話を削除しますか？';

  @override
  String deleteConversationBody(String name) {
    return '「$name」がチャットリストから削除されます。メッセージ履歴はディスクに残ります。';
  }

  @override
  String get firstRunBackupWizardTitle => 'アカウントファイルを保存';

  @override
  String get firstRunBackupWizardBody =>
      'アカウントはこのデバイスにのみ保存されています。.tox ファイルを安全な場所（クラウドストレージ、パスワードマネージャー、USB メモリなど）に保存してください。保存しないままこのデバイスを失うと、アカウントとすべての連絡先が永久に失われます。';

  @override
  String get firstRunBackupWizardExportNow => '今すぐエクスポート';

  @override
  String get firstRunBackupWizardLater => '後で行う';

  @override
  String get firstRunBackupWizardDismissTitle => 'バックアップをスキップしますか？';

  @override
  String get firstRunBackupWizardDismissBody =>
      'このデバイスを失うと、アカウントとすべての連絡先が失われます。復旧する方法はありません。';

  @override
  String get firstRunBackupWizardDismissConfirm => '理解したうえで続行';

  @override
  String firstRunBackupWizardExportFailed(String error) {
    return 'アカウントファイルを保存できませんでした: $error';
  }

  @override
  String get restoreFromToxFile => '.tox ファイルから復元';

  @override
  String restoreFromToxFileSuccess(String nickname) {
    return 'アカウントを復元しました: $nickname';
  }

  @override
  String get restoreFromToxFileInvalidFile => 'このファイルは有効な Tox プロフィールではないようです。';

  @override
  String get pairDeviceHostTitle => '別のデバイスをペアリング';

  @override
  String get pairDeviceClientTitle => '別のデバイスとペアリング';

  @override
  String get pairingHostInstructions =>
      'もう一方のデバイスで toxee を開き、「別のデバイスとペアリング」を選択して、この QR コードをスキャンしてください。';

  @override
  String get pairingClientScanInstructions =>
      'もう一方のデバイスに表示されている QR コードにカメラを向けてください。';

  @override
  String get pairingClientPasteInstructions =>
      'このデバイスはカメラでのスキャンに対応していません。もう一方のデバイスに表示されているペアリング URL を下に貼り付けてください。';

  @override
  String get pairingPasteUrlLabel => 'ペアリング URL';

  @override
  String get pairingConnectButton => '接続';

  @override
  String get pairingWaitingForPeer => 'もう一方のデバイスの接続を待機中…';

  @override
  String get pairingVerifyCodeHeader => '両方のデバイスに同じコードが表示されていることを確認してください';

  @override
  String get pairingVerifyCodeInstructions =>
      'もう一方のデバイスに表示されているコードと一致する場合は、下をタップしてください。異なる場合はキャンセルしてください — 接続が傍受されている可能性があります。';

  @override
  String get pairingCodesMatch => 'コードが一致しています';

  @override
  String get pairingHostCompleted => 'アカウントを送信しました。もう一方のデバイスでこのアカウントを使用できます。';

  @override
  String get pairingClientCompleted => 'アカウントを受信しました。ペアリングが完了しました。';

  @override
  String get pairingCancelled => 'ペアリングをキャンセルしました。';

  @override
  String get pairingTimeout => 'ペアリングがタイムアウトしました — もう一度お試しください。';

  @override
  String pairingNetworkError(String detail) {
    return 'ペアリング中にネットワークエラーが発生しました: $detail';
  }

  @override
  String pairingProtocolError(String detail) {
    return 'ペアリングのハンドシェイクに失敗しました: $detail';
  }

  @override
  String pairingInvalidUrl(String detail) {
    return 'この QR コードは有効なペアリング招待ではありません: $detail';
  }

  @override
  String get pairingDecryptFailed =>
      '受信したプロフィールを復号できませんでした。ペアリングが改ざんされた可能性があります — 信頼できるネットワークでもう一度お試しください。';

  @override
  String get pairingNoLanInterface =>
      'LAN ネットワークが検出されません。Wi-Fi またはイーサネットに接続して、もう一度お試しください。';

  @override
  String get pairThisAccountToAnotherDevice => 'このアカウントを別のデバイスとペアリング';

  @override
  String get pairWithAnotherDevice => '自分のアカウントがある別のデバイスとペアリング';

  @override
  String get devicesSectionTitle => 'デバイス';

  @override
  String get done => '完了';

  @override
  String get runtimeForegroundTitle => 'Toxee は実行中です';

  @override
  String get runtimeForegroundBody => 'メッセージや通話を受信できるよう接続を維持しています。';

  @override
  String get runtimeForegroundSettingsLabel => '通知設定';

  @override
  String get runtimeForegroundCallTitle => '通話中';

  @override
  String get runtimeForegroundCallBody => 'Toxee が通話の接続を維持しています。';

  @override
  String runtimeForegroundCallBodyWithCaller(String name) {
    return '$name と通話中';
  }

  @override
  String get appTagline => 'プライベートなP2Pメッセンジャー';

  @override
  String get noBootstrapNodes => 'ブートストラップノードがありません';

  @override
  String get importMayHaveCompleted =>
      'インポートを取り消せなかったため、このアカウントはまだ残っている可能性があります。再度インポートする前にアカウントリストを確認してください。';

  @override
  String get importBlockedByPendingImport =>
      '中断された別のアカウントインポートがまだ処理されていません。toxee を再起動して取り消しを完了してから、再度インポートしてください。';

  @override
  String get friendRequestQueued => 'オフライン — リクエストはキューに追加され、再接続時に送信されます';

  @override
  String get cannotAddSelfAsFriend => '自分自身を友達に追加することはできません';

  @override
  String get friendRequestAlreadySent => 'このセッションで既に友達リクエストを送信しています';

  @override
  String get alreadyInFriendList => 'このユーザーは既に友達リストにいます';

  @override
  String get addFriendOfflineBanner =>
      'オフライン — 友達リクエストはキューに追加され、再接続時に自動的に送信されます。';

  @override
  String get scanQr => 'QR をスキャン';

  @override
  String get sendingInProgress => '送信中...';

  @override
  String get firewallHintWindows =>
      'Windows では、ファイアウォールが着信接続をブロックする場合があります。確認を求められたらアプリを許可してください。';

  @override
  String get firewallHintLinux =>
      'Linux では、ネットワーク操作に適切な権限またはファイアウォールルールが必要な場合があります。';

  @override
  String get nodePublicKeyHint => '公開鍵（16進数）';

  @override
  String get failedToAddBootstrapNode => 'ブートストラップノードの追加に失敗しました';

  @override
  String get couldNotRemovePassword => 'パスワードを削除できませんでした';

  @override
  String get couldNotSavePassword => 'パスワードを保存できませんでした';

  @override
  String mediaSent(String label) {
    return '$labelを送信しました';
  }

  @override
  String get dhtUnreachableUsingFallback =>
      'DHT に接続できません。フォールバックのブートストラップノードを使用しています — ネットワークが UDP をブロックしているか、ノードがダウンしている可能性があります。';

  @override
  String get dhtUnreachableTimeout =>
      '30 秒経っても DHT に接続できません。ネットワーク接続を確認してください。';

  @override
  String chatSdkInitFailed(String error) {
    return 'チャット SDK の初期化に失敗しました: $error';
  }

  @override
  String messageTooLongMaxBytes(int maxBytes) {
    return 'メッセージが長すぎます（最大 $maxBytes バイト）';
  }

  @override
  String get friendOfflineWillRetry => '友達がオフラインです — 再接続時に再送信します';

  @override
  String get groupFileTransferUnsupported => 'グループチャットでのファイル転送はサポートされていません';

  @override
  String fileSendFailed(String error) {
    return 'ファイルの送信に失敗しました: $error';
  }

  @override
  String errorWithCode(int code) {
    return 'エラー $code';
  }

  @override
  String pairingLanUnreachable(String detail) {
    return 'このネットワークではデバイス同士が互いを検出できません。個人用ホットスポットを試すか、代わりにエクスポート → ファイルからインポートを使用してください。($detail)';
  }

  @override
  String get notificationNewFriendRequest => '新しい友達リクエスト';

  @override
  String notificationFriendRequestFrom(String name) {
    return '友達リクエスト: $name';
  }

  @override
  String get notificationMissedCall => '不在着信';

  @override
  String get notificationMissedVideoCall => 'ビデオ通話の不在着信';

  @override
  String get notificationIncomingCall => '着信';

  @override
  String get notificationIncomingVideoCall => 'ビデオ通話の着信';

  @override
  String get notificationUnknownCaller => 'Toxee の連絡先';

  @override
  String get notificationNewMessage => '新しいメッセージ';

  @override
  String get previewImage => '[画像]';

  @override
  String get previewVideo => '[動画]';

  @override
  String get previewVoice => '[音声]';

  @override
  String previewVoiceWithDuration(int seconds) {
    return '[音声 $seconds秒]';
  }

  @override
  String get previewFile => '[ファイル]';

  @override
  String previewFileWithName(String name) {
    return '[ファイル] $name';
  }

  @override
  String get previewSticker => '[ステッカー]';

  @override
  String get previewLocation => '[位置情報]';

  @override
  String get previewCustomMessage => '[カスタムメッセージ]';

  @override
  String get previewGroupEvent => '[グループイベント]';

  @override
  String get previewMessage => '[メッセージ]';

  @override
  String get channelMessagesName => 'メッセージ';

  @override
  String get channelMessagesDescription => 'Tox の連絡先から新しいメッセージを受信したときの通知。';

  @override
  String get channelFriendRequestsName => '友達リクエスト';

  @override
  String get channelFriendRequestsDescription => '友達リクエストを受信したときの通知。';

  @override
  String get channelMissedCallsName => '不在着信';

  @override
  String get channelMissedCallsDescription => '着信に応答できなかった、または不在だったときの通知。';

  @override
  String get channelIncomingCallsName => '着信';

  @override
  String get channelIncomingCallsDescription => 'Toxee の着信を知らせる全画面アラート。';

  @override
  String get notificationOpenAction => 'Toxee を開く';

  @override
  String trayUnreadTooltip(int count) {
    return '未読: $count';
  }

  @override
  String get unknownErrorReason => '不明なエラー';

  @override
  String get notificationNoMessage => '（メッセージなし）';

  @override
  String notificationGroupedSummary(int count, String name) {
    return '$name から $count 件の新着メッセージ';
  }

  @override
  String pairingConnectTimedOut(String endpoint) {
    return '時間内にもう一方のデバイス（$endpoint）に接続できませんでした。両方のデバイスが同じネットワークにあることを確認するか、個人用ホットスポットを試すか、ファイルによるエクスポート → インポートを使用してください。';
  }
}
