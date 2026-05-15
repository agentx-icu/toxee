// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get chats => '聊天';

  @override
  String get contacts => '联系人';

  @override
  String get requests => '请求';

  @override
  String get groups => '群组';

  @override
  String get settings => '设置';

  @override
  String get searchConversations => '按昵称/群/消息搜索';

  @override
  String get searchContacts => '搜索联系人';

  @override
  String get searchResults => '搜索结果';

  @override
  String get enterKeywordToSearch => '请输入关键词搜索';

  @override
  String get noResultsFound => '未找到结果';

  @override
  String get searchSectionMessages => '消息';

  @override
  String get searchSectionConversations => '会话';

  @override
  String get searchHint => '搜索...';

  @override
  String messageCount(int count) {
    return '$count 条消息';
  }

  @override
  String get searchChatHistory => '搜索聊天记录';

  @override
  String searchResultsCount(int count, String keyword) {
    return '共有 $count 条与「$keyword」相关的结果';
  }

  @override
  String get openChat => '打开聊天';

  @override
  String relatedChats(int count) {
    return '$count 条相关消息';
  }

  @override
  String get newItem => '新建';

  @override
  String get addFriend => '添加好友';

  @override
  String get createGroup => '创建群聊';

  @override
  String get friendUserId => '好友 User ID（十六进制）';

  @override
  String get groupNameOptional => '群名称（可选）';

  @override
  String get typeMessage => '输入消息';

  @override
  String get messageToGroup => '发送到群组';

  @override
  String get selfId => '我的ID';

  @override
  String get appearance => '外观';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get language => '语言';

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
  String get profile => '资料';

  @override
  String get nickname => '昵称';

  @override
  String get statusMessage => '签名';

  @override
  String get saveProfile => '保存资料';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get group => '群';

  @override
  String get file => '文件';

  @override
  String get audio => '音频';

  @override
  String get friendRequestSent => '好友请求已发送';

  @override
  String get joinGroup => '加入群聊';

  @override
  String get groupId => '群ID';

  @override
  String get createAndOpen => '创建并打开';

  @override
  String get joinAndOpen => '加入并打开';

  @override
  String get knownGroups => '已知群组';

  @override
  String get selectAChat => '请选择一个会话';

  @override
  String get photo => '图片';

  @override
  String get video => '视频';

  @override
  String get autoAcceptFriendRequests => '自动接受好友申请';

  @override
  String get autoAcceptFriendRequestsDesc => '收到好友申请时自动通过';

  @override
  String get autoAcceptGroupInvites => '自动接受群组邀请';

  @override
  String get autoAcceptGroupInvitesDesc => '收到群组邀请时自动接受';

  @override
  String get bootstrapNodes => 'Bootstrap 节点';

  @override
  String get currentNode => '当前节点';

  @override
  String get viewAndTestNodes => '查看并测试节点';

  @override
  String get currentlyOnlineNoReconnect => '当前已连接，无需重新连接';

  @override
  String get addOrCreateGroup => '添加 / 创建群组';

  @override
  String get joinGroupById => '通过 ID 加入群组';

  @override
  String get enterGroupId => '请输入群组 ID';

  @override
  String get requestMessage => '申请留言';

  @override
  String get groupAlias => '本地群名称（可选）';

  @override
  String get joinAction => '发送入群申请';

  @override
  String get joinSuccess => '入群申请已发送';

  @override
  String get joinFailed => '入群失败';

  @override
  String get groupName => '群名称';

  @override
  String get enterGroupName => '请输入群名称';

  @override
  String get createAction => '创建群聊';

  @override
  String get createSuccess => '群聊已创建';

  @override
  String get createFailed => '创建群聊失败';

  @override
  String get createdGroupId => '新群组 ID';

  @override
  String get copyId => '复制 ID';

  @override
  String get copied => '已复制到剪切板';

  @override
  String get addFailed => '添加失败';

  @override
  String get enterId => '请输入 Tox ID';

  @override
  String get invalidLength => 'ID 必须为 64 或 76 位十六进制字符';

  @override
  String get invalidCharacters => '只能包含十六进制字符';

  @override
  String get paste => '粘贴';

  @override
  String get addContactHint => '输入好友的 Tox ID（64 或 76 位十六进制字符）。';

  @override
  String get verificationMessage => '验证信息';

  @override
  String get defaultFriendRequestMessage => '你好，我想添加你为好友。';

  @override
  String get friendRequestMessageTooLong => '好友请求消息不能超过 921 个字符';

  @override
  String get enterMessage => '请输入消息';

  @override
  String get autoAcceptedNewFriendRequest => '已自动接受新的好友申请';

  @override
  String get scanQrCodeToAddContact => '扫描二维码，添加我为联系人';

  @override
  String get generateCard => '生成名片';

  @override
  String get customCardText => '自定义名片文字';

  @override
  String get userId => '用户ID';

  @override
  String get saveImage => '保存图片';

  @override
  String get copy => '复制';

  @override
  String get fileCopiedSuccessfully => '文件复制成功';

  @override
  String get idCopiedToClipboard => 'ID已复制到剪切板';

  @override
  String get establishingEncryptedChannel => '正在建立 加密通道...';

  @override
  String get checkingUserInfo => '正在检查用户信息...';

  @override
  String get initializingService => '正在初始化服务...';

  @override
  String get loggingIn => '正在登录...';

  @override
  String get initializingSDK => '正在初始化 SDK...';

  @override
  String get updatingProfile => '正在更新个人资料...';

  @override
  String get initializationCompleted => '初始化完成！';

  @override
  String get loadingFriends => '正在加载好友信息...';

  @override
  String get inProgress => '进行中';

  @override
  String get completed => '完成';

  @override
  String get personalCard => '个人名片';

  @override
  String get appTitle => 'toxee';

  @override
  String get startChat => '开始聊天';

  @override
  String get pasteServerUserId => '在此粘贴服务器用户ID';

  @override
  String get groupProfile => '群组资料';

  @override
  String get invalidGroupId => '无效的群组ID';

  @override
  String maintainer(String maintainer) {
    return '维护者: $maintainer';
  }

  @override
  String get success => '成功';

  @override
  String get failed => '失败';

  @override
  String error(String error) {
    return '错误: $error';
  }

  @override
  String get saved => '已保存';

  @override
  String failedToSave(String error) {
    return '保存失败: $error';
  }

  @override
  String copyFailed(String error) {
    return '复制失败: $error';
  }

  @override
  String failedToUpdateAvatar(String error) {
    return '更新头像失败: $error';
  }

  @override
  String get failedToLoadQr => '加载二维码失败';

  @override
  String get helloFromToxee => '来自 toxee 的问候';

  @override
  String attachFailed(String error) {
    return '附件失败: $error';
  }

  @override
  String get autoFriendRequestFromToxee => '来自 toxee 的自动好友请求';

  @override
  String get reconnect => '重新连接';

  @override
  String get reconnectConfirmMessage => '将使用选定的 Bootstrap 节点重新连接。是否继续？';

  @override
  String get reconnectedWaiting => '已发起重新连接，正在等待建立连接...';

  @override
  String get reconnectWithThisNode => '使用此节点重新连接';

  @override
  String get friendOfflineCannotSendFile => '好友不在线，无法发送文件。请等待好友上线后再试。';

  @override
  String get friendOfflineSendCardFailed => '好友不在线，发送名片失败';

  @override
  String get friendOfflineSendImageFailed => '好友不在线，发送图片失败';

  @override
  String get friendOfflineSendVideoFailed => '好友不在线，发送视频失败';

  @override
  String get friendOfflineSendFileFailed => '好友不在线，发送文件失败';

  @override
  String get userNotInFriendList => '该用户不在您的好友列表中。';

  @override
  String sendFailed(String error) {
    return '发送失败: $error';
  }

  @override
  String get myId => '我的ID';

  @override
  String get sendPersonalCardToGroup => '发送个人名片到群组';

  @override
  String get personalCardSent => '个人名片已发送';

  @override
  String get sentPersonalCardToGroup => '已发送个人名片到群组';

  @override
  String get bootstrapNodesTitle => 'Bootstrap 节点';

  @override
  String get refresh => '刷新';

  @override
  String get retry => '重试';

  @override
  String lastPing(String seconds) {
    return '最后ping: $seconds秒前';
  }

  @override
  String get testNode => '测试节点';

  @override
  String get deleteAccount => '注销账号';

  @override
  String get deleteAccountConfirmMessage => '注销后账号与所有数据将永久删除且无法找回，请谨慎操作。';

  @override
  String get delete => '注销';

  @override
  String get deleteAccountEnterPasswordToConfirm => '请输入当前账号密码以确认注销。';

  @override
  String get deleteAccountTypeWordToConfirm => '请正确输入下方显示的英文单词以确认注销。';

  @override
  String deleteAccountConfirmWordPrompt(String word) {
    return '请在下框输入以下单词以确认: $word';
  }

  @override
  String get deleteAccountWrongWord => '输入的单词不正确';

  @override
  String get applications => '应用';

  @override
  String get applicationsComingSoon => '更多应用即将推出...';

  @override
  String get notificationSound => '通知声音';

  @override
  String get notificationSoundDesc => '新消息、好友申请和群组申请时播放声音';

  @override
  String get downloadsDirectory => '下载目录';

  @override
  String get selectDownloadsDirectory => '选择下载目录';

  @override
  String get changeDownloadsDirectory => '更改下载目录';

  @override
  String get downloadsDirectoryDesc => '设置默认的文件下载目录。接收的文件、音频和视频将保存到此目录。';

  @override
  String get downloadsDirectorySet => '下载目录已设置';

  @override
  String get downloadsDirectoryReset => '下载目录已重置为默认';

  @override
  String get failedToSelectDirectory => '选择目录失败';

  @override
  String get reset => '重置';

  @override
  String get autoDownloadSizeLimit => '自动下载大小限制';

  @override
  String get sizeLimitInMB => '大小限制 (MB)';

  @override
  String get autoDownloadSizeLimitDesc => '小于此大小的文件和所有图片将自动下载。大于此大小的文件需要手动点击下载按钮。';

  @override
  String get autoDownloadSizeLimitSet => '自动下载大小限制已设置为';

  @override
  String get invalidSizeLimit => '无效的大小限制，请输入 1-10000 之间的数字';

  @override
  String get save => '保存';

  @override
  String get routeSelection => '线路选择';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get canOnlySelectOnlineNode => '只能选择在线节点';

  @override
  String get canOnlySelectTestedNode => '只能选择已测试成功的节点，请先测试节点';

  @override
  String get switchNode => '切换节点';

  @override
  String switchNodeConfirm(String node) {
    return '确定切换到节点 $node 吗？切换后将重新连接。';
  }

  @override
  String get nodeSwitched => '已切换节点，正在重新连接...';

  @override
  String get selectThisNode => '切换到此节点';

  @override
  String nodeSwitchFailed(String error) {
    return '节点切换失败: $error';
  }

  @override
  String get ircChannelApp => 'IRC频道';

  @override
  String get ircChannelAppDesc => '将IRC频道连接到Tox群组以实现消息同步';

  @override
  String get install => '安装';

  @override
  String get uninstall => '卸载';

  @override
  String get ircAppInstalled => 'IRC频道应用已安装';

  @override
  String get ircAppUninstalled => 'IRC频道应用已卸载';

  @override
  String get uninstallIrcApp => '卸载IRC频道应用';

  @override
  String get uninstallIrcAppConfirm => '确定要卸载IRC频道应用吗？所有IRC频道将被移除，您将退出所有IRC群组。';

  @override
  String get addIrcChannel => '添加频道';

  @override
  String get ircChannels => 'IRC频道';

  @override
  String get ircServerConfig => 'IRC服务器配置';

  @override
  String get ircServer => '服务器';

  @override
  String get ircPort => '端口';

  @override
  String get ircUseSasl => '使用SASL认证';

  @override
  String get ircUseSaslDesc => '使用Tox公钥进行SASL认证（需要注册NickServ）';

  @override
  String get ircServerRequired => 'IRC服务器地址不能为空';

  @override
  String get ircConfigSaved => 'IRC配置已保存';

  @override
  String ircChannelAdded(String channel) {
    return 'IRC频道已添加: $channel';
  }

  @override
  String get ircChannelAddFailed => '添加IRC频道失败';

  @override
  String ircChannelRemoved(String channel) {
    return 'IRC频道已移除: $channel';
  }

  @override
  String get removeIrcChannel => '移除IRC频道';

  @override
  String removeIrcChannelConfirm(String channel) {
    return '确定要移除 $channel 吗？您将退出对应的群组。';
  }

  @override
  String get remove => '移除';

  @override
  String get joinIrcChannel => '加入IRC频道';

  @override
  String get ircChannelName => 'IRC频道名称';

  @override
  String get ircChannelHint => '#频道';

  @override
  String get ircChannelDesc => '输入IRC频道名称（例如：#channel）。将为此频道创建一个Tox群组。';

  @override
  String get enterIrcChannel => '请输入IRC频道名称';

  @override
  String get invalidIrcChannel => 'IRC频道必须以 # 或 & 开头';

  @override
  String get join => '加入';

  @override
  String get ircAppNotInstalled => '请先从应用页面安装IRC频道应用';

  @override
  String get ircChannelPassword => '频道密码';

  @override
  String get ircChannelPasswordHint => '无密码时留空';

  @override
  String get ircCustomNickname => '自定义IRC昵称';

  @override
  String get ircCustomNicknameHint => '留空则使用自动生成的昵称';

  @override
  String deleteAccountFailed(String error) {
    return '注销失败: $error';
  }

  @override
  String get directorySelectionNotSupported => '此平台不支持目录选择';

  @override
  String failedToSendFriendRequest(String error) {
    return '发送好友请求失败: $error';
  }

  @override
  String get fileDoesNotExist => '文件不存在';

  @override
  String get fileIsEmpty => '文件为空';

  @override
  String failedToSendFile(String label, String error) {
    return '发送 $label 失败: $error';
  }

  @override
  String get noReceivers => '暂无接收者';

  @override
  String messageReceivers(String count) {
    return '消息接收者 ($count)';
  }

  @override
  String get close => '关闭';

  @override
  String get nodeNotTestedWarning => '注意：此节点尚未测试，可能无法连接。';

  @override
  String get nodeTestFailedWarning => '注意：此节点测试失败，可能无法连接。';

  @override
  String get nicknameTooLong => '昵称过长';

  @override
  String get nicknameCannotBeEmpty => '昵称不能为空';

  @override
  String get statusMessageTooLong => '签名过长';

  @override
  String get manualNodeInput => '手动输入节点';

  @override
  String get nodeHost => '主机';

  @override
  String get nodePort => '端口';

  @override
  String get nodePublicKey => '公钥';

  @override
  String get setAsCurrentNode => '设置为当前节点';

  @override
  String get nodeTestSuccess => '节点测试成功';

  @override
  String get nodeTestFailed => '节点测试失败';

  @override
  String get invalidNodeInfo => '请输入有效的节点信息（主机、端口和公钥）';

  @override
  String get nodeSetSuccess => '已设为当前节点';

  @override
  String get bootstrapNodeMode => 'Bootstrap 节点模式';

  @override
  String get manualMode => '手动指定';

  @override
  String get autoMode => '自动（从网页拉取）';

  @override
  String get manualModeDesc => '手动指定 Bootstrap 节点信息';

  @override
  String get autoModeDesc => '自动从网页拉取并使用 Bootstrap 节点';

  @override
  String get autoModeDescPrefix => '自动从 ';

  @override
  String get lanMode => '局域网 Bootstrap';

  @override
  String get lanModeDesc => '使用局域网内的 Bootstrap 服务';

  @override
  String get startLocalBootstrapService => '启动本地 Bootstrap 服务';

  @override
  String get stopLocalBootstrapService => '停止本地 Bootstrap 服务';

  @override
  String get bootstrapServiceStatus => 'Bootstrap 服务状态';

  @override
  String get serviceRunning => '运行中';

  @override
  String get serviceStopped => '已停止';

  @override
  String get scanLanBootstrapServices => '扫描局域网 Bootstrap 服务';

  @override
  String get scanLanBootstrapServicesTitle => '局域网 Bootstrap 服务';

  @override
  String get scanPort => '扫描端口';

  @override
  String get startScan => '开始扫描';

  @override
  String scanningAliveIPs(int current, int total) {
    return '扫描活跃IP: $current/$total';
  }

  @override
  String probingBootstrapServices(int current, int total) {
    return '探测 Bootstrap 服务: $current/$total';
  }

  @override
  String get scanning => '扫描中...';

  @override
  String get probing => '探测中...';

  @override
  String aliveIPsFound(int count) {
    return '找到活跃IP: $count';
  }

  @override
  String get noAliveIPsFound => '未找到活跃IP';

  @override
  String get bootstrapServiceFound => '发现 Bootstrap 服务';

  @override
  String get noBootstrapService => '未发现 Bootstrap 服务';

  @override
  String get noServicesFound => '未找到服务';

  @override
  String get useAsBootstrapNode => '设为 Bootstrap 节点';

  @override
  String get ipAddress => 'IP地址';

  @override
  String get probeStatus => '探测状态';

  @override
  String get probeSingleIP => '探测该 IP';

  @override
  String probingIP(String ip) {
    return '探测 $ip...';
  }

  @override
  String get refreshAliveIPs => '刷新活跃IP';

  @override
  String get aliveIPsList => '活跃IP列表';

  @override
  String get notProbedYet => '尚未探测';

  @override
  String get probeSuccess => '发现 Bootstrap 服务';

  @override
  String get probeFailed => '未发现 Bootstrap 服务';

  @override
  String bootstrapServiceRunning(String ip, int port) {
    return 'Bootstrap 服务运行中: $ip:$port';
  }

  @override
  String get logOut => '退出登录';

  @override
  String get logOutConfirm => '确定要退出登录吗？';

  @override
  String get autoLogin => '自动登录';

  @override
  String get autoLoginEnabled => '自动登录：已启用';

  @override
  String get autoLoginDisabled => '自动登录：已禁用';

  @override
  String get autoLoginDesc => '启用后，启动应用时将自动登录。';

  @override
  String get disable => '禁用';

  @override
  String get enable => '启用';

  @override
  String get login => '登录';

  @override
  String get register => '注册';

  @override
  String get registerNewAccount => '注册新账号';

  @override
  String get unnamedAccount => '未命名账号';

  @override
  String get accountInfo => '账户信息';

  @override
  String get accountManagement => '账号管理';

  @override
  String get localAccounts => '本地账号';

  @override
  String showMore(int count) {
    return '显示更多（还有 $count 个）';
  }

  @override
  String get showLess => '收起';

  @override
  String get current => '当前';

  @override
  String get lastLogin => '最近登录';

  @override
  String get switchAccount => '切换账号';

  @override
  String get exportAccount => '导出账号';

  @override
  String get exportOptionProfileTox => 'Profile (.tox)';

  @override
  String get exportOptionProfileToxSubtitle => 'qTox compatible, profile only';

  @override
  String get exportOptionFullBackup => 'Full Backup (.zip)';

  @override
  String get exportOptionFullBackupSubtitle => 'Profile + chat history + settings';

  @override
  String get importAccount => '导入账号';

  @override
  String get setPassword => '设置密码';

  @override
  String get changePassword => '修改密码';

  @override
  String get enterPasswordToExport => '输入密码以导出账号';

  @override
  String get enterPasswordToImport => '输入密码以导入账号';

  @override
  String enterPasswordForAccount(String nickname) {
    return '输入账号 \"$nickname\" 的密码';
  }

  @override
  String get invalidPassword => '密码错误';

  @override
  String accountExportedSuccessfully(String filePath) {
    return '账号已成功导出到: $filePath';
  }

  @override
  String get accountImportedSuccessfully => '账号导入成功';

  @override
  String get passwordSetSuccessfully => '密码设置成功';

  @override
  String get passwordRemoved => '密码已移除';

  @override
  String failedToSwitchAccount(String error) {
    return '切换账号失败: $error';
  }

  @override
  String failedToExportAccount(String error) {
    return '导出账号失败: $error';
  }

  @override
  String failedToImportAccount(String error) {
    return '导入账号失败: $error';
  }

  @override
  String failedToSetPassword(String error) {
    return '设置密码失败: $error';
  }

  @override
  String get noAccountToExport => '没有可导出的账号';

  @override
  String get noAccountSelected => '未选择账号';

  @override
  String get accountAlreadyExists => '账号已存在';

  @override
  String get accountAlreadyExistsMessage => '已存在相同ID的账号。是否要更新它？';

  @override
  String get update => '更新';

  @override
  String switchAccountConfirm(String nickname) {
    return '确定要切换到 \"$nickname\" 吗？您将被登出当前账号。';
  }

  @override
  String get savedAccounts => '已保存的账号';

  @override
  String get tapToSelectDoubleTapToLogin => '点击选择，双击快速登录';

  @override
  String get tapToLogIn => '点击登录';

  @override
  String get switchToThisAccount => '切换到此账号';

  @override
  String get password => '密码';

  @override
  String get newPassword => '新密码';

  @override
  String get confirmPassword => '确认密码';

  @override
  String get leaveEmptyToRemovePassword => '留空以移除密码';

  @override
  String get passwordsDoNotMatch => '密码不匹配';

  @override
  String get never => '从未';

  @override
  String get justNow => '刚刚';

  @override
  String daysAgo(int count, String plural) {
    return '$count 天前';
  }

  @override
  String hoursAgo(int count, String plural) {
    return '$count 小时前';
  }

  @override
  String minutesAgo(int count, String plural) {
    return '$count 分钟前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '此账号已登录';

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
    return '找到 $contacts 个联系人、$groups 个群组、$messages 条消息线索';
  }

  @override
  String get searchFailed => '搜索失败，显示部分结果';

  @override
  String get callVideoCall => '视频通话';

  @override
  String get callAudioCall => '语音通话';

  @override
  String get callReject => '拒绝';

  @override
  String get callAccept => '接听';

  @override
  String get callRemoteVideo => '对方画面';

  @override
  String get callUnmute => '取消静音';

  @override
  String get callMute => '静音';

  @override
  String get callVideoOff => '关闭视频';

  @override
  String get callVideoOn => '开启视频';

  @override
  String get callSpeakerOff => '关闭扬声器';

  @override
  String get callSpeakerOn => '开启扬声器';

  @override
  String get callHangUp => '挂断';

  @override
  String get callEnded => '通话已结束';

  @override
  String get callPermissionMicrophoneRequired => '继续通话需要麦克风权限。';

  @override
  String get callPermissionCameraRequired => '继续通话需要相机权限。';

  @override
  String get callPermissionMicrophoneCameraRequired => '继续通话需要麦克风和相机权限。';

  @override
  String get callAudioInterrupted => '通话过程中音频输出发生变化或被中断。';

  @override
  String get callCalling => '呼叫中...';

  @override
  String get callMinimize => '最小化';

  @override
  String get callReturnToCall => '返回通话';

  @override
  String get callQualityGood => '连接良好';

  @override
  String get callQualityMedium => '连接一般';

  @override
  String get callQualityPoor => '连接较差';

  @override
  String get callQualityUnknown => '—';

  @override
  String get callQualityLabel => '通话质量';

  @override
  String unreadMessagesSemantics(int count) => '$count条未读消息';

  @override
  String matchingMessagesSemantics(int count) => '$count条匹配消息';

  @override
  String get statusOnline => '在线';

  @override
  String get statusOffline => '离线';

  @override
  String get noIrcChannels => '没有IRC频道';

  @override
  String get joinChannelToGetStarted => '加入频道开始使用';

  @override
  String ircUsersCount(int count) => '用户 ($count)';

  @override
  String get ircNoUsers => '暂无用户';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans(): super('zh_Hans');

  @override
  String get chats => '聊天';

  @override
  String get contacts => '联系人';

  @override
  String get requests => '请求';

  @override
  String get groups => '群组';

  @override
  String get settings => '设置';

  @override
  String get searchConversations => '按昵称/群/消息搜索';

  @override
  String get searchContacts => '搜索联系人';

  @override
  String get searchResults => '搜索结果';

  @override
  String get enterKeywordToSearch => '请输入关键词搜索';

  @override
  String get noResultsFound => '未找到结果';

  @override
  String get searchSectionMessages => '消息';

  @override
  String get searchSectionConversations => '会话';

  @override
  String get searchHint => '搜索...';

  @override
  String messageCount(int count) {
    return '$count 条消息';
  }

  @override
  String get searchChatHistory => '搜索聊天记录';

  @override
  String searchResultsCount(int count, String keyword) {
    return '共有 $count 条与「$keyword」相关的结果';
  }

  @override
  String get openChat => '打开聊天';

  @override
  String relatedChats(int count) {
    return '$count 条相关消息';
  }

  @override
  String get newItem => '新建';

  @override
  String get addFriend => '添加好友';

  @override
  String get createGroup => '创建群聊';

  @override
  String get friendUserId => '好友 User ID（十六进制）';

  @override
  String get groupNameOptional => '群名称（可选）';

  @override
  String get typeMessage => '输入消息';

  @override
  String get messageToGroup => '发送到群组';

  @override
  String get selfId => '我的ID';

  @override
  String get appearance => '外观';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get language => '语言';

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
  String get profile => '资料';

  @override
  String get nickname => '昵称';

  @override
  String get statusMessage => '签名';

  @override
  String get saveProfile => '保存资料';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get group => '群';

  @override
  String get file => '文件';

  @override
  String get audio => '音频';

  @override
  String get friendRequestSent => '好友请求已发送';

  @override
  String get joinGroup => '加入群聊';

  @override
  String get groupId => '群ID';

  @override
  String get createAndOpen => '创建并打开';

  @override
  String get joinAndOpen => '加入并打开';

  @override
  String get knownGroups => '已知群组';

  @override
  String get selectAChat => '请选择一个会话';

  @override
  String get photo => '图片';

  @override
  String get video => '视频';

  @override
  String get autoAcceptFriendRequests => '自动接受好友申请';

  @override
  String get autoAcceptFriendRequestsDesc => '收到好友申请时自动通过';

  @override
  String get autoAcceptGroupInvites => '自动接受群组邀请';

  @override
  String get autoAcceptGroupInvitesDesc => '收到群组邀请时自动接受';

  @override
  String get bootstrapNodes => 'Bootstrap 节点';

  @override
  String get currentNode => '当前节点';

  @override
  String get viewAndTestNodes => '查看并测试节点';

  @override
  String get currentlyOnlineNoReconnect => '当前已连接，无需重新连接';

  @override
  String get addOrCreateGroup => '添加 / 创建群组';

  @override
  String get joinGroupById => '通过 ID 加入群组';

  @override
  String get enterGroupId => '请输入群组 ID';

  @override
  String get requestMessage => '申请留言';

  @override
  String get groupAlias => '本地群名称（可选）';

  @override
  String get joinAction => '发送入群申请';

  @override
  String get joinSuccess => '入群申请已发送';

  @override
  String get joinFailed => '入群失败';

  @override
  String get groupName => '群名称';

  @override
  String get enterGroupName => '请输入群名称';

  @override
  String get createAction => '创建群聊';

  @override
  String get createSuccess => '群聊已创建';

  @override
  String get createFailed => '创建群聊失败';

  @override
  String get createdGroupId => '新群组 ID';

  @override
  String get copyId => '复制 ID';

  @override
  String get copied => '已复制到剪切板';

  @override
  String get addFailed => '添加失败';

  @override
  String get enterId => '请输入 Tox ID';

  @override
  String get invalidLength => 'ID 必须为 64 或 76 位十六进制字符';

  @override
  String get invalidCharacters => '只能包含十六进制字符';

  @override
  String get paste => '粘贴';

  @override
  String get addContactHint => '输入好友的 Tox ID（64 或 76 位十六进制字符）。';

  @override
  String get verificationMessage => '验证信息';

  @override
  String get defaultFriendRequestMessage => '你好，我想添加你为好友。';

  @override
  String get friendRequestMessageTooLong => '好友请求消息不能超过 921 个字符';

  @override
  String get enterMessage => '请输入消息';

  @override
  String get autoAcceptedNewFriendRequest => '已自动接受新的好友申请';

  @override
  String get scanQrCodeToAddContact => '扫描二维码，添加我为联系人';

  @override
  String get generateCard => '生成名片';

  @override
  String get customCardText => '自定义名片文字';

  @override
  String get userId => '用户ID';

  @override
  String get saveImage => '保存图片';

  @override
  String get copy => '复制';

  @override
  String get fileCopiedSuccessfully => '文件复制成功';

  @override
  String get idCopiedToClipboard => 'ID已复制到剪切板';

  @override
  String get establishingEncryptedChannel => '正在建立 加密通道...';

  @override
  String get checkingUserInfo => '正在检查用户信息...';

  @override
  String get initializingService => '正在初始化服务...';

  @override
  String get loggingIn => '正在登录...';

  @override
  String get initializingSDK => '正在初始化 SDK...';

  @override
  String get updatingProfile => '正在更新个人资料...';

  @override
  String get initializationCompleted => '初始化完成！';

  @override
  String get loadingFriends => '正在加载好友信息...';

  @override
  String get inProgress => '进行中';

  @override
  String get completed => '完成';

  @override
  String get personalCard => '个人名片';

  @override
  String get appTitle => 'toxee';

  @override
  String get startChat => '开始聊天';

  @override
  String get pasteServerUserId => '在此粘贴服务器用户ID';

  @override
  String get groupProfile => '群组资料';

  @override
  String get invalidGroupId => '无效的群组ID';

  @override
  String maintainer(String maintainer) {
    return '维护者: $maintainer';
  }

  @override
  String get success => '成功';

  @override
  String get failed => '失败';

  @override
  String error(String error) {
    return '错误: $error';
  }

  @override
  String get saved => '已保存';

  @override
  String failedToSave(String error) {
    return '保存失败: $error';
  }

  @override
  String copyFailed(String error) {
    return '复制失败: $error';
  }

  @override
  String failedToUpdateAvatar(String error) {
    return '更新头像失败: $error';
  }

  @override
  String get failedToLoadQr => '加载二维码失败';

  @override
  String get helloFromToxee => '来自 toxee 的问候';

  @override
  String attachFailed(String error) {
    return '附件失败: $error';
  }

  @override
  String get autoFriendRequestFromToxee => '来自 toxee 的自动好友请求';

  @override
  String get reconnect => '重新连接';

  @override
  String get reconnectConfirmMessage => '将使用选定的 Bootstrap 节点重新连接。是否继续？';

  @override
  String get reconnectedWaiting => '已发起重新连接，正在等待建立连接...';

  @override
  String get reconnectWithThisNode => '使用此节点重新连接';

  @override
  String get friendOfflineCannotSendFile => '好友不在线，无法发送文件。请等待好友上线后再试。';

  @override
  String get friendOfflineSendCardFailed => '好友不在线，发送名片失败';

  @override
  String get friendOfflineSendImageFailed => '好友不在线，发送图片失败';

  @override
  String get friendOfflineSendVideoFailed => '好友不在线，发送视频失败';

  @override
  String get friendOfflineSendFileFailed => '好友不在线，发送文件失败';

  @override
  String get userNotInFriendList => '该用户不在您的好友列表中。';

  @override
  String sendFailed(String error) {
    return '发送失败: $error';
  }

  @override
  String get myId => '我的ID';

  @override
  String get sendPersonalCardToGroup => '发送个人名片到群组';

  @override
  String get personalCardSent => '个人名片已发送';

  @override
  String get sentPersonalCardToGroup => '已发送个人名片到群组';

  @override
  String get bootstrapNodesTitle => 'Bootstrap 节点';

  @override
  String get refresh => '刷新';

  @override
  String get retry => '重试';

  @override
  String lastPing(String seconds) {
    return '最后ping: $seconds秒前';
  }

  @override
  String get testNode => '测试节点';

  @override
  String get deleteAccount => '注销账号';

  @override
  String get deleteAccountConfirmMessage => '注销后账号与所有数据将永久删除且无法找回，请谨慎操作。';

  @override
  String get delete => '注销';

  @override
  String get deleteAccountEnterPasswordToConfirm => '请输入当前账号密码以确认注销。';

  @override
  String get deleteAccountTypeWordToConfirm => '请正确输入下方显示的英文单词以确认注销。';

  @override
  String deleteAccountConfirmWordPrompt(String word) {
    return '请在下框输入以下单词以确认: $word';
  }

  @override
  String get deleteAccountWrongWord => '输入的单词不正确';

  @override
  String get applications => '应用';

  @override
  String get applicationsComingSoon => '更多应用即将推出...';

  @override
  String get notificationSound => '通知声音';

  @override
  String get notificationSoundDesc => '新消息、好友申请和群组申请时播放声音';

  @override
  String get downloadsDirectory => '下载目录';

  @override
  String get selectDownloadsDirectory => '选择下载目录';

  @override
  String get changeDownloadsDirectory => '更改下载目录';

  @override
  String get downloadsDirectoryDesc => '设置默认的文件下载目录。接收的文件、音频和视频将保存到此目录。';

  @override
  String get downloadsDirectorySet => '下载目录已设置';

  @override
  String get downloadsDirectoryReset => '下载目录已重置为默认';

  @override
  String get failedToSelectDirectory => '选择目录失败';

  @override
  String get reset => '重置';

  @override
  String get autoDownloadSizeLimit => '自动下载大小限制';

  @override
  String get sizeLimitInMB => '大小限制 (MB)';

  @override
  String get autoDownloadSizeLimitDesc => '小于此大小的文件和所有图片将自动下载。大于此大小的文件需要手动点击下载按钮。';

  @override
  String get autoDownloadSizeLimitSet => '自动下载大小限制已设置为';

  @override
  String get invalidSizeLimit => '无效的大小限制，请输入 1-10000 之间的数字';

  @override
  String get save => '保存';

  @override
  String get routeSelection => '线路选择';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get canOnlySelectOnlineNode => '只能选择在线节点';

  @override
  String get canOnlySelectTestedNode => '只能选择已测试成功的节点，请先测试节点';

  @override
  String get switchNode => '切换节点';

  @override
  String switchNodeConfirm(String node) {
    return '确定切换到节点 $node 吗？切换后将重新连接。';
  }

  @override
  String get nodeSwitched => '已切换节点，正在重新连接...';

  @override
  String get selectThisNode => '切换到此节点';

  @override
  String nodeSwitchFailed(String error) {
    return '节点切换失败: $error';
  }

  @override
  String get ircChannelApp => 'IRC频道';

  @override
  String get ircChannelAppDesc => '将IRC频道连接到Tox群组以实现消息同步';

  @override
  String get install => '安装';

  @override
  String get uninstall => '卸载';

  @override
  String get ircAppInstalled => 'IRC频道应用已安装';

  @override
  String get ircAppUninstalled => 'IRC频道应用已卸载';

  @override
  String get uninstallIrcApp => '卸载IRC频道应用';

  @override
  String get uninstallIrcAppConfirm => '确定要卸载IRC频道应用吗？所有IRC频道将被移除，您将退出所有IRC群组。';

  @override
  String get addIrcChannel => '添加频道';

  @override
  String get ircChannels => 'IRC频道';

  @override
  String get ircServerConfig => 'IRC服务器配置';

  @override
  String get ircServer => '服务器';

  @override
  String get ircPort => '端口';

  @override
  String get ircUseSasl => '使用SASL认证';

  @override
  String get ircUseSaslDesc => '使用Tox公钥进行SASL认证（需要注册NickServ）';

  @override
  String get ircServerRequired => 'IRC服务器地址不能为空';

  @override
  String get ircConfigSaved => 'IRC配置已保存';

  @override
  String ircChannelAdded(String channel) {
    return 'IRC频道已添加: $channel';
  }

  @override
  String get ircChannelAddFailed => '添加IRC频道失败';

  @override
  String ircChannelRemoved(String channel) {
    return 'IRC频道已移除: $channel';
  }

  @override
  String get removeIrcChannel => '移除IRC频道';

  @override
  String removeIrcChannelConfirm(String channel) {
    return '确定要移除 $channel 吗？您将退出对应的群组。';
  }

  @override
  String get remove => '移除';

  @override
  String get joinIrcChannel => '加入IRC频道';

  @override
  String get ircChannelName => 'IRC频道名称';

  @override
  String get ircChannelHint => '#频道';

  @override
  String get ircChannelDesc => '输入IRC频道名称（例如：#channel）。将为此频道创建一个Tox群组。';

  @override
  String get enterIrcChannel => '请输入IRC频道名称';

  @override
  String get invalidIrcChannel => 'IRC channel must start with # or &';

  @override
  String get join => '加入';

  @override
  String get ircAppNotInstalled => '请先从应用页面安装IRC频道应用';

  @override
  String get ircChannelPassword => '频道密码';

  @override
  String get ircChannelPasswordHint => '无密码时留空';

  @override
  String get ircCustomNickname => '自定义IRC昵称';

  @override
  String get ircCustomNicknameHint => '留空则使用自动生成的昵称';

  @override
  String deleteAccountFailed(String error) {
    return '注销失败: $error';
  }

  @override
  String get directorySelectionNotSupported => 'Directory selection is not supported on this platform';

  @override
  String failedToSendFriendRequest(String error) {
    return '发送好友请求失败: $error';
  }

  @override
  String get fileDoesNotExist => '文件不存在';

  @override
  String get fileIsEmpty => '文件为空';

  @override
  String failedToSendFile(String label, String error) {
    return '发送 $label 失败: $error';
  }

  @override
  String get noReceivers => '暂无接收者';

  @override
  String messageReceivers(String count) {
    return 'Message Receivers ($count)';
  }

  @override
  String get close => '关闭';

  @override
  String get nodeNotTestedWarning => '注意：此节点尚未测试，可能无法连接。';

  @override
  String get nodeTestFailedWarning => '注意：此节点测试失败，可能无法连接。';

  @override
  String get nicknameTooLong => 'Nickname too long';

  @override
  String get nicknameCannotBeEmpty => '昵称不能为空';

  @override
  String get statusMessageTooLong => '签名过长';

  @override
  String get manualNodeInput => '手动输入节点';

  @override
  String get nodeHost => '主机';

  @override
  String get nodePort => '端口';

  @override
  String get nodePublicKey => '公钥';

  @override
  String get setAsCurrentNode => '设置为当前节点';

  @override
  String get nodeTestSuccess => '节点测试成功';

  @override
  String get nodeTestFailed => '节点测试失败';

  @override
  String get invalidNodeInfo => '请输入有效的节点信息（主机、端口和公钥）';

  @override
  String get nodeSetSuccess => '已设为当前节点';

  @override
  String get bootstrapNodeMode => 'Bootstrap 节点模式';

  @override
  String get manualMode => '手动指定';

  @override
  String get autoMode => '自动（从网页拉取）';

  @override
  String get manualModeDesc => '手动指定 Bootstrap 节点信息';

  @override
  String get autoModeDesc => '自动从网页拉取并使用 Bootstrap 节点';

  @override
  String get autoModeDescPrefix => '自动从 ';

  @override
  String get lanMode => '局域网 Bootstrap';

  @override
  String get lanModeDesc => '使用局域网内的 Bootstrap 服务';

  @override
  String get startLocalBootstrapService => '启动本地 Bootstrap 服务';

  @override
  String get stopLocalBootstrapService => '停止本地 Bootstrap 服务';

  @override
  String get bootstrapServiceStatus => 'Bootstrap 服务状态';

  @override
  String get serviceRunning => '运行中';

  @override
  String get serviceStopped => '已停止';

  @override
  String get scanLanBootstrapServices => '扫描局域网 Bootstrap 服务';

  @override
  String get scanLanBootstrapServicesTitle => '局域网 Bootstrap 服务';

  @override
  String get scanPort => '扫描端口';

  @override
  String get startScan => '开始扫描';

  @override
  String scanningAliveIPs(int current, int total) {
    return '扫描活跃IP: $current/$total';
  }

  @override
  String probingBootstrapServices(int current, int total) {
    return '探测 Bootstrap 服务: $current/$total';
  }

  @override
  String get scanning => '扫描中...';

  @override
  String get probing => '探测中...';

  @override
  String aliveIPsFound(int count) {
    return '找到活跃IP: $count';
  }

  @override
  String get noAliveIPsFound => 'No alive IPs found';

  @override
  String get bootstrapServiceFound => '发现 Bootstrap 服务';

  @override
  String get noBootstrapService => '未发现 Bootstrap 服务';

  @override
  String get noServicesFound => '未找到服务';

  @override
  String get useAsBootstrapNode => '设为 Bootstrap 节点';

  @override
  String get ipAddress => 'IP Address';

  @override
  String get probeStatus => '探测状态';

  @override
  String get probeSingleIP => '探测该 IP';

  @override
  String probingIP(String ip) {
    return '探测 $ip...';
  }

  @override
  String get refreshAliveIPs => '刷新活跃IP';

  @override
  String get aliveIPsList => '活跃IP列表';

  @override
  String get notProbedYet => '尚未探测';

  @override
  String get probeSuccess => '发现 Bootstrap 服务';

  @override
  String get probeFailed => '未发现 Bootstrap 服务';

  @override
  String bootstrapServiceRunning(String ip, int port) {
    return 'Bootstrap 服务运行中: $ip:$port';
  }

  @override
  String get logOut => '退出登录';

  @override
  String get logOutConfirm => '确定要退出登录吗？';

  @override
  String get autoLogin => '自动登录';

  @override
  String get autoLoginEnabled => '自动登录：已启用';

  @override
  String get autoLoginDisabled => '自动登录：已禁用';

  @override
  String get autoLoginDesc => '启用后，启动应用时将自动登录。';

  @override
  String get disable => '禁用';

  @override
  String get enable => '启用';

  @override
  String get login => '登录';

  @override
  String get register => '注册';

  @override
  String get registerNewAccount => '注册新账号';

  @override
  String get unnamedAccount => '未命名账号';

  @override
  String get accountInfo => '账户信息';

  @override
  String get accountManagement => '账号管理';

  @override
  String get localAccounts => '本地账号';

  @override
  String showMore(int count) {
    return '显示更多（还有 $count 个）';
  }

  @override
  String get showLess => '收起';

  @override
  String get current => '当前';

  @override
  String get lastLogin => '最近登录';

  @override
  String get switchAccount => '切换账号';

  @override
  String get exportAccount => '导出账号';

  @override
  String get importAccount => '导入账号';

  @override
  String get setPassword => '设置密码';

  @override
  String get changePassword => '修改密码';

  @override
  String get enterPasswordToExport => '输入密码以导出账号';

  @override
  String get enterPasswordToImport => '输入密码以导入账号';

  @override
  String enterPasswordForAccount(String nickname) {
    return '输入账号 \"$nickname\" 的密码';
  }

  @override
  String get invalidPassword => '密码错误';

  @override
  String accountExportedSuccessfully(String filePath) {
    return '账号已成功导出到: $filePath';
  }

  @override
  String get accountImportedSuccessfully => '账号导入成功';

  @override
  String get passwordSetSuccessfully => '密码设置成功';

  @override
  String get passwordRemoved => '密码已移除';

  @override
  String failedToSwitchAccount(String error) {
    return '切换账号失败: $error';
  }

  @override
  String failedToExportAccount(String error) {
    return '导出账号失败: $error';
  }

  @override
  String failedToImportAccount(String error) {
    return '导入账号失败: $error';
  }

  @override
  String failedToSetPassword(String error) {
    return '设置密码失败: $error';
  }

  @override
  String get noAccountToExport => '没有可导出的账号';

  @override
  String get noAccountSelected => '未选择账号';

  @override
  String get accountAlreadyExists => '账号已存在';

  @override
  String get accountAlreadyExistsMessage => '已存在相同ID的账号。是否要更新它？';

  @override
  String get update => '更新';

  @override
  String switchAccountConfirm(String nickname) {
    return '确定要切换到 \"$nickname\" 吗？您将被登出当前账号。';
  }

  @override
  String get savedAccounts => '已保存的账号';

  @override
  String get tapToSelectDoubleTapToLogin => '点击选择，双击快速登录';

  @override
  String get tapToLogIn => '点击登录';

  @override
  String get switchToThisAccount => '切换到此账号';

  @override
  String get password => '密码';

  @override
  String get newPassword => '新密码';

  @override
  String get confirmPassword => '确认密码';

  @override
  String get leaveEmptyToRemovePassword => '留空以移除密码';

  @override
  String get passwordsDoNotMatch => '密码不匹配';

  @override
  String get never => '从未';

  @override
  String get justNow => '刚刚';

  @override
  String daysAgo(int count, String plural) {
    return '$count 天前';
  }

  @override
  String hoursAgo(int count, String plural) {
    return '$count 小时前';
  }

  @override
  String minutesAgo(int count, String plural) {
    return '$count 分钟前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '此账号已登录';

  @override
  String searchSummary(int contacts, int groups, int messages) {
    return '找到 $contacts 个联系人、$groups 个群组、$messages 条消息线索';
  }

  @override
  String get searchFailed => '搜索失败，显示部分结果';

  @override
  String get callVideoCall => '视频通话';

  @override
  String get callAudioCall => '语音通话';

  @override
  String get callReject => '拒绝';

  @override
  String get callAccept => '接听';

  @override
  String get callRemoteVideo => '对方画面';

  @override
  String get callUnmute => '取消静音';

  @override
  String get callMute => '静音';

  @override
  String get callVideoOff => '关闭视频';

  @override
  String get callVideoOn => '开启视频';

  @override
  String get callSpeakerOff => '关闭扬声器';

  @override
  String get callSpeakerOn => '开启扬声器';

  @override
  String get callHangUp => '挂断';

  @override
  String get callEnded => '通话已结束';

  @override
  String get callPermissionMicrophoneRequired => '继续通话需要麦克风权限。';

  @override
  String get callPermissionCameraRequired => '继续通话需要相机权限。';

  @override
  String get callPermissionMicrophoneCameraRequired => '继续通话需要麦克风和相机权限。';

  @override
  String get callAudioInterrupted => '通话过程中音频输出发生变化或被中断。';

  @override
  String get callCalling => '呼叫中...';

  @override
  String get callMinimize => '最小化';

  @override
  String get callReturnToCall => '返回通话';

  @override
  String get callQualityGood => '连接良好';

  @override
  String get callQualityMedium => '连接一般';

  @override
  String get callQualityPoor => '连接较差';

  @override
  String get callQualityUnknown => '—';

  @override
  String get callQualityLabel => '通话质量';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant(): super('zh_Hant');

  @override
  String get chats => '聊天';

  @override
  String get contacts => '聯絡人';

  @override
  String get requests => '請求';

  @override
  String get groups => '群組';

  @override
  String get settings => '設定';

  @override
  String get searchConversations => '按暱稱/群/訊息搜尋';

  @override
  String get searchContacts => '搜尋聯絡人';

  @override
  String get searchResults => '搜尋結果';

  @override
  String get enterKeywordToSearch => '請輸入關鍵詞搜尋';

  @override
  String get noResultsFound => '未找到結果';

  @override
  String get searchSectionMessages => '訊息';

  @override
  String get searchSectionConversations => '會話';

  @override
  String get searchHint => '搜尋...';

  @override
  String messageCount(int count) {
    return '$count 條訊息';
  }

  @override
  String get searchChatHistory => '搜尋聊天記錄';

  @override
  String searchResultsCount(int count, String keyword) {
    return '共有 $count 條與「$keyword」相關的結果';
  }

  @override
  String get openChat => '打開聊天';

  @override
  String relatedChats(int count) {
    return '$count 條相關訊息';
  }

  @override
  String get newItem => '新建';

  @override
  String get addFriend => '新增好友';

  @override
  String get createGroup => '建立群聊';

  @override
  String get friendUserId => '好友 User ID（十六進位）';

  @override
  String get groupNameOptional => '群名稱（選填）';

  @override
  String get typeMessage => '輸入訊息';

  @override
  String get messageToGroup => '發送到群組';

  @override
  String get selfId => '我的ID';

  @override
  String get appearance => '外觀';

  @override
  String get light => '淺色';

  @override
  String get dark => '深色';

  @override
  String get language => '語言';

  @override
  String get english => 'English';

  @override
  String get arabic => 'العربية';

  @override
  String get japanese => '日本語';

  @override
  String get korean => '한국어';

  @override
  String get simplifiedChinese => '簡體中文';

  @override
  String get traditionalChinese => '繁體中文';

  @override
  String get profile => '資料';

  @override
  String get nickname => '暱稱';

  @override
  String get statusMessage => '簽名';

  @override
  String get saveProfile => '儲存資料';

  @override
  String get ok => '確定';

  @override
  String get cancel => '取消';

  @override
  String get group => '群';

  @override
  String get file => '檔案';

  @override
  String get audio => '音訊';

  @override
  String get friendRequestSent => '好友請求已發送';

  @override
  String get joinGroup => '加入群聊';

  @override
  String get groupId => '群ID';

  @override
  String get createAndOpen => '建立並開啟';

  @override
  String get joinAndOpen => '加入並開啟';

  @override
  String get knownGroups => '已知群組';

  @override
  String get selectAChat => '請選擇一個會話';

  @override
  String get photo => '圖片';

  @override
  String get video => '影片';

  @override
  String get autoAcceptFriendRequests => '自動接受好友申請';

  @override
  String get autoAcceptFriendRequestsDesc => '收到好友申請時自動通過';

  @override
  String get autoAcceptGroupInvites => '自動接受群組邀請';

  @override
  String get autoAcceptGroupInvitesDesc => '收到群組邀請時自動接受';

  @override
  String get bootstrapNodes => 'Bootstrap 節點';

  @override
  String get currentNode => '目前節點';

  @override
  String get viewAndTestNodes => '查看並測試節點';

  @override
  String get currentlyOnlineNoReconnect => '目前已連線，無需重新連線';

  @override
  String get addOrCreateGroup => '新增 / 建立群組';

  @override
  String get joinGroupById => '透過 ID 加入群組';

  @override
  String get enterGroupId => '請輸入群組 ID';

  @override
  String get requestMessage => '申請留言';

  @override
  String get groupAlias => '本地群名稱（選填）';

  @override
  String get joinAction => '發送入群申請';

  @override
  String get joinSuccess => '入群申請已發送';

  @override
  String get joinFailed => '入群失敗';

  @override
  String get groupName => '群名稱';

  @override
  String get enterGroupName => '請輸入群名稱';

  @override
  String get createAction => '建立群聊';

  @override
  String get createSuccess => '群聊已建立';

  @override
  String get createFailed => '建立群聊失敗';

  @override
  String get createdGroupId => '新群組 ID';

  @override
  String get copyId => '複製 ID';

  @override
  String get copied => '已複製到剪貼板';

  @override
  String get addFailed => '新增失敗';

  @override
  String get enterId => '請輸入 Tox ID';

  @override
  String get invalidLength => 'ID 必須為 64 或 76 位十六進位字元';

  @override
  String get invalidCharacters => '只能包含十六進位字元';

  @override
  String get paste => '貼上';

  @override
  String get addContactHint => '輸入好友的 Tox ID（64 或 76 位十六進位字元）。';

  @override
  String get verificationMessage => '驗證訊息';

  @override
  String get defaultFriendRequestMessage => '你好，我想添加你為好友。';

  @override
  String get friendRequestMessageTooLong => '好友請求訊息不能超過 921 個字元';

  @override
  String get enterMessage => '請輸入訊息';

  @override
  String get autoAcceptedNewFriendRequest => '已自動接受新的好友申請';

  @override
  String get scanQrCodeToAddContact => '掃描 QR 碼，新增我為聯絡人';

  @override
  String get generateCard => '生成名片';

  @override
  String get customCardText => '自訂名片文字';

  @override
  String get userId => '用戶ID';

  @override
  String get saveImage => '儲存圖片';

  @override
  String get copy => '複製';

  @override
  String get fileCopiedSuccessfully => '檔案複製成功';

  @override
  String get idCopiedToClipboard => 'ID已複製到剪貼板';

  @override
  String get establishingEncryptedChannel => '正在建立 加密通道...';

  @override
  String get checkingUserInfo => '正在檢查用戶資訊...';

  @override
  String get initializingService => '正在初始化服務...';

  @override
  String get loggingIn => '正在登入...';

  @override
  String get initializingSDK => '正在初始化 SDK...';

  @override
  String get updatingProfile => '正在更新個人資料...';

  @override
  String get initializationCompleted => '初始化完成！';

  @override
  String get loadingFriends => '正在載入好友資訊...';

  @override
  String get inProgress => '進行中';

  @override
  String get completed => '完成';

  @override
  String get personalCard => '個人名片';

  @override
  String get appTitle => 'toxee';

  @override
  String get startChat => '開始聊天';

  @override
  String get pasteServerUserId => '在此貼上伺服器用戶ID';

  @override
  String get groupProfile => '群組資料';

  @override
  String get invalidGroupId => '無效的群組ID';

  @override
  String maintainer(String maintainer) {
    return '維護者: $maintainer';
  }

  @override
  String get success => '成功';

  @override
  String get failed => '失敗';

  @override
  String error(String error) {
    return '錯誤: $error';
  }

  @override
  String get saved => '已儲存';

  @override
  String failedToSave(String error) {
    return '儲存失敗: $error';
  }

  @override
  String copyFailed(String error) {
    return '複製失敗: $error';
  }

  @override
  String failedToUpdateAvatar(String error) {
    return '更新頭像失敗: $error';
  }

  @override
  String get failedToLoadQr => '載入 QR 碼失敗';

  @override
  String get helloFromToxee => '來自 toxee 的問候';

  @override
  String attachFailed(String error) {
    return '附件失敗: $error';
  }

  @override
  String get autoFriendRequestFromToxee => '來自 toxee 的自動好友請求';

  @override
  String get reconnect => '重新連線';

  @override
  String get reconnectConfirmMessage => '將使用選定的 Bootstrap 節點重新連線。是否繼續？';

  @override
  String get reconnectedWaiting => '已發起重新連線，正在等待建立連線...';

  @override
  String get reconnectWithThisNode => '使用此節點重新連線';

  @override
  String get friendOfflineCannotSendFile => '好友不在線，無法發送檔案。請等待好友上線後再試。';

  @override
  String get friendOfflineSendCardFailed => '好友不在線，發送名片失敗';

  @override
  String get friendOfflineSendImageFailed => '好友不在線，發送圖片失敗';

  @override
  String get friendOfflineSendVideoFailed => '好友不在線，發送視頻失敗';

  @override
  String get friendOfflineSendFileFailed => '好友不在線，發送檔案失敗';

  @override
  String get userNotInFriendList => '該用戶不在您的好友列表中。';

  @override
  String sendFailed(String error) {
    return '發送失敗: $error';
  }

  @override
  String get myId => '我的ID';

  @override
  String get sendPersonalCardToGroup => '發送個人名片到群組';

  @override
  String get personalCardSent => '個人名片已發送';

  @override
  String get sentPersonalCardToGroup => '已發送個人名片到群組';

  @override
  String get bootstrapNodesTitle => 'Bootstrap 節點';

  @override
  String get refresh => '重新整理';

  @override
  String get retry => '重試';

  @override
  String lastPing(String seconds) {
    return '最後ping: $seconds秒前';
  }

  @override
  String get testNode => '測試節點';

  @override
  String get deleteAccount => '註銷帳號';

  @override
  String get deleteAccountConfirmMessage => '註銷後帳號與所有數據將永久刪除且無法找回，請謹慎操作。';

  @override
  String get delete => '註銷';

  @override
  String get deleteAccountEnterPasswordToConfirm => '請輸入當前帳號密碼以確認註銷。';

  @override
  String get deleteAccountTypeWordToConfirm => '請正確輸入下方顯示的英文單詞以確認註銷。';

  @override
  String deleteAccountConfirmWordPrompt(String word) {
    return '請在下框輸入以下單詞以確認: $word';
  }

  @override
  String get deleteAccountWrongWord => '輸入的單詞不正確';

  @override
  String get applications => '應用';

  @override
  String get applicationsComingSoon => '更多應用即將推出...';

  @override
  String get notificationSound => '通知聲音';

  @override
  String get notificationSoundDesc => '新消息、好友申請和群組申請時播放聲音';

  @override
  String get downloadsDirectory => '下載目錄';

  @override
  String get selectDownloadsDirectory => '選擇下載目錄';

  @override
  String get changeDownloadsDirectory => '更改下載目錄';

  @override
  String get downloadsDirectoryDesc => '設置默認的文件下載目錄。接收的文件、音頻和視頻將保存到此目錄。';

  @override
  String get downloadsDirectorySet => '下載目錄已設置';

  @override
  String get downloadsDirectoryReset => '下載目錄已重置為默認';

  @override
  String get failedToSelectDirectory => '選擇目錄失敗';

  @override
  String get reset => '重置';

  @override
  String get autoDownloadSizeLimit => '自動下載大小限制';

  @override
  String get sizeLimitInMB => '大小限制 (MB)';

  @override
  String get autoDownloadSizeLimitDesc => '小於此大小的文件和所有圖片將自動下載。大於此大小的文件需要手動點擊下載按鈕。';

  @override
  String get autoDownloadSizeLimitSet => '自動下載大小限制已設置為';

  @override
  String get invalidSizeLimit => '無效的大小限制，請輸入 1-10000 之間的數字';

  @override
  String get save => '保存';

  @override
  String get routeSelection => '線路選擇';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get canOnlySelectOnlineNode => '只能選擇在線節點';

  @override
  String get canOnlySelectTestedNode => '只能選擇已測試成功的節點，請先測試節點';

  @override
  String get switchNode => '切換節點';

  @override
  String switchNodeConfirm(String node) {
    return '確定切換到節點 $node 嗎？切換後將重新連線。';
  }

  @override
  String get nodeSwitched => '已切換節點，正在重新連線...';

  @override
  String get selectThisNode => '切換到此節點';

  @override
  String nodeSwitchFailed(String error) {
    return '節點切換失敗: $error';
  }

  @override
  String get ircChannelApp => 'IRC頻道';

  @override
  String get ircChannelAppDesc => '將IRC頻道連接到Tox群組以實現消息同步';

  @override
  String get install => '安裝';

  @override
  String get uninstall => '卸載';

  @override
  String get ircAppInstalled => 'IRC頻道應用已安裝';

  @override
  String get ircAppUninstalled => 'IRC頻道應用已卸載';

  @override
  String get uninstallIrcApp => '卸載IRC頻道應用';

  @override
  String get uninstallIrcAppConfirm => '確定要卸載IRC頻道應用嗎？所有IRC頻道將被移除，您將退出所有IRC群組。';

  @override
  String get addIrcChannel => '添加頻道';

  @override
  String get ircChannels => 'IRC頻道';

  @override
  String get ircServerConfig => 'IRC伺服器配置';

  @override
  String get ircServer => '伺服器';

  @override
  String get ircPort => '端口';

  @override
  String get ircUseSasl => '使用SASL認證';

  @override
  String get ircUseSaslDesc => '使用Tox公鑰進行SASL認證（需要註冊NickServ）';

  @override
  String get ircServerRequired => 'IRC伺服器地址不能為空';

  @override
  String get ircConfigSaved => 'IRC配置已保存';

  @override
  String ircChannelAdded(String channel) {
    return 'IRC頻道已添加: $channel';
  }

  @override
  String get ircChannelAddFailed => '添加IRC頻道失敗';

  @override
  String ircChannelRemoved(String channel) {
    return 'IRC頻道已移除: $channel';
  }

  @override
  String get removeIrcChannel => '移除IRC頻道';

  @override
  String removeIrcChannelConfirm(String channel) {
    return '確定要移除 $channel 嗎？您將退出對應的群組。';
  }

  @override
  String get remove => '移除';

  @override
  String get joinIrcChannel => '加入IRC頻道';

  @override
  String get ircChannelName => 'IRC頻道名稱';

  @override
  String get ircChannelHint => '#頻道';

  @override
  String get ircChannelDesc => '輸入IRC頻道名稱（例如：#channel）。將為此頻道創建一個Tox群組。';

  @override
  String get enterIrcChannel => '請輸入IRC頻道名稱';

  @override
  String get invalidIrcChannel => 'IRC頻道必須以 # 或 & 開頭';

  @override
  String get join => '加入';

  @override
  String get ircAppNotInstalled => '請先從應用頁面安裝IRC頻道應用';

  @override
  String get ircChannelPassword => '頻道密碼';

  @override
  String get ircChannelPasswordHint => '無密碼時留空';

  @override
  String get ircCustomNickname => '自定義IRC暱稱';

  @override
  String get ircCustomNicknameHint => '留空則使用自動生成的暱稱';

  @override
  String deleteAccountFailed(String error) {
    return '註銷失敗: $error';
  }

  @override
  String get directorySelectionNotSupported => '此平台不支持目錄選擇';

  @override
  String failedToSendFriendRequest(String error) {
    return '發送好友請求失敗: $error';
  }

  @override
  String get fileDoesNotExist => '文件不存在';

  @override
  String get fileIsEmpty => '文件為空';

  @override
  String failedToSendFile(String label, String error) {
    return '發送 $label 失敗: $error';
  }

  @override
  String get noReceivers => '暫無接收者';

  @override
  String messageReceivers(String count) {
    return '消息接收者 ($count)';
  }

  @override
  String get close => '關閉';

  @override
  String get nodeNotTestedWarning => '注意：此節點尚未測試，可能無法連接。';

  @override
  String get nodeTestFailedWarning => '注意：此節點測試失敗，可能無法連接。';

  @override
  String get nicknameTooLong => '暱稱過長';

  @override
  String get nicknameCannotBeEmpty => '暱稱不能為空';

  @override
  String get statusMessageTooLong => '簽名過長';

  @override
  String get manualNodeInput => '手動輸入節點';

  @override
  String get nodeHost => '主機';

  @override
  String get nodePort => '端口';

  @override
  String get nodePublicKey => '公鑰';

  @override
  String get setAsCurrentNode => '設置為當前節點';

  @override
  String get nodeTestSuccess => '節點測試成功';

  @override
  String get nodeTestFailed => '節點測試失敗';

  @override
  String get invalidNodeInfo => '請輸入有效的節點信息（主機、端口和公鑰）';

  @override
  String get nodeSetSuccess => '已設為目前節點';

  @override
  String get bootstrapNodeMode => 'Bootstrap 節點模式';

  @override
  String get manualMode => '手動指定';

  @override
  String get autoMode => '自動（從網頁拉取）';

  @override
  String get manualModeDesc => '手動指定 Bootstrap 節點資訊';

  @override
  String get autoModeDesc => '自動從網頁拉取並使用 Bootstrap 節點';

  @override
  String get autoModeDescPrefix => '自動從 ';

  @override
  String get lanMode => '局域網 Bootstrap';

  @override
  String get lanModeDesc => '使用局域網內的 Bootstrap 服務';

  @override
  String get startLocalBootstrapService => '啟動本地 Bootstrap 服務';

  @override
  String get stopLocalBootstrapService => '停止本地 Bootstrap 服務';

  @override
  String get bootstrapServiceStatus => 'Bootstrap 服務狀態';

  @override
  String get serviceRunning => '運行中';

  @override
  String get serviceStopped => '已停止';

  @override
  String get scanLanBootstrapServices => '掃描局域網 Bootstrap 服務';

  @override
  String get scanLanBootstrapServicesTitle => '局域網 Bootstrap 服務';

  @override
  String get scanPort => '掃描端口';

  @override
  String get startScan => '開始掃描';

  @override
  String scanningAliveIPs(int current, int total) {
    return '掃描活躍IP: $current/$total';
  }

  @override
  String probingBootstrapServices(int current, int total) {
    return '探測 Bootstrap 服務: $current/$total';
  }

  @override
  String get scanning => '掃描中...';

  @override
  String get probing => '探測中...';

  @override
  String aliveIPsFound(int count) {
    return '找到活躍IP: $count';
  }

  @override
  String get noAliveIPsFound => '未找到活躍IP';

  @override
  String get bootstrapServiceFound => '發現 Bootstrap 服務';

  @override
  String get noBootstrapService => '未發現 Bootstrap 服務';

  @override
  String get noServicesFound => '未找到服務';

  @override
  String get useAsBootstrapNode => '設為 Bootstrap 節點';

  @override
  String get ipAddress => 'IP地址';

  @override
  String get probeStatus => '探測狀態';

  @override
  String get probeSingleIP => '探測該 IP';

  @override
  String probingIP(String ip) {
    return '探測 $ip...';
  }

  @override
  String get refreshAliveIPs => '刷新活躍IP';

  @override
  String get aliveIPsList => '活躍IP列表';

  @override
  String get notProbedYet => '尚未探測';

  @override
  String get probeSuccess => '發現 Bootstrap 服務';

  @override
  String get probeFailed => '未發現 Bootstrap 服務';

  @override
  String bootstrapServiceRunning(String ip, int port) {
    return 'Bootstrap 服務運行中: $ip:$port';
  }

  @override
  String get logOut => '登出';

  @override
  String get logOutConfirm => '確定要登出嗎？';

  @override
  String get autoLogin => '自動登入';

  @override
  String get autoLoginEnabled => '自動登入：已啟用';

  @override
  String get autoLoginDisabled => '自動登入：已停用';

  @override
  String get autoLoginDesc => '啟用後，啟動應用時將自動登入。';

  @override
  String get disable => '停用';

  @override
  String get enable => '啟用';

  @override
  String get login => '登入';

  @override
  String get register => '註冊';

  @override
  String get registerNewAccount => '註冊新帳號';

  @override
  String get unnamedAccount => '未命名帳號';

  @override
  String get accountInfo => '帳戶資訊';

  @override
  String get accountManagement => '帳號管理';

  @override
  String get localAccounts => '本地帳號';

  @override
  String showMore(int count) {
    return '顯示更多（還有 $count 個）';
  }

  @override
  String get showLess => '收起';

  @override
  String get current => '當前';

  @override
  String get lastLogin => '最近登入';

  @override
  String get switchAccount => '切換帳號';

  @override
  String get exportAccount => '匯出帳號';

  @override
  String get importAccount => '匯入帳號';

  @override
  String get setPassword => '設定密碼';

  @override
  String get changePassword => '修改密碼';

  @override
  String get enterPasswordToExport => '輸入密碼以匯出帳號';

  @override
  String get enterPasswordToImport => '輸入密碼以匯入帳號';

  @override
  String enterPasswordForAccount(String nickname) {
    return '輸入帳號 \"$nickname\" 的密碼';
  }

  @override
  String get invalidPassword => '密碼錯誤';

  @override
  String accountExportedSuccessfully(String filePath) {
    return '帳號已成功匯出到: $filePath';
  }

  @override
  String get accountImportedSuccessfully => '帳號匯入成功';

  @override
  String get passwordSetSuccessfully => '密碼設定成功';

  @override
  String get passwordRemoved => '密碼已移除';

  @override
  String failedToSwitchAccount(String error) {
    return '切換帳號失敗: $error';
  }

  @override
  String failedToExportAccount(String error) {
    return '匯出帳號失敗: $error';
  }

  @override
  String failedToImportAccount(String error) {
    return '匯入帳號失敗: $error';
  }

  @override
  String failedToSetPassword(String error) {
    return '設定密碼失敗: $error';
  }

  @override
  String get noAccountToExport => '沒有可匯出的帳號';

  @override
  String get noAccountSelected => '未選擇帳號';

  @override
  String get accountAlreadyExists => '帳號已存在';

  @override
  String get accountAlreadyExistsMessage => '已存在相同ID的帳號。是否要更新它？';

  @override
  String get update => '更新';

  @override
  String switchAccountConfirm(String nickname) {
    return '確定要切換到 \"$nickname\" 嗎？您將被登出當前帳號。';
  }

  @override
  String get savedAccounts => '已儲存的帳號';

  @override
  String get tapToSelectDoubleTapToLogin => '點擊選擇，雙擊快速登入';

  @override
  String get tapToLogIn => '點擊登入';

  @override
  String get switchToThisAccount => '切換到此帳號';

  @override
  String get password => '密碼';

  @override
  String get newPassword => '新密碼';

  @override
  String get confirmPassword => '確認密碼';

  @override
  String get leaveEmptyToRemovePassword => '留空以移除密碼';

  @override
  String get passwordsDoNotMatch => '密碼不匹配';

  @override
  String get never => '從未';

  @override
  String get justNow => '剛剛';

  @override
  String daysAgo(int count, String plural) {
    return '$count 天前';
  }

  @override
  String hoursAgo(int count, String plural) {
    return '$count 小時前';
  }

  @override
  String minutesAgo(int count, String plural) {
    return '$count 分鐘前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '此帳號已登入';

  @override
  String searchSummary(int contacts, int groups, int messages) {
    return '找到 $contacts 個聯絡人、$groups 個群組、$messages 條訊息線索';
  }

  @override
  String get searchFailed => '搜尋失敗，顯示部分結果';

  @override
  String get callVideoCall => '視訊通話';

  @override
  String get callAudioCall => '語音通話';

  @override
  String get callReject => '拒絕';

  @override
  String get callAccept => '接聽';

  @override
  String get callRemoteVideo => '對方畫面';

  @override
  String get callUnmute => '取消靜音';

  @override
  String get callMute => '靜音';

  @override
  String get callVideoOff => '關閉視訊';

  @override
  String get callVideoOn => '開啟視訊';

  @override
  String get callSpeakerOff => '關閉揚聲器';

  @override
  String get callSpeakerOn => '開啟揚聲器';

  @override
  String get callHangUp => '掛斷';

  @override
  String get callEnded => '通話已結束';

  @override
  String get callPermissionMicrophoneRequired => '繼續通話需要麥克風權限。';

  @override
  String get callPermissionCameraRequired => '繼續通話需要相機權限。';

  @override
  String get callPermissionMicrophoneCameraRequired => '繼續通話需要麥克風和相機權限。';

  @override
  String get callAudioInterrupted => '通話過程中音訊輸出發生變化或被中斷。';

  @override
  String get callCalling => '撥打中...';

  @override
  String get callMinimize => '最小化';

  @override
  String get callReturnToCall => '返回通話';

  @override
  String get callQualityGood => '連線良好';

  @override
  String get callQualityMedium => '連線一般';

  @override
  String get callQualityPoor => '連線較差';

  @override
  String get callQualityUnknown => '—';

  @override
  String get callQualityLabel => '通話品質';
}
