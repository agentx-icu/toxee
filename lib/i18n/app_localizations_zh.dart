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
  String get general => '通用';

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
  String get joinQueued => '当前离线 — 入群申请将在重新连接后发送';

  @override
  String get offlineBanner => '当前离线 — 群组操作将在重新连接后排队处理。';

  @override
  String get groupType => '群组类型';

  @override
  String get publicGroup => '公开';

  @override
  String get privateGroup => '私密';

  @override
  String get publicGroupHint => '公开群 — 在 DHT 上可被发现，知道群 ID 的人均可加入。';

  @override
  String get privateGroupHint => '私密群 — 仅限邀请加入，不在 DHT 上公告。';

  @override
  String get conferenceHint => '传统会议群 — 旧协议，没有角色或持久化。';

  @override
  String get searchHintBody => '搜索联系人、群组和消息';

  @override
  String get noResultsFoundHint => '试试更短的关键词或检查拼写';

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
  String get invalidLength => 'ID 长度不正确';

  @override
  String get invalidCharacters => '只能包含十六进制字符';

  @override
  String get paste => '粘贴';

  @override
  String get addContactHint => '请输入对方的 Tox 地址。';

  @override
  String get addFriendInvalidToxIdHint => 'Tox 地址必须是 76 位十六进制字符';

  @override
  String get verificationMessage => '验证信息';

  @override
  String get defaultFriendRequestMessage => '你好，我想添加你为好友。';

  @override
  String get friendRequestMessageTooLong => '好友请求消息不能超过 921 个字符';

  @override
  String get enterMessage => '请输入消息';

  @override
  String get noGroupMembers => '暂无成员';

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
  String get autoDownloadSizeLimitDesc =>
      '小于此大小的文件和所有图片将自动下载。大于此大小的文件需要手动点击下载按钮。';

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
  String get canOnlySelectTestedNode => '选择此节点前，请先成功发送引导请求';

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
  String get ircStatusDisconnected => '已断开';

  @override
  String get ircStatusConnecting => '连接中';

  @override
  String get ircStatusConnected => '已连接';

  @override
  String get ircStatusAuthenticating => '认证中';

  @override
  String get ircStatusReconnecting => '重连中';

  @override
  String get ircStatusError => '错误';

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
  String ircChannelAddedNotConnected(String channel) {
    return '频道 $channel 已添加，但无法建立 IRC 连接';
  }

  @override
  String get ircAppInstalledNoLibrary => 'IRC 应用已安装，但本设备不支持实时 IRC 连接';

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
  String get nodeNotTestedWarning => '尚未测试此节点。';

  @override
  String get nodeTestFailedWarning => '此节点未响应，可能不可用。';

  @override
  String get nodeTestInconclusiveWarning => '无法从本设备检测该节点，因此对它是否可用一无所知。';

  @override
  String get nicknameTooLong => '昵称过长';

  @override
  String get nicknameCannotBeEmpty => '昵称不能为空';

  @override
  String get statusMessageTooLong => '签名过长';

  @override
  String get passwordStrengthWeak => '弱';

  @override
  String get passwordStrengthFair => '一般';

  @override
  String get passwordStrengthGood => '良好';

  @override
  String get passwordStrengthStrong => '强';

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
  String get nodeTestSuccess => '节点可达';

  @override
  String get nodeTestUdpUnavailable => '节点测试需要 UDP，本设备当前仅使用 TCP';

  @override
  String get nodeTestFailed => '节点不可达';

  @override
  String get nodeTestUnavailable => '本设备无法执行节点测试';

  @override
  String get failedToLoadBootstrapNodes => '加载Bootstrap 节点失败';

  @override
  String get failedToStartBootstrapService => '启动引导服务失败';

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
  String get exportOptionProfileTox => '配置文件（.tox）';

  @override
  String get exportOptionProfileToxSubtitle => '兼容 qTox，仅包含配置文件';

  @override
  String get exportOptionFullBackup => '完整备份（.zip）';

  @override
  String get exportOptionFullBackupSubtitle => '配置文件 + 聊天记录 + 设置';

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
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '此账号已登录';

  @override
  String get upgradeRequiredTitle => '请升级应用';

  @override
  String upgradeRequiredMessage(int storedVersion, int currentVersion) {
    return '你的数据由更新版本的应用保存（数据版本：$storedVersion），当前版本最高仅支持 $currentVersion。请安装最新版本后继续。';
  }

  @override
  String get upgradeAppTitle => 'toxee';

  @override
  String get hide => '隐藏';

  @override
  String get pressBackAgainToExit => '再按一次返回键退出';

  @override
  String get startupFailed => '启动失败';

  @override
  String get unknownError => '未知错误';

  @override
  String get goToLogin => '前往登录';

  @override
  String get conference => '会议群';

  @override
  String get defaultJoinRequestMessage => '你好，请邀请我加入这个群';

  @override
  String get userNotFoundPleaseRegister => '未找到该用户，请先注册。';

  @override
  String get nicknameDoesNotMatch => '昵称不匹配。请使用注册时的昵称，或注册新账号。';

  @override
  String get accountAlreadyExistsPleaseLogin => '账号已存在。请直接登录，或使用其他昵称。';

  @override
  String get profileNotFoundImportRestore => '未找到该账号的配置文件，请导入账号或恢复备份。';

  @override
  String get failedToInitializeTIMManager => 'TIMManager SDK 初始化失败';

  @override
  String get failedToGetToxId => '获取 Tox ID 失败';

  @override
  String get failedToGenerateToxId => '生成 Tox ID 失败';

  @override
  String get registrationCouldNotCreateProfile => '注册时无法创建唯一的配置文件，请重试。';

  @override
  String get importedAccount => '已导入账号';

  @override
  String get unknown => '未知';

  @override
  String sendingToGroupsNotSupported(String label) {
    return '暂不支持向群组发送$label';
  }

  @override
  String noLabelSelected(String label) {
    return '未选择$label';
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
  String get callSwitchCamera => '切换摄像头';

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
  String get callIncomingNotificationPermissionRequired =>
      '启用通知权限前，来电只能在 Toxee 应用内响铃。';

  @override
  String get callFailedGroupUnsupported => '暂不支持群组通话。';

  @override
  String get callFailedSignaling => '呼叫失败，请重试。';

  @override
  String get callFailedMediaChannel => '无法建立通话媒体通道。';

  @override
  String get callVideoUnsupportedPlatform => '当前平台暂不支持视频通话（无摄像头支持）。';

  @override
  String get callAudioInterrupted => '通话过程中音频输出发生变化或被中断。';

  @override
  String get callBusyInCall => '请先结束当前通话。';

  @override
  String get callBusyInConference => '请先退出语音会议，再发起或接听通话。';

  @override
  String get callBusyInOtherConference => '你已在另一个语音会议中，请先退出。';

  @override
  String get callPeerBusy => '对方正在通话中。';

  @override
  String get callConferenceMuteIncoming => '静音他人';

  @override
  String get callConferenceUnmuteIncoming => '收听他人';

  @override
  String get callConferenceListenOnly => '仅收听 — 麦克风不可用。';

  @override
  String get callCalling => '呼叫中...';

  @override
  String get callLeaving => '正在离开会议...';

  @override
  String callReceivedFrames(int count) {
    return '已接收 $count 帧';
  }

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
  String unreadMessagesSemantics(int count) {
    return '$count 条未读消息';
  }

  @override
  String matchingMessagesSemantics(int count) {
    return '$count 条匹配的消息';
  }

  @override
  String get statusOnline => '在线';

  @override
  String get statusOffline => '离线';

  @override
  String get noIrcChannels => '暂无IRC频道';

  @override
  String get joinChannelToGetStarted => '加入一个频道开始使用';

  @override
  String ircUsersCount(int count) {
    return '用户（$count）';
  }

  @override
  String get ircNoUsers => '暂无用户';

  @override
  String get passwordVisibility => '切换密码可见';

  @override
  String get nicknameHintExample => '例如：Alice';

  @override
  String get callAudioRouteSystem => '此平台音频输出由系统管理';

  @override
  String get copyFullToxId => '复制完整 ID';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get idLabel => 'ID：';

  @override
  String errorBannerLabel(String message) {
    return '错误：$message';
  }

  @override
  String searchResultContactSemantics(String name) {
    return '$name，联系人';
  }

  @override
  String searchResultGroupSemantics(String name) {
    return '$name，群组';
  }

  @override
  String searchResultMessageSemantics(String name) {
    return '$name，消息';
  }

  @override
  String searchResultConversationSemantics(String name) {
    return '$name，会话';
  }

  @override
  String get importNoFileSelected => '未选择文件';

  @override
  String get importCancelled => '已取消';

  @override
  String get recoveryBlockedTitle => '账号恢复未完成';

  @override
  String get recoveryBlockedBody =>
      'toxee 发现一个未完成的账号恢复或删除操作，且无法读取其记录，因此没有打开任何账号——继续可能会破坏数据。\n\n你的账号及其文件仍在本机。请不要重新注册，也不要清除应用数据，否则数据会永久丢失。请反馈下方信息以便修复。';

  @override
  String get secureStorageUnavailable =>
      '安全存储当前不可用，toxee 无法校验该账号的密码。这通常是临时问题——请重试，或先解锁设备钥匙串。';

  @override
  String get recoverLegacyDataAction => '恢复旧版本的数据';

  @override
  String get recoverLegacyDataConfirm =>
      '本机仍保留着 toxee 支持多账号之前的聊天记录、待发消息和联系人头像。要把它们并入当前登录的账号吗？\n\n请仅在确认这些数据属于你时操作。这些数据只能被一个账号认领一次。\n\n确认后会退出登录，以便在下次登录时完成合并。';

  @override
  String get recoverLegacyDataClaimed =>
      '该账号将接管这些旧数据。请退出并重新登录以完成合并——在登录时合并才能保证当前的聊天记录和待发消息不受影响。';

  @override
  String get recoverLegacyDataDone => '旧版本数据已并入当前账号。';

  @override
  String get recoverLegacyDataUnavailable => '无法认领这些数据——它们可能已归本机上的其他账号所有。';

  @override
  String get accountRegistryUnreadable =>
      '无法读取已保存的账号列表。账号文件仍在本机，请不要重新注册；请反馈此问题以便修复账号列表。';

  @override
  String get importedAccountDefaultName => '已导入账号';

  @override
  String failedToImport(String error) {
    return '导入失败：$error';
  }

  @override
  String get selectConversationEmptyState => '选择一个会话开始聊天';

  @override
  String get newConversationTooltip => '新建会话';

  @override
  String get pinConversation => '置顶';

  @override
  String get unpinConversation => '取消置顶';

  @override
  String get markConversationAsRead => '标为已读';

  @override
  String get deleteConversationTitle => '删除会话？';

  @override
  String deleteConversationBody(String name) {
    return '将从聊天列表中移除“$name”。聊天记录仍保留在本地。';
  }

  @override
  String get firstRunBackupWizardTitle => '保存你的账户文件';

  @override
  String get firstRunBackupWizardBody =>
      '你的账户仅存在于这台设备。请将 .tox 文件保存到安全的位置（云盘、密码管理器、U 盘）。一旦丢失这台设备而又没有备份，账户和所有联系人都将无法恢复。';

  @override
  String get firstRunBackupWizardExportNow => '立即导出';

  @override
  String get firstRunBackupWizardLater => '稍后再说';

  @override
  String get firstRunBackupWizardDismissTitle => '跳过备份？';

  @override
  String get firstRunBackupWizardDismissBody =>
      '如果丢失此设备，你将失去账户和所有联系人。没有任何恢复方式。';

  @override
  String get firstRunBackupWizardDismissConfirm => '我已了解，继续';

  @override
  String firstRunBackupWizardExportFailed(String error) {
    return '无法保存账户文件：$error';
  }

  @override
  String get restoreFromToxFile => '从 .tox 文件恢复';

  @override
  String restoreFromToxFileSuccess(String nickname) {
    return '已恢复账户：$nickname';
  }

  @override
  String get restoreFromToxFileInvalidFile => '该文件不是有效的 Tox 配置文件。';

  @override
  String get pairDeviceHostTitle => '配对另一台设备';

  @override
  String get pairDeviceClientTitle => '与另一台设备配对';

  @override
  String get pairingHostInstructions =>
      '在另一台设备上打开 toxee，选择“与另一台设备配对”，然后扫描此二维码。';

  @override
  String get pairingClientScanInstructions => '将摄像头对准另一台设备上显示的二维码。';

  @override
  String get pairingClientPasteInstructions =>
      '此设备不支持摄像头扫描。请将另一台设备显示的配对链接粘贴到下方。';

  @override
  String get pairingPasteUrlLabel => '配对链接';

  @override
  String get pairingConnectButton => '连接';

  @override
  String get pairingWaitingForPeer => '等待另一台设备连接……';

  @override
  String get pairingVerifyCodeHeader => '请确认两台设备显示的验证码相同';

  @override
  String get pairingVerifyCodeInstructions =>
      '如果验证码与另一台设备显示的一致，请点击下方按钮。如果不一致，请取消——可能有人在拦截连接。';

  @override
  String get pairingCodesMatch => '验证码一致';

  @override
  String get pairingHostCompleted => '账号已发送。另一台设备现在拥有你的账号。';

  @override
  String get pairingClientCompleted => '账号已接收。配对完成。';

  @override
  String get pairingCancelled => '已取消配对。';

  @override
  String get pairingTimeout => '配对超时，请重试。';

  @override
  String pairingNetworkError(String detail) {
    return '配对时发生网络错误：$detail';
  }

  @override
  String pairingProtocolError(String detail) {
    return '配对握手失败：$detail';
  }

  @override
  String pairingInvalidUrl(String detail) {
    return '此二维码不是有效的配对邀请：$detail';
  }

  @override
  String get pairingDecryptFailed => '无法解密接收到的资料。配对过程可能被篡改——请在可信网络上重试。';

  @override
  String get pairingNoLanInterface => '未检测到局域网。请连接 WiFi 或以太网后重试。';

  @override
  String get pairThisAccountToAnotherDevice => '将此账号配对到另一台设备';

  @override
  String get pairWithAnotherDevice => '与已有此账号的另一台设备配对';

  @override
  String get devicesSectionTitle => '设备';

  @override
  String get done => '完成';

  @override
  String get runtimeForegroundTitle => 'Toxee 正在运行';

  @override
  String get runtimeForegroundBody => '保持连接，以便接收消息和通话。';

  @override
  String get runtimeForegroundSettingsLabel => '通知设置';

  @override
  String get runtimeForegroundCallTitle => '通话中';

  @override
  String get runtimeForegroundCallBody => 'Toxee 正在保持通话连接。';

  @override
  String runtimeForegroundCallBodyWithCaller(String name) {
    return '与 $name 通话中';
  }

  @override
  String get appTagline => '私密的点对点通讯工具';

  @override
  String get noBootstrapNodes => '没有Bootstrap 节点';

  @override
  String get importMayHaveCompleted => '这次导入没能撤销，该账号可能仍然存在。请先查看账号列表再重新导入。';

  @override
  String get importBlockedByPendingImport =>
      '上一次账号导入被中断，还没有清理完。请重启 toxee 完成撤销后再重新导入。';

  @override
  String get friendRequestQueued => '当前离线 — 好友请求已排队，将在重新连接后发送';

  @override
  String get cannotAddSelfAsFriend => '不能添加自己为好友';

  @override
  String get friendRequestAlreadySent => '本次已发送过好友请求';

  @override
  String get alreadyInFriendList => '该用户已在你的好友列表中';

  @override
  String get addFriendOfflineBanner => '当前离线 — 好友请求将排队，并在重新连接后自动发送。';

  @override
  String get scanQr => '扫描二维码';

  @override
  String get sendingInProgress => '正在发送...';

  @override
  String get firewallHintWindows => '在 Windows 上，防火墙可能会拦截传入连接；如有提示，请允许本应用通过。';

  @override
  String get firewallHintLinux => '在 Linux 上，网络操作可能需要相应的权限或防火墙规则。';

  @override
  String get nodePublicKeyHint => '公钥（十六进制）';

  @override
  String get failedToAddBootstrapNode => '添加Bootstrap 节点失败';

  @override
  String get couldNotRemovePassword => '无法移除密码';

  @override
  String get couldNotSavePassword => '无法保存密码';

  @override
  String mediaSent(String label) {
    return '$label已发送';
  }

  @override
  String get dhtUnreachableUsingFallback =>
      '无法连接到 DHT。正在使用备用Bootstrap 节点——你的网络可能屏蔽了 UDP，或节点已下线。';

  @override
  String get dhtUnreachableTimeout => '30 秒内无法连接到 DHT，请检查网络连接。';

  @override
  String chatSdkInitFailed(String error) {
    return '聊天 SDK 初始化失败：$error';
  }

  @override
  String messageTooLongMaxBytes(int maxBytes) {
    return '消息过长（最多 $maxBytes 字节）';
  }

  @override
  String get friendOfflineWillRetry => '好友不在线 — 将在对方重新上线后重试';

  @override
  String get groupFileTransferUnsupported => '暂不支持在群聊中传输文件';

  @override
  String fileSendFailed(String error) {
    return '文件发送失败：$error';
  }

  @override
  String errorWithCode(int code) {
    return '错误码 $code';
  }

  @override
  String pairingLanUnreachable(String detail) {
    return '两台设备在当前网络中无法互相发现。请尝试使用个人热点，或改用“导出 → 导入”文件的方式。（$detail）';
  }

  @override
  String get notificationNewFriendRequest => '新的好友请求';

  @override
  String notificationFriendRequestFrom(String name) {
    return '好友请求：$name';
  }

  @override
  String get notificationMissedCall => '未接来电';

  @override
  String get notificationMissedVideoCall => '未接视频来电';

  @override
  String get notificationIncomingCall => '来电';

  @override
  String get notificationIncomingVideoCall => '视频来电';

  @override
  String get notificationUnknownCaller => 'Toxee 联系人';

  @override
  String get notificationNewMessage => '新消息';

  @override
  String get previewImage => '[图片]';

  @override
  String get previewVideo => '[视频]';

  @override
  String get previewVoice => '[语音]';

  @override
  String previewVoiceWithDuration(int seconds) {
    return '[语音 $seconds秒]';
  }

  @override
  String get previewFile => '[文件]';

  @override
  String previewFileWithName(String name) {
    return '[文件] $name';
  }

  @override
  String get previewSticker => '[贴纸]';

  @override
  String get previewLocation => '[位置]';

  @override
  String get previewCustomMessage => '[自定义消息]';

  @override
  String get previewGroupEvent => '[群组事件]';

  @override
  String get previewMessage => '[消息]';

  @override
  String get channelMessagesName => '消息';

  @override
  String get channelMessagesDescription => '收到 Tox 联系人的新消息时通知。';

  @override
  String get channelFriendRequestsName => '好友请求';

  @override
  String get channelFriendRequestsDescription => '有人向你发送好友请求时通知。';

  @override
  String get channelGroupInvitesName => '群邀请';

  @override
  String get channelGroupInvitesDescription => '有人邀请你加入群聊时通知。';

  @override
  String get channelMissedCallsName => '未接来电';

  @override
  String get channelMissedCallsDescription => '来电未能接通或被错过时通知。';

  @override
  String get channelIncomingCallsName => '来电';

  @override
  String get channelIncomingCallsDescription => 'Toxee 来电时的全屏提醒。';

  @override
  String get notificationOpenAction => '打开 Toxee';

  @override
  String trayUnreadTooltip(int count) {
    return '未读：$count';
  }

  @override
  String get unknownErrorReason => '未知错误';

  @override
  String get notificationNoMessage => '（无附言）';

  @override
  String notificationGroupedSummary(int count, String name) {
    return '来自 $name 的 $count 条新消息';
  }

  @override
  String pairingConnectTimedOut(String endpoint) {
    return '未能及时连接到另一台设备（$endpoint）。请确认两台设备在同一网络中，尝试使用个人热点，或改用“导出 → 导入”文件的方式。';
  }

  @override
  String get groupInviteTitle => '群邀请';

  @override
  String groupInviteBody(String inviter, String group) {
    return '$inviter 邀请你加入群聊“$group”。';
  }

  @override
  String groupInviteBodyUnnamed(String inviter) {
    return '$inviter 邀请你加入一个群聊。';
  }

  @override
  String get groupInviteDecline => '拒绝';

  @override
  String get groupInviteLater => '稍后';

  @override
  String get groupInviteAcceptFailed => '无法加入。邀请人可能不在线，请等对方上线后重试。';

  @override
  String get alreadyInGroup => '你已在该群聊中';

  @override
  String get groupNameTooLong => '群名称过长';

  @override
  String get leaveGroupFailed => '退出群聊失败，请重试。';

  @override
  String get groupPassword => '群密码（可选）';

  @override
  String get groupPasswordTooLong => '群密码最多 32 字节';

  @override
  String get groupJoinRefusedPassword => '该群需要密码，或密码不正确。';

  @override
  String get groupJoinRefusedFull => '该群已满员。';

  @override
  String get groupJoinRefusedUnknown => '该群拒绝了你的加入。';

  @override
  String get groupJoinEnterPassword => '输入密码';

  @override
  String get groupPasswordRequired => '请输入群密码';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

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
  String get general => '通用';

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
  String get joinQueued => '当前离线 — 入群申请将在重新连接后发送';

  @override
  String get offlineBanner => '当前离线 — 群组操作将在重新连接后排队处理。';

  @override
  String get groupType => '群组类型';

  @override
  String get publicGroup => '公开';

  @override
  String get privateGroup => '私密';

  @override
  String get publicGroupHint => '公开群 — 在 DHT 上可被发现，知道群 ID 的人均可加入。';

  @override
  String get privateGroupHint => '私密群 — 仅限邀请加入，不在 DHT 上公告。';

  @override
  String get conferenceHint => '传统会议群 — 旧协议，没有角色或持久化。';

  @override
  String get searchHintBody => '搜索联系人、群组和消息';

  @override
  String get noResultsFoundHint => '试试更短的关键词或检查拼写';

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
  String get invalidLength => 'ID 长度不正确';

  @override
  String get invalidCharacters => '只能包含十六进制字符';

  @override
  String get paste => '粘贴';

  @override
  String get addContactHint => '请输入对方的 Tox 地址。';

  @override
  String get addFriendInvalidToxIdHint => 'Tox 地址必须是 76 位十六进制字符';

  @override
  String get verificationMessage => '验证信息';

  @override
  String get defaultFriendRequestMessage => '你好，我想添加你为好友。';

  @override
  String get friendRequestMessageTooLong => '好友请求消息不能超过 921 个字符';

  @override
  String get enterMessage => '请输入消息';

  @override
  String get noGroupMembers => '暂无成员';

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
  String get autoDownloadSizeLimitDesc =>
      '小于此大小的文件和所有图片将自动下载。大于此大小的文件需要手动点击下载按钮。';

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
  String get canOnlySelectTestedNode => '选择此节点前，请先成功发送引导请求';

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
  String get ircStatusDisconnected => '已断开';

  @override
  String get ircStatusConnecting => '连接中';

  @override
  String get ircStatusConnected => '已连接';

  @override
  String get ircStatusAuthenticating => '认证中';

  @override
  String get ircStatusReconnecting => '重连中';

  @override
  String get ircStatusError => '错误';

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
  String ircChannelAddedNotConnected(String channel) {
    return '频道 $channel 已添加，但无法建立 IRC 连接';
  }

  @override
  String get ircAppInstalledNoLibrary => 'IRC 应用已安装，但本设备不支持实时 IRC 连接';

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
  String get close => '关闭';

  @override
  String get nodeNotTestedWarning => '尚未测试此节点。';

  @override
  String get nodeTestFailedWarning => '此节点未响应，可能不可用。';

  @override
  String get nodeTestInconclusiveWarning => '无法从本设备检测该节点，因此对它是否可用一无所知。';

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
  String get nodeTestSuccess => '节点可达';

  @override
  String get nodeTestUdpUnavailable => '节点测试需要 UDP，本设备当前仅使用 TCP';

  @override
  String get nodeTestFailed => '节点不可达';

  @override
  String get nodeTestUnavailable => '本设备无法执行节点测试';

  @override
  String get failedToLoadBootstrapNodes => '加载引导节点失败';

  @override
  String get failedToStartBootstrapService => '启动引导服务失败';

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
  String get bootstrapServiceFound => '发现 Bootstrap 服务';

  @override
  String get noBootstrapService => '未发现 Bootstrap 服务';

  @override
  String get noServicesFound => '未找到服务';

  @override
  String get useAsBootstrapNode => '设为 Bootstrap 节点';

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
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '此账号已登录';

  @override
  String get unknownError => '未知错误';

  @override
  String get unknown => '未知';

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
  String get callSwitchCamera => '切换摄像头';

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
  String get callIncomingNotificationPermissionRequired =>
      '启用通知权限前，来电只能在 Toxee 应用内响铃。';

  @override
  String get callFailedGroupUnsupported => '暂不支持群组通话。';

  @override
  String get callFailedSignaling => '呼叫失败，请重试。';

  @override
  String get callFailedMediaChannel => '无法建立通话媒体通道。';

  @override
  String get callVideoUnsupportedPlatform => '当前平台暂不支持视频通话（无摄像头支持）。';

  @override
  String get callAudioInterrupted => '通话过程中音频输出发生变化或被中断。';

  @override
  String get callBusyInCall => '请先结束当前通话。';

  @override
  String get callBusyInConference => '请先退出语音会议，再发起或接听通话。';

  @override
  String get callBusyInOtherConference => '你已在另一个语音会议中，请先退出。';

  @override
  String get callPeerBusy => '对方正在通话中。';

  @override
  String get callConferenceMuteIncoming => '静音他人';

  @override
  String get callConferenceUnmuteIncoming => '收听他人';

  @override
  String get callConferenceListenOnly => '仅收听 — 麦克风不可用。';

  @override
  String get callCalling => '呼叫中...';

  @override
  String get callLeaving => '正在离开会议...';

  @override
  String callReceivedFrames(int count) {
    return '已接收 $count 帧';
  }

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
  String get passwordVisibility => '切换密码可见';

  @override
  String get nicknameHintExample => '例如：Alice';

  @override
  String get callAudioRouteSystem => '此平台音频输出由系统管理';

  @override
  String get copyFullToxId => '复制完整 ID';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get idLabel => 'ID：';

  @override
  String errorBannerLabel(String message) {
    return '错误：$message';
  }

  @override
  String searchResultContactSemantics(String name) {
    return '$name，联系人';
  }

  @override
  String searchResultGroupSemantics(String name) {
    return '$name，群组';
  }

  @override
  String searchResultMessageSemantics(String name) {
    return '$name，消息';
  }

  @override
  String searchResultConversationSemantics(String name) {
    return '$name，会话';
  }

  @override
  String get importNoFileSelected => '未选择文件';

  @override
  String get importCancelled => '已取消';

  @override
  String get importedAccountDefaultName => '已导入账号';

  @override
  String failedToImport(String error) {
    return '导入失败：$error';
  }

  @override
  String get selectConversationEmptyState => '选择一个会话开始聊天';

  @override
  String get newConversationTooltip => '新建会话';

  @override
  String get pinConversation => '置顶';

  @override
  String get unpinConversation => '取消置顶';

  @override
  String get markConversationAsRead => '标为已读';

  @override
  String get deleteConversationTitle => '删除会话？';

  @override
  String deleteConversationBody(String name) {
    return '将从聊天列表中移除“$name”。聊天记录仍保留在本地。';
  }

  @override
  String get runtimeForegroundTitle => 'Toxee 正在运行';

  @override
  String get runtimeForegroundBody => '保持连接，以便接收消息和通话。';

  @override
  String get runtimeForegroundSettingsLabel => '通知设置';

  @override
  String get runtimeForegroundCallTitle => '通话中';

  @override
  String get runtimeForegroundCallBody => 'Toxee 正在保持通话连接。';

  @override
  String runtimeForegroundCallBodyWithCaller(String name) {
    return '与 $name 通话中';
  }

  @override
  String get appTagline => '私密的点对点通讯工具';

  @override
  String get noBootstrapNodes => '没有引导节点';

  @override
  String get groupInviteTitle => '群邀请';

  @override
  String groupInviteBody(String inviter, String group) {
    return '$inviter 邀请你加入群聊“$group”。';
  }

  @override
  String groupInviteBodyUnnamed(String inviter) {
    return '$inviter 邀请你加入一个群聊。';
  }

  @override
  String get groupInviteDecline => '拒绝';

  @override
  String get groupInviteLater => '稍后';

  @override
  String get groupInviteAcceptFailed => '无法加入。邀请人可能不在线，请等对方上线后重试。';

  @override
  String get alreadyInGroup => '你已在该群聊中';

  @override
  String get groupNameTooLong => '群名称过长';

  @override
  String get leaveGroupFailed => '退出群聊失败，请重试。';

  @override
  String get groupPassword => '群密码（可选）';

  @override
  String get groupPasswordTooLong => '群密码最多 32 字节';

  @override
  String get groupJoinRefusedPassword => '该群需要密码，或密码不正确。';

  @override
  String get groupJoinRefusedFull => '该群已满员。';

  @override
  String get groupJoinRefusedUnknown => '该群拒绝了你的加入。';

  @override
  String get groupJoinEnterPassword => '输入密码';

  @override
  String get groupPasswordRequired => '请输入群密码';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

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
    return '$count 則訊息';
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
  String get general => '通用';

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
  String get joinQueued => '目前離線 — 入群申請將在重新連線後發送';

  @override
  String get offlineBanner => '目前離線 — 群組操作將在重新連線後排隊處理。';

  @override
  String get groupType => '群組類型';

  @override
  String get publicGroup => '公開';

  @override
  String get privateGroup => '私密';

  @override
  String get publicGroupHint => '公開群 — 在 DHT 上可被發現，知道群 ID 的人均可加入。';

  @override
  String get privateGroupHint => '私密群 — 僅限邀請加入，不在 DHT 上公告。';

  @override
  String get conferenceHint => '傳統會議群 — 舊協定，沒有角色或持久化。';

  @override
  String get searchHintBody => '搜尋聯絡人、群組和訊息';

  @override
  String get noResultsFoundHint => '試試更短的關鍵字或檢查拼寫';

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
  String get invalidLength => 'ID 長度不正確';

  @override
  String get invalidCharacters => '只能包含十六進位字元';

  @override
  String get paste => '貼上';

  @override
  String get addContactHint => '請輸入對方的 Tox 地址。';

  @override
  String get addFriendInvalidToxIdHint => 'Tox 地址必須是 76 位十六進位字元';

  @override
  String get verificationMessage => '驗證訊息';

  @override
  String get defaultFriendRequestMessage => '你好，我想添加你為好友。';

  @override
  String get friendRequestMessageTooLong => '好友請求訊息不能超過 921 個字元';

  @override
  String get enterMessage => '請輸入訊息';

  @override
  String get noGroupMembers => '暫無成員';

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
  String get autoDownloadSizeLimitDesc =>
      '小於此大小的文件和所有圖片將自動下載。大於此大小的文件需要手動點擊下載按鈕。';

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
  String get canOnlySelectTestedNode => '選擇此節點前，請先成功傳送引導請求';

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
  String get ircStatusDisconnected => '已斷開';

  @override
  String get ircStatusConnecting => '連線中';

  @override
  String get ircStatusConnected => '已連線';

  @override
  String get ircStatusAuthenticating => '認證中';

  @override
  String get ircStatusReconnecting => '重新連線中';

  @override
  String get ircStatusError => '錯誤';

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
  String ircChannelAddedNotConnected(String channel) {
    return '頻道 $channel 已添加，但無法建立 IRC 連線';
  }

  @override
  String get ircAppInstalledNoLibrary => 'IRC 應用已安裝，但本裝置不支援即時 IRC 連線';

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
  String get ircChannelDesc => '輸入IRC頻道名稱（例如：#channel）。將為此頻道建立一個Tox群組。';

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
  String get nodeNotTestedWarning => '尚未測試此節點。';

  @override
  String get nodeTestFailedWarning => '此節點未回應，可能無法使用。';

  @override
  String get nodeTestInconclusiveWarning => '無法從本裝置檢測該節點，因此對它是否可用一無所知。';

  @override
  String get nicknameTooLong => '暱稱過長';

  @override
  String get nicknameCannotBeEmpty => '暱稱不能為空';

  @override
  String get statusMessageTooLong => '簽名過長';

  @override
  String get passwordStrengthWeak => '弱';

  @override
  String get passwordStrengthFair => '普通';

  @override
  String get passwordStrengthGood => '良好';

  @override
  String get passwordStrengthStrong => '強';

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
  String get nodeTestSuccess => '節點可連線';

  @override
  String get nodeTestUdpUnavailable => '節點測試需要 UDP，本裝置目前僅使用 TCP';

  @override
  String get nodeTestFailed => '節點無法連線';

  @override
  String get nodeTestUnavailable => '本裝置無法執行節點測試';

  @override
  String get failedToLoadBootstrapNodes => '載入Bootstrap 節點失敗';

  @override
  String get failedToStartBootstrapService => '啟動引導服務失敗';

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
  String get exportOptionProfileTox => '設定檔（.tox）';

  @override
  String get exportOptionProfileToxSubtitle => '相容 qTox，僅含設定檔';

  @override
  String get exportOptionFullBackup => '完整備份（.zip）';

  @override
  String get exportOptionFullBackupSubtitle => '設定檔 + 聊天記錄 + 設定';

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
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String minutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '此帳號已登入';

  @override
  String get upgradeRequiredTitle => '請更新應用程式';

  @override
  String upgradeRequiredMessage(int storedVersion, int currentVersion) {
    return '你的資料是由較新版本的應用程式儲存的（資料版本：$storedVersion）。此版本最高僅支援 $currentVersion。請安裝最新版本後再繼續。';
  }

  @override
  String get upgradeAppTitle => 'toxee';

  @override
  String get hide => '隱藏';

  @override
  String get pressBackAgainToExit => '再按一次返回鍵即可退出';

  @override
  String get startupFailed => '啟動失敗';

  @override
  String get unknownError => '未知錯誤';

  @override
  String get goToLogin => '前往登入';

  @override
  String get conference => '會議群';

  @override
  String get defaultJoinRequestMessage => '你好，請邀請我加入這個群組';

  @override
  String get userNotFoundPleaseRegister => '找不到此用戶，請先註冊。';

  @override
  String get nicknameDoesNotMatch => '暱稱不符。請使用註冊時的暱稱，或註冊新帳號。';

  @override
  String get accountAlreadyExistsPleaseLogin => '帳號已存在。請直接登入，或改用其他暱稱。';

  @override
  String get profileNotFoundImportRestore => '找不到此帳號的設定檔。請匯入或還原備份。';

  @override
  String get failedToInitializeTIMManager => 'TIMManager SDK 初始化失敗';

  @override
  String get failedToGetToxId => '取得 Tox ID 失敗';

  @override
  String get failedToGenerateToxId => '產生 Tox ID 失敗';

  @override
  String get registrationCouldNotCreateProfile => '註冊時無法建立唯一的設定檔，請再試一次。';

  @override
  String get importedAccount => '匯入的帳號';

  @override
  String get unknown => '未知';

  @override
  String sendingToGroupsNotSupported(String label) {
    return '目前尚不支援向群組發送$label';
  }

  @override
  String noLabelSelected(String label) {
    return '未選擇$label';
  }

  @override
  String searchSummary(int contacts, int groups, int messages) {
    return '找到 $contacts 個聯絡人、$groups 個群組、$messages 則訊息線索';
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
  String get callSwitchCamera => '切換相機';

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
  String get callIncomingNotificationPermissionRequired =>
      '啟用通知權限前，來電只能在 Toxee 應用內響鈴。';

  @override
  String get callFailedGroupUnsupported => '暫不支援群組通話。';

  @override
  String get callFailedSignaling => '呼叫失敗，請重試。';

  @override
  String get callFailedMediaChannel => '無法建立通話媒體通道。';

  @override
  String get callVideoUnsupportedPlatform => '目前平台暫不支援視訊通話（無攝影機支援）。';

  @override
  String get callAudioInterrupted => '通話過程中音訊輸出發生變化或被中斷。';

  @override
  String get callBusyInCall => '請先結束目前的通話。';

  @override
  String get callBusyInConference => '請先退出語音會議，再撥打或接聽通話。';

  @override
  String get callBusyInOtherConference => '你已在另一個語音會議中，請先退出。';

  @override
  String get callPeerBusy => '對方正在通話中。';

  @override
  String get callConferenceMuteIncoming => '靜音他人';

  @override
  String get callConferenceUnmuteIncoming => '收聽他人';

  @override
  String get callConferenceListenOnly => '僅收聽 — 麥克風無法使用。';

  @override
  String get callCalling => '撥打中...';

  @override
  String get callLeaving => '正在離開會議...';

  @override
  String callReceivedFrames(int count) {
    return '已接收 $count 幀';
  }

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

  @override
  String unreadMessagesSemantics(int count) {
    return '$count 則未讀訊息';
  }

  @override
  String matchingMessagesSemantics(int count) {
    return '$count 則相符的訊息';
  }

  @override
  String get statusOnline => '在線';

  @override
  String get statusOffline => '離線';

  @override
  String get noIrcChannels => '沒有 IRC 頻道';

  @override
  String get joinChannelToGetStarted => '加入頻道即可開始';

  @override
  String ircUsersCount(int count) {
    return '用戶（$count）';
  }

  @override
  String get ircNoUsers => '沒有用戶';

  @override
  String get passwordVisibility => '切換密碼可見';

  @override
  String get nicknameHintExample => '例如：Alice';

  @override
  String get callAudioRouteSystem => '此平台音訊輸出由系統管理';

  @override
  String get copyFullToxId => '複製完整 ID';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get idLabel => 'ID：';

  @override
  String errorBannerLabel(String message) {
    return '錯誤：$message';
  }

  @override
  String searchResultContactSemantics(String name) {
    return '$name，聯絡人';
  }

  @override
  String searchResultGroupSemantics(String name) {
    return '$name，群組';
  }

  @override
  String searchResultMessageSemantics(String name) {
    return '$name，訊息';
  }

  @override
  String searchResultConversationSemantics(String name) {
    return '$name，會話';
  }

  @override
  String get importNoFileSelected => '未選擇檔案';

  @override
  String get importCancelled => '已取消';

  @override
  String get recoveryBlockedTitle => '帳號復原未完成';

  @override
  String get recoveryBlockedBody =>
      'toxee 發現一項未完成的帳號還原或刪除操作，但無法讀取其記錄，因此沒有開啟任何帳號——繼續操作可能會破壞資料。\n\n你的帳號及其設定檔仍保留在此裝置上。請勿重新註冊，也不要清除應用程式資料，否則資料將永久遺失。請回報下方的詳細資訊，以便進行修復。';

  @override
  String get secureStorageUnavailable =>
      '安全儲存區目前無法使用，toxee 無法驗證此帳號的密碼。這通常是暫時性的問題——請再試一次，或解鎖裝置的鑰匙圈。';

  @override
  String get recoverLegacyDataAction => '從舊版本復原資料';

  @override
  String get recoverLegacyDataConfirm =>
      '此裝置仍保留 toxee 支援多帳號之前的聊天記錄、待發送訊息和聯絡人頭像。要將它們加入你目前登入的帳號嗎？\n\n請僅在這些資料屬於你時才執行此操作。這些資料只能被一個帳號認領一次。\n\n你將被登出，以便在下次登入時合併資料。';

  @override
  String get recoverLegacyDataClaimed =>
      '此帳號將接管舊資料。請登出後重新登入以完成合併——在登入時合併，才能確保你目前的聊天記錄和待發送訊息完整保留。';

  @override
  String get recoverLegacyDataDone => '舊資料已加入此帳號。';

  @override
  String get recoverLegacyDataUnavailable => '無法認領這些資料——它們可能已屬於此裝置上的其他帳號。';

  @override
  String get accountRegistryUnreadable =>
      '無法讀取已儲存的帳號。它們的設定檔仍保留在此裝置上——請勿重新註冊；請回報此問題，以便修復帳號列表。';

  @override
  String get importedAccountDefaultName => '已匯入帳號';

  @override
  String failedToImport(String error) {
    return '匯入失敗：$error';
  }

  @override
  String get selectConversationEmptyState => '選擇一個會話開始聊天';

  @override
  String get newConversationTooltip => '新建會話';

  @override
  String get pinConversation => '置頂';

  @override
  String get unpinConversation => '取消置頂';

  @override
  String get markConversationAsRead => '標為已讀';

  @override
  String get deleteConversationTitle => '刪除會話？';

  @override
  String deleteConversationBody(String name) {
    return '將從聊天清單中移除「$name」。聊天記錄仍保留在本機。';
  }

  @override
  String get firstRunBackupWizardTitle => '儲存你的帳號檔案';

  @override
  String get firstRunBackupWizardBody =>
      '你的帳號只存在於這台裝置上。請將 .tox 檔案儲存到安全的地方（雲端硬碟、密碼管理器、USB 隨身碟）。若沒有備份，一旦遺失這台裝置，帳號和所有聯絡人都將永久遺失。';

  @override
  String get firstRunBackupWizardExportNow => '立即匯出';

  @override
  String get firstRunBackupWizardLater => '稍後再說';

  @override
  String get firstRunBackupWizardDismissTitle => '略過備份？';

  @override
  String get firstRunBackupWizardDismissBody => '如果遺失此裝置，你將失去帳號和所有聯絡人，且無法復原。';

  @override
  String get firstRunBackupWizardDismissConfirm => '我了解，繼續';

  @override
  String firstRunBackupWizardExportFailed(String error) {
    return '無法儲存帳號檔案：$error';
  }

  @override
  String get restoreFromToxFile => '從 .tox 檔案還原';

  @override
  String restoreFromToxFileSuccess(String nickname) {
    return '已還原帳號：$nickname';
  }

  @override
  String get restoreFromToxFileInvalidFile => '此檔案不是有效的 Tox 設定檔。';

  @override
  String get pairDeviceHostTitle => '配對另一台裝置';

  @override
  String get pairDeviceClientTitle => '與另一台裝置配對';

  @override
  String get pairingHostInstructions =>
      '在另一台裝置上開啟 toxee，選擇「與另一台裝置配對」，然後掃描此 QR 碼。';

  @override
  String get pairingClientScanInstructions => '將相機對準另一台裝置上顯示的 QR 碼。';

  @override
  String get pairingClientPasteInstructions =>
      '此裝置不支援相機掃描。請將另一台裝置上顯示的配對網址貼到下方。';

  @override
  String get pairingPasteUrlLabel => '配對網址';

  @override
  String get pairingConnectButton => '連線';

  @override
  String get pairingWaitingForPeer => '正在等待另一台裝置連線…';

  @override
  String get pairingVerifyCodeHeader => '請確認兩台裝置顯示的驗證碼相同';

  @override
  String get pairingVerifyCodeInstructions =>
      '如果驗證碼與另一台裝置上顯示的相同，請點擊下方按鈕。若不相同，請取消——可能有人正在攔截連線。';

  @override
  String get pairingCodesMatch => '驗證碼相同';

  @override
  String get pairingHostCompleted => '帳號已發送，另一台裝置現在已擁有你的帳號。';

  @override
  String get pairingClientCompleted => '帳號已接收，配對完成。';

  @override
  String get pairingCancelled => '已取消配對。';

  @override
  String get pairingTimeout => '配對逾時，請再試一次。';

  @override
  String pairingNetworkError(String detail) {
    return '配對時發生網路錯誤：$detail';
  }

  @override
  String pairingProtocolError(String detail) {
    return '配對交握失敗：$detail';
  }

  @override
  String pairingInvalidUrl(String detail) {
    return '此 QR 碼不是有效的配對邀請：$detail';
  }

  @override
  String get pairingDecryptFailed => '無法解密收到的設定檔。配對過程可能遭到竄改——請在可信任的網路上再試一次。';

  @override
  String get pairingNoLanInterface => '未偵測到區域網路。請連接 Wi-Fi 或乙太網路後再試一次。';

  @override
  String get pairThisAccountToAnotherDevice => '將此帳號配對到另一台裝置';

  @override
  String get pairWithAnotherDevice => '與已登入我帳號的另一台裝置配對';

  @override
  String get devicesSectionTitle => '裝置';

  @override
  String get done => '完成';

  @override
  String get runtimeForegroundTitle => 'Toxee 正在執行';

  @override
  String get runtimeForegroundBody => '保持連線，以便接收訊息和通話。';

  @override
  String get runtimeForegroundSettingsLabel => '通知設定';

  @override
  String get runtimeForegroundCallTitle => '通話中';

  @override
  String get runtimeForegroundCallBody => 'Toxee 正在維持通話連線。';

  @override
  String runtimeForegroundCallBodyWithCaller(String name) {
    return '與 $name 通話中';
  }

  @override
  String get appTagline => '私密的點對點通訊工具';

  @override
  String get noBootstrapNodes => '沒有Bootstrap 節點';

  @override
  String get importMayHaveCompleted => '無法復原此次匯入，因此這個帳號可能仍然存在。再次匯入前，請先檢查帳號列表。';

  @override
  String get importBlockedByPendingImport =>
      '先前有一次帳號匯入被中斷，尚未清理完成。請重新啟動 toxee 以完成復原，然後再匯入。';

  @override
  String get friendRequestQueued => '目前離線 — 請求已排入佇列，將在重新連線後發送';

  @override
  String get cannotAddSelfAsFriend => '不能將自己新增為好友';

  @override
  String get friendRequestAlreadySent => '本次已發送過好友請求';

  @override
  String get alreadyInFriendList => '此用戶已在你的好友列表中';

  @override
  String get addFriendOfflineBanner => '目前離線 — 好友請求將排入佇列，並在重新連線後自動發送。';

  @override
  String get scanQr => '掃描 QR 碼';

  @override
  String get sendingInProgress => '發送中...';

  @override
  String get firewallHintWindows => '在 Windows 上，防火牆可能會封鎖連入連線；如出現提示，請允許此應用程式。';

  @override
  String get firewallHintLinux => '在 Linux 上，網路操作可能需要相應的權限或防火牆規則。';

  @override
  String get nodePublicKeyHint => '公鑰（十六進位）';

  @override
  String get failedToAddBootstrapNode => '新增 Bootstrap 節點失敗';

  @override
  String get couldNotRemovePassword => '無法移除密碼';

  @override
  String get couldNotSavePassword => '無法儲存密碼';

  @override
  String mediaSent(String label) {
    return '$label已發送';
  }

  @override
  String get dhtUnreachableUsingFallback =>
      '無法連上 DHT。正在使用備用 Bootstrap 節點——你的網路可能封鎖了 UDP，或節點已離線。';

  @override
  String get dhtUnreachableTimeout => '30 秒後仍無法連上 DHT，請檢查網路連線。';

  @override
  String chatSdkInitFailed(String error) {
    return '聊天 SDK 初始化失敗：$error';
  }

  @override
  String messageTooLongMaxBytes(int maxBytes) {
    return '訊息過長（上限 $maxBytes 位元組）';
  }

  @override
  String get friendOfflineWillRetry => '好友不在線 — 將在對方重新連線後重試';

  @override
  String get groupFileTransferUnsupported => '群聊不支援檔案傳輸';

  @override
  String fileSendFailed(String error) {
    return '檔案發送失敗：$error';
  }

  @override
  String errorWithCode(int code) {
    return '錯誤碼 $code';
  }

  @override
  String pairingLanUnreachable(String detail) {
    return '兩台裝置在此網路上無法互相連線。請改用個人熱點，或改用「匯出 → 匯入」透過檔案轉移。（$detail）';
  }

  @override
  String get notificationNewFriendRequest => '新的好友請求';

  @override
  String notificationFriendRequestFrom(String name) {
    return '好友請求：$name';
  }

  @override
  String get notificationMissedCall => '未接來電';

  @override
  String get notificationMissedVideoCall => '未接視訊通話';

  @override
  String get notificationIncomingCall => '來電';

  @override
  String get notificationIncomingVideoCall => '視訊來電';

  @override
  String get notificationUnknownCaller => 'Toxee 聯絡人';

  @override
  String get notificationNewMessage => '新訊息';

  @override
  String get previewImage => '[圖片]';

  @override
  String get previewVideo => '[影片]';

  @override
  String get previewVoice => '[語音]';

  @override
  String previewVoiceWithDuration(int seconds) {
    return '[語音 $seconds 秒]';
  }

  @override
  String get previewFile => '[檔案]';

  @override
  String previewFileWithName(String name) {
    return '[檔案] $name';
  }

  @override
  String get previewSticker => '[貼圖]';

  @override
  String get previewLocation => '[位置]';

  @override
  String get previewCustomMessage => '[自訂訊息]';

  @override
  String get previewGroupEvent => '[群組事件]';

  @override
  String get previewMessage => '[訊息]';

  @override
  String get channelMessagesName => '訊息';

  @override
  String get channelMessagesDescription => '收到 Tox 聯絡人傳來的新訊息時通知。';

  @override
  String get channelFriendRequestsName => '好友請求';

  @override
  String get channelFriendRequestsDescription => '有人向你發送好友請求時通知。';

  @override
  String get channelGroupInvitesName => '群組邀請';

  @override
  String get channelGroupInvitesDescription => '有人邀請你加入群組時通知。';

  @override
  String get channelMissedCallsName => '未接來電';

  @override
  String get channelMissedCallsDescription => '來電未能接通或未接聽時通知。';

  @override
  String get channelIncomingCallsName => '來電';

  @override
  String get channelIncomingCallsDescription => 'Toxee 來電的全螢幕提醒。';

  @override
  String get notificationOpenAction => '開啟 Toxee';

  @override
  String trayUnreadTooltip(int count) {
    return '未讀：$count';
  }

  @override
  String get unknownErrorReason => '未知錯誤';

  @override
  String get notificationNoMessage => '（無附言）';

  @override
  String notificationGroupedSummary(int count, String name) {
    return '來自 $name 的 $count 則新訊息';
  }

  @override
  String pairingConnectTimedOut(String endpoint) {
    return '無法及時連線到另一台裝置（$endpoint）。請確認兩台裝置位於同一網路，改用個人熱點，或改用「匯出 → 匯入」透過檔案轉移。';
  }

  @override
  String get groupInviteTitle => '群聊邀請';

  @override
  String groupInviteBody(String inviter, String group) {
    return '$inviter 邀請你加入群聊「$group」。';
  }

  @override
  String groupInviteBodyUnnamed(String inviter) {
    return '$inviter 邀請你加入一個群聊。';
  }

  @override
  String get groupInviteDecline => '拒絕';

  @override
  String get groupInviteLater => '稍後';

  @override
  String get groupInviteAcceptFailed => '無法加入。邀請人可能不在線上，請等對方上線後再試。';

  @override
  String get alreadyInGroup => '你已在該群聊中';

  @override
  String get groupNameTooLong => '群名稱過長';

  @override
  String get leaveGroupFailed => '退出群聊失敗，請重試。';

  @override
  String get groupPassword => '群組密碼（選填）';

  @override
  String get groupPasswordTooLong => '群組密碼最多 32 位元組';

  @override
  String get groupJoinRefusedPassword => '此群組需要密碼，或密碼不正確。';

  @override
  String get groupJoinRefusedFull => '此群組已滿員。';

  @override
  String get groupJoinRefusedUnknown => '此群組拒絕了你的加入。';

  @override
  String get groupJoinEnterPassword => '輸入密碼';

  @override
  String get groupPasswordRequired => '請輸入群組密碼';
}
