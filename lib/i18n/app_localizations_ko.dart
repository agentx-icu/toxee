// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get chats => '채팅';

  @override
  String get contacts => '연락처';

  @override
  String get requests => '요청';

  @override
  String get groups => '그룹';

  @override
  String get settings => '설정';

  @override
  String get searchConversations => '닉네임 / 그룹 / 메시지로 검색';

  @override
  String get searchContacts => '연락처 검색';

  @override
  String get searchResults => '검색 결과';

  @override
  String get enterKeywordToSearch => '키워드를 입력하여 검색';

  @override
  String get noResultsFound => '결과를 찾을 수 없습니다';

  @override
  String get searchSectionMessages => '메시지';

  @override
  String get searchSectionConversations => '대화';

  @override
  String get searchHint => '검색...';

  @override
  String messageCount(int count) {
    return '$count개의 메시지';
  }

  @override
  String get searchChatHistory => '채팅 기록 검색';

  @override
  String searchResultsCount(int count, String keyword) {
    return '\"$keyword\"에 대한 결과가 $count개 있습니다';
  }

  @override
  String get openChat => '채팅 열기';

  @override
  String relatedChats(int count) {
    return '관련 메시지 $count개';
  }

  @override
  String get newItem => '새로 만들기';

  @override
  String get addFriend => '친구 추가';

  @override
  String get createGroup => '그룹 만들기';

  @override
  String get friendUserId => '친구 사용자 ID (16진수)';

  @override
  String get groupNameOptional => '그룹 이름 (선택 사항)';

  @override
  String get typeMessage => '메시지 입력';

  @override
  String get messageToGroup => '그룹에 메시지';

  @override
  String get selfId => '내 ID';

  @override
  String get appearance => '모양';

  @override
  String get light => '라이트';

  @override
  String get dark => '다크';

  @override
  String get language => '언어';

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
  String get profile => '프로필';

  @override
  String get nickname => '닉네임';

  @override
  String get statusMessage => '상태 메시지';

  @override
  String get saveProfile => '프로필 저장';

  @override
  String get ok => '확인';

  @override
  String get cancel => '취소';

  @override
  String get group => '그룹';

  @override
  String get file => '파일';

  @override
  String get audio => '오디오';

  @override
  String get friendRequestSent => '친구 요청을 보냈습니다';

  @override
  String get joinGroup => '그룹에 참가';

  @override
  String get groupId => '그룹 ID';

  @override
  String get createAndOpen => '만들고 열기';

  @override
  String get joinAndOpen => '참가하고 열기';

  @override
  String get knownGroups => '알려진 그룹';

  @override
  String get selectAChat => '채팅 선택';

  @override
  String get photo => '사진';

  @override
  String get video => '비디오';

  @override
  String get autoAcceptFriendRequests => '친구 요청 자동 수락';

  @override
  String get autoAcceptFriendRequestsDesc => '들어오는 친구 요청을 자동으로 수락';

  @override
  String get autoAcceptGroupInvites => '그룹 초대 자동 수락';

  @override
  String get autoAcceptGroupInvitesDesc => '들어오는 그룹 초대를 자동으로 수락';

  @override
  String get bootstrapNodes => 'Bootstrap 노드';

  @override
  String get currentNode => '현재 사용 중인 노드';

  @override
  String get viewAndTestNodes => '노드 보기 및 테스트';

  @override
  String get currentlyOnlineNoReconnect => '현재 온라인 상태입니다. 재연결할 필요가 없습니다';

  @override
  String get addOrCreateGroup => '추가 / 그룹 만들기';

  @override
  String get joinGroupById => 'ID로 그룹에 참가';

  @override
  String get enterGroupId => '그룹 ID를 입력하세요';

  @override
  String get requestMessage => '요청 메시지';

  @override
  String get groupAlias => '로컬 그룹 이름 (선택 사항)';

  @override
  String get joinAction => '참가 요청 보내기';

  @override
  String get joinSuccess => '참가 요청을 보냈습니다';

  @override
  String get joinFailed => '그룹 참가에 실패했습니다';

  @override
  String get groupName => '그룹 이름';

  @override
  String get enterGroupName => '그룹 이름을 입력하세요';

  @override
  String get createAction => '그룹 만들기';

  @override
  String get createSuccess => '그룹을 만들었습니다';

  @override
  String get createFailed => '그룹 만들기에 실패했습니다';

  @override
  String get createdGroupId => '새 그룹 ID';

  @override
  String get copyId => 'ID 복사';

  @override
  String get copied => '클립보드에 복사했습니다';

  @override
  String get addFailed => '추가에 실패했습니다';

  @override
  String get enterId => 'Tox ID를 입력하세요';

  @override
  String get invalidLength => 'ID는 64자 또는 76자의 16진수 문자여야 합니다';

  @override
  String get invalidCharacters => '16진수 문자만 포함할 수 있습니다';

  @override
  String get paste => '붙여넣기';

  @override
  String get addContactHint => '친구의 Tox ID (64자 또는 76자의 16진수 문자)를 입력하세요.';

  @override
  String get verificationMessage => '확인 메시지';

  @override
  String get defaultFriendRequestMessage => '안녕하세요, 친구로 추가하고 싶습니다.';

  @override
  String get friendRequestMessageTooLong => '친구 요청 메시지는 921자를 초과할 수 없습니다';

  @override
  String get enterMessage => '메시지를 입력하세요';

  @override
  String get noGroupMembers => '아직 멤버가 없습니다';

  @override
  String get autoAcceptedNewFriendRequest => '새 친구 요청을 자동으로 수락했습니다';

  @override
  String get scanQrCodeToAddContact => 'QR 코드를 스캔하여 연락처에 추가';

  @override
  String get generateCard => '명함 생성';

  @override
  String get customCardText => '사용자 정의 명함 텍스트';

  @override
  String get userId => '사용자 ID';

  @override
  String get saveImage => '이미지 저장';

  @override
  String get copy => '복사';

  @override
  String get fileCopiedSuccessfully => '파일을 복사했습니다';

  @override
  String get idCopiedToClipboard => 'ID를 클립보드에 복사했습니다';

  @override
  String get establishingEncryptedChannel => '암호화 채널 설정 중...';

  @override
  String get checkingUserInfo => '사용자 정보 확인 중...';

  @override
  String get initializingService => '서비스 초기화 중...';

  @override
  String get loggingIn => '로그인 중...';

  @override
  String get initializingSDK => 'SDK 초기화 중...';

  @override
  String get updatingProfile => '프로필 업데이트 중...';

  @override
  String get initializationCompleted => '초기화 완료!';

  @override
  String get loadingFriends => '친구 정보 로딩 중...';

  @override
  String get inProgress => '진행 중';

  @override
  String get completed => '완료';

  @override
  String get personalCard => '개인 명함';

  @override
  String get appTitle => 'toxee';

  @override
  String get startChat => '채팅 시작';

  @override
  String get pasteServerUserId => '서버 사용자 ID를 여기에 붙여넣기';

  @override
  String get groupProfile => '그룹 프로필';

  @override
  String get invalidGroupId => '잘못된 그룹 ID';

  @override
  String maintainer(String maintainer) {
    return '유지 관리자: $maintainer';
  }

  @override
  String get success => '성공';

  @override
  String get failed => '실패';

  @override
  String error(String error) {
    return '오류: $error';
  }

  @override
  String get saved => '저장됨';

  @override
  String failedToSave(String error) {
    return '저장 실패: $error';
  }

  @override
  String copyFailed(String error) {
    return '복사 실패: $error';
  }

  @override
  String failedToUpdateAvatar(String error) {
    return '아바타 업데이트 실패: $error';
  }

  @override
  String get failedToLoadQr => 'QR 코드 로드 실패';

  @override
  String get helloFromToxee => 'toxee로부터의 인사';

  @override
  String attachFailed(String error) {
    return '첨부 실패: $error';
  }

  @override
  String get autoFriendRequestFromToxee => 'toxee로부터의 자동 친구 요청';

  @override
  String get reconnect => '재연결';

  @override
  String get reconnectConfirmMessage => '선택한 Bootstrap 노드를 사용하여 재연결합니다. 계속하시겠습니까?';

  @override
  String get reconnectedWaiting => '다시 로그인했습니다. 연결 대기 중...';

  @override
  String get reconnectWithThisNode => '이 노드로 재연결';

  @override
  String get friendOfflineCannotSendFile => '친구가 오프라인입니다. 파일을 보낼 수 없습니다. 온라인 상태가 될 때까지 기다려주세요.';

  @override
  String get friendOfflineSendCardFailed => '친구가 오프라인입니다. 명함 전송 실패';

  @override
  String get friendOfflineSendImageFailed => '친구가 오프라인입니다. 이미지 전송 실패';

  @override
  String get friendOfflineSendVideoFailed => '친구가 오프라인입니다. 비디오 전송 실패';

  @override
  String get friendOfflineSendFileFailed => '친구가 오프라인입니다. 파일 전송 실패';

  @override
  String get userNotInFriendList => '이 사용자는 친구 목록에 없습니다.';

  @override
  String sendFailed(String error) {
    return '전송 실패: $error';
  }

  @override
  String get myId => '내 ID';

  @override
  String get sendPersonalCardToGroup => '개인 명함을 그룹에 보내기';

  @override
  String get personalCardSent => '개인 명함을 보냈습니다';

  @override
  String get sentPersonalCardToGroup => '그룹에 개인 명함을 보냈습니다';

  @override
  String get bootstrapNodesTitle => 'Bootstrap 노드';

  @override
  String get refresh => '새로고침';

  @override
  String get retry => '다시 시도';

  @override
  String lastPing(String seconds) {
    return '마지막 ping: $seconds초 전';
  }

  @override
  String get testNode => '노드 테스트';

  @override
  String get deleteAccount => '계정 삭제';

  @override
  String get deleteAccountConfirmMessage => '계정과 모든 데이터가 영구적으로 삭제되며 복구할 수 없습니다. 신중하게 진행하세요.';

  @override
  String get delete => '삭제';

  @override
  String get deleteAccountEnterPasswordToConfirm => '삭제를 확인하려면 현재 계정 비밀번호를 입력하세요.';

  @override
  String get deleteAccountTypeWordToConfirm => '삭제를 확인하려면 아래에 표시된 영어 단어를 정확히 입력하세요.';

  @override
  String deleteAccountConfirmWordPrompt(String word) {
    return '확인을 위해 아래 상자에 다음 단어를 입력하세요: $word';
  }

  @override
  String get deleteAccountWrongWord => '입력한 단어가 올바르지 않습니다.';

  @override
  String get applications => '앱';

  @override
  String get applicationsComingSoon => '더 많은 앱이 곧 출시됩니다...';

  @override
  String get notificationSound => '알림 소리';

  @override
  String get notificationSoundDesc => '새 메시지, 친구 요청 및 그룹 요청 시 소리 재생';

  @override
  String get downloadsDirectory => '다운로드 디렉토리';

  @override
  String get selectDownloadsDirectory => '다운로드 디렉토리 선택';

  @override
  String get changeDownloadsDirectory => '다운로드 디렉토리 변경';

  @override
  String get downloadsDirectoryDesc => '파일 다운로드의 기본 디렉토리를 설정합니다. 수신한 파일, 오디오 및 비디오는 이 디렉토리에 저장됩니다.';

  @override
  String get downloadsDirectorySet => '다운로드 디렉토리가 설정되었습니다';

  @override
  String get downloadsDirectoryReset => '다운로드 디렉토리가 기본값으로 재설정되었습니다';

  @override
  String get failedToSelectDirectory => '디렉토리 선택 실패';

  @override
  String get reset => '재설정';

  @override
  String get autoDownloadSizeLimit => '자동 다운로드 크기 제한';

  @override
  String get sizeLimitInMB => '크기 제한 (MB)';

  @override
  String get autoDownloadSizeLimitDesc => '이 크기보다 작은 파일과 모든 이미지는 자동으로 다운로드됩니다. 이 크기보다 큰 파일은 수동으로 다운로드 버튼을 클릭해야 합니다.';

  @override
  String get autoDownloadSizeLimitSet => '자동 다운로드 크기 제한이 설정되었습니다';

  @override
  String get invalidSizeLimit => '유효하지 않은 크기 제한입니다. 1-10000 사이의 숫자를 입력하세요';

  @override
  String get save => '저장';

  @override
  String get routeSelection => '경로 선택';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get canOnlySelectOnlineNode => '온라인 노드만 선택할 수 있습니다';

  @override
  String get canOnlySelectTestedNode => '테스트에 성공한 노드만 선택할 수 있습니다. 먼저 노드를 테스트하세요';

  @override
  String get switchNode => '노드 전환';

  @override
  String switchNodeConfirm(String node) {
    return '노드 $node로 전환하시겠습니까? 전환 후 재연결이 필요합니다.';
  }

  @override
  String get nodeSwitched => '노드가 전환되었습니다. 재연결 중...';

  @override
  String get selectThisNode => '이 노드 선택';

  @override
  String nodeSwitchFailed(String error) {
    return '노드 전환 실패: $error';
  }

  @override
  String get ircChannelApp => 'IRC 채널';

  @override
  String get ircChannelAppDesc => 'IRC 채널을 Tox 그룹에 연결하여 메시지 동기화';

  @override
  String get install => '설치';

  @override
  String get uninstall => '제거';

  @override
  String get ircAppInstalled => 'IRC 채널 앱이 설치되었습니다';

  @override
  String get ircAppUninstalled => 'IRC 채널 앱이 제거되었습니다';

  @override
  String get uninstallIrcApp => 'IRC 채널 앱 제거';

  @override
  String get uninstallIrcAppConfirm => 'IRC 채널 앱을 제거하시겠습니까? 모든 IRC 채널이 제거되고 모든 IRC 그룹에서 나가게 됩니다.';

  @override
  String get addIrcChannel => '채널 추가';

  @override
  String get ircChannels => 'IRC 채널';

  @override
  String get ircServerConfig => 'IRC 서버 설정';

  @override
  String get ircServer => '서버';

  @override
  String get ircPort => '포트';

  @override
  String get ircUseSasl => 'SASL 인증 사용';

  @override
  String get ircUseSaslDesc => 'SASL 인증에 Tox 공개 키 사용 (NickServ 등록 필요)';

  @override
  String get ircServerRequired => 'IRC 서버 주소는 필수입니다';

  @override
  String get ircConfigSaved => 'IRC 설정이 저장되었습니다';

  @override
  String ircChannelAdded(String channel) {
    return 'IRC 채널이 추가되었습니다: $channel';
  }

  @override
  String get ircChannelAddFailed => 'IRC 채널 추가 실패';

  @override
  String ircChannelRemoved(String channel) {
    return 'IRC 채널이 제거되었습니다: $channel';
  }

  @override
  String get removeIrcChannel => 'IRC 채널 제거';

  @override
  String removeIrcChannelConfirm(String channel) {
    return '$channel을(를) 제거하시겠습니까? 해당 그룹에서 나가게 됩니다.';
  }

  @override
  String get remove => '제거';

  @override
  String get joinIrcChannel => 'IRC 채널 참가';

  @override
  String get ircChannelName => 'IRC 채널 이름';

  @override
  String get ircChannelHint => '#채널';

  @override
  String get ircChannelDesc => 'IRC 채널 이름을 입력하세요 (예: #channel). 이 채널에 대한 Tox 그룹이 생성됩니다.';

  @override
  String get enterIrcChannel => 'IRC 채널 이름을 입력하세요';

  @override
  String get invalidIrcChannel => 'IRC 채널은 # 또는 &로 시작해야 합니다';

  @override
  String get join => '참가';

  @override
  String get ircAppNotInstalled => '먼저 애플리케이션 페이지에서 IRC 채널 앱을 설치하세요';

  @override
  String get ircChannelPassword => '채널 비밀번호';

  @override
  String get ircChannelPasswordHint => '비밀번호가 없으면 비워두세요';

  @override
  String get ircCustomNickname => '사용자 정의 IRC 닉네임';

  @override
  String get ircCustomNicknameHint => '비워두면 자동 생성된 닉네임을 사용합니다';

  @override
  String deleteAccountFailed(String error) {
    return '계정 삭제 실패: $error';
  }

  @override
  String get directorySelectionNotSupported => '이 플랫폼에서는 디렉토리 선택이 지원되지 않습니다';

  @override
  String failedToSendFriendRequest(String error) {
    return '친구 요청 전송 실패: $error';
  }

  @override
  String get fileDoesNotExist => '파일이 존재하지 않습니다';

  @override
  String get fileIsEmpty => '파일이 비어 있습니다';

  @override
  String failedToSendFile(String label, String error) {
    return '$label 전송 실패: $error';
  }

  @override
  String get noReceivers => '아직 수신자가 없습니다';

  @override
  String messageReceivers(String count) {
    return '메시지 수신자 ($count)';
  }

  @override
  String get close => '닫기';

  @override
  String get nodeNotTestedWarning => '참고: 이 노드는 테스트되지 않았으며 연결할 수 없을 수 있습니다.';

  @override
  String get nodeTestFailedWarning => '참고: 이 노드 테스트가 실패했으며 연결할 수 없을 수 있습니다.';

  @override
  String get nicknameTooLong => '닉네임이 너무 깁니다';

  @override
  String get nicknameCannotBeEmpty => '닉네임을 입력해 주세요';

  @override
  String get statusMessageTooLong => '상태 메시지가 너무 깁니다';

  @override
  String get manualNodeInput => '수동 노드 입력';

  @override
  String get nodeHost => '호스트';

  @override
  String get nodePort => '포트';

  @override
  String get nodePublicKey => '공개 키';

  @override
  String get setAsCurrentNode => '현재 노드로 설정';

  @override
  String get nodeTestSuccess => '노드 테스트 성공';

  @override
  String get nodeTestFailed => '노드 테스트 실패';

  @override
  String get invalidNodeInfo => '유효한 노드 정보(호스트, 포트, 공개 키)를 입력하세요';

  @override
  String get nodeSetSuccess => '노드가 현재 노드로 성공적으로 설정되었습니다';

  @override
  String get bootstrapNodeMode => 'Bootstrap 노드 모드';

  @override
  String get manualMode => '수동 지정';

  @override
  String get autoMode => '자동 (웹에서 가져오기)';

  @override
  String get manualModeDesc => 'Bootstrap 노드 정보를 수동으로 지정';

  @override
  String get autoModeDesc => '웹에서 자동으로 Bootstrap 노드를 가져와 사용';

  @override
  String get autoModeDescPrefix => '자동으로 에서 Bootstrap 노드를 가져와 사용';

  @override
  String get lanMode => 'LAN 모드';

  @override
  String get lanModeDesc => '로컬 네트워크 Bootstrap 서비스 사용';

  @override
  String get startLocalBootstrapService => '로컬 Bootstrap 서비스 시작';

  @override
  String get stopLocalBootstrapService => '로컬 Bootstrap 서비스 중지';

  @override
  String get bootstrapServiceStatus => '서비스 상태';

  @override
  String get serviceRunning => '실행 중';

  @override
  String get serviceStopped => '중지됨';

  @override
  String get scanLanBootstrapServices => 'LAN Bootstrap 서비스 스캔';

  @override
  String get scanLanBootstrapServicesTitle => 'LAN Bootstrap 서비스';

  @override
  String get scanPort => '스캔 포트';

  @override
  String get startScan => '스캔 시작';

  @override
  String scanningAliveIPs(int current, int total) {
    return '활성 IP 스캔 중: $current/$total';
  }

  @override
  String probingBootstrapServices(int current, int total) {
    return 'Bootstrap 서비스 프로브 중: $current/$total';
  }

  @override
  String get scanning => '스캔 중...';

  @override
  String get probing => '프로브 중...';

  @override
  String aliveIPsFound(int count) {
    return '활성 IP 발견: $count';
  }

  @override
  String get noAliveIPsFound => '활성 IP를 찾을 수 없습니다';

  @override
  String get bootstrapServiceFound => 'Bootstrap 서비스 발견';

  @override
  String get noBootstrapService => 'Bootstrap 서비스를 찾을 수 없습니다';

  @override
  String get noServicesFound => '서비스를 찾을 수 없습니다';

  @override
  String get useAsBootstrapNode => 'Bootstrap 노드로 사용';

  @override
  String get ipAddress => 'IP 주소';

  @override
  String get probeStatus => '프로브 상태';

  @override
  String get probeSingleIP => '이 IP 프로브';

  @override
  String probingIP(String ip) {
    return '$ip 프로브 중...';
  }

  @override
  String get refreshAliveIPs => '활성 IP 새로고침';

  @override
  String get aliveIPsList => '활성 IP 목록';

  @override
  String get notProbedYet => '아직 프로브되지 않음';

  @override
  String get probeSuccess => 'Bootstrap 서비스 발견';

  @override
  String get probeFailed => 'Bootstrap 서비스를 찾을 수 없습니다';

  @override
  String bootstrapServiceRunning(String ip, int port) {
    return 'Bootstrap 서비스 실행 중: $ip:$port';
  }

  @override
  String get logOut => '로그아웃';

  @override
  String get logOutConfirm => '로그아웃하시겠습니까?';

  @override
  String get autoLogin => '자동 로그인';

  @override
  String get autoLoginEnabled => '자동 로그인: 활성화됨';

  @override
  String get autoLoginDisabled => '자동 로그인: 비활성화됨';

  @override
  String get autoLoginDesc => '활성화하면 앱 시작 시 자동으로 로그인됩니다.';

  @override
  String get disable => '비활성화';

  @override
  String get enable => '활성화';

  @override
  String get login => '로그인';

  @override
  String get register => '등록';

  @override
  String get registerNewAccount => '새 계정 등록';

  @override
  String get unnamedAccount => '이름 없는 계정';

  @override
  String get accountInfo => '계정 정보';

  @override
  String get accountManagement => '계정 관리';

  @override
  String get localAccounts => '로컬 계정';

  @override
  String showMore(int count) {
    return '$count개 더 보기';
  }

  @override
  String get showLess => '접기';

  @override
  String get current => '현재';

  @override
  String get lastLogin => '최근 로그인';

  @override
  String get switchAccount => '계정 전환';

  @override
  String get exportAccount => '계정 내보내기';

  @override
  String get exportOptionProfileTox => 'Profile (.tox)';

  @override
  String get exportOptionProfileToxSubtitle => 'qTox compatible, profile only';

  @override
  String get exportOptionFullBackup => 'Full Backup (.zip)';

  @override
  String get exportOptionFullBackupSubtitle => 'Profile + chat history + settings';

  @override
  String get importAccount => '계정 가져오기';

  @override
  String get setPassword => '비밀번호 설정';

  @override
  String get changePassword => '비밀번호 변경';

  @override
  String get enterPasswordToExport => '계정을 내보내려면 비밀번호를 입력하세요';

  @override
  String get enterPasswordToImport => '계정을 가져오려면 비밀번호를 입력하세요';

  @override
  String enterPasswordForAccount(String nickname) {
    return '계정 \"$nickname\"의 비밀번호를 입력하세요';
  }

  @override
  String get invalidPassword => '비밀번호가 올바르지 않습니다';

  @override
  String accountExportedSuccessfully(String filePath) {
    return '계정이 성공적으로 내보내졌습니다: $filePath';
  }

  @override
  String get accountImportedSuccessfully => '계정이 성공적으로 가져와졌습니다';

  @override
  String get passwordSetSuccessfully => '비밀번호가 성공적으로 설정되었습니다';

  @override
  String get passwordRemoved => '비밀번호가 제거되었습니다';

  @override
  String failedToSwitchAccount(String error) {
    return '계정 전환 실패: $error';
  }

  @override
  String failedToExportAccount(String error) {
    return '계정 내보내기 실패: $error';
  }

  @override
  String failedToImportAccount(String error) {
    return '계정 가져오기 실패: $error';
  }

  @override
  String failedToSetPassword(String error) {
    return '비밀번호 설정 실패: $error';
  }

  @override
  String get noAccountToExport => '내보낼 계정이 없습니다';

  @override
  String get noAccountSelected => '계정이 선택되지 않았습니다';

  @override
  String get accountAlreadyExists => '계정이 이미 존재합니다';

  @override
  String get accountAlreadyExistsMessage => '이 ID의 계정이 이미 존재합니다. 업데이트하시겠습니까?';

  @override
  String get update => '업데이트';

  @override
  String switchAccountConfirm(String nickname) {
    return '\"$nickname\"로 전환하시겠습니까? 현재 계정에서 로그아웃됩니다.';
  }

  @override
  String get savedAccounts => '저장된 계정';

  @override
  String get tapToSelectDoubleTapToLogin => '탭하여 선택, 더블 탭하여 빠른 로그인';

  @override
  String get tapToLogIn => '탭하여 로그인';

  @override
  String get switchToThisAccount => '이 계정으로 전환';

  @override
  String get password => '비밀번호';

  @override
  String get newPassword => '새 비밀번호';

  @override
  String get confirmPassword => '비밀번호 확인';

  @override
  String get leaveEmptyToRemovePassword => '비워두면 비밀번호 제거';

  @override
  String get passwordsDoNotMatch => '비밀번호가 일치하지 않습니다';

  @override
  String get never => '없음';

  @override
  String get justNow => '방금';

  @override
  String daysAgo(int count, String plural) {
    return '$count일 전';
  }

  @override
  String hoursAgo(int count, String plural) {
    return '$count시간 전';
  }

  @override
  String minutesAgo(int count, String plural) {
    return '$count분 전';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '이 계정은 이미 로그인되어 있습니다';

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
    return '연락처 $contacts개, 그룹 $groups개, 메시지 스레드 $messages개를 찾았습니다';
  }

  @override
  String get searchFailed => '검색에 실패했습니다. 부분 결과를 표시합니다';

  @override
  String get callVideoCall => '영상 통화';

  @override
  String get callAudioCall => '음성 통화';

  @override
  String get callReject => '거절';

  @override
  String get callAccept => '수락';

  @override
  String get callRemoteVideo => '상대 화면';

  @override
  String get callUnmute => '음소거 해제';

  @override
  String get callMute => '음소거';

  @override
  String get callVideoOff => '영상 끄기';

  @override
  String get callVideoOn => '영상 켜기';

  @override
  String get callSpeakerOff => '스피커 끄기';

  @override
  String get callSpeakerOn => '스피커 켜기';

  @override
  String get callHangUp => '통화 종료';

  @override
  String get callEnded => '통화가 종료되었습니다';

  @override
  String get callPermissionMicrophoneRequired => '통화를 계속하려면 마이크 권한이 필요합니다.';

  @override
  String get callPermissionCameraRequired => '통화를 계속하려면 카메라 권한이 필요합니다.';

  @override
  String get callPermissionMicrophoneCameraRequired => '통화를 계속하려면 마이크 및 카메라 권한이 필요합니다.';

  @override
  String get callAudioInterrupted => '통화 중 오디오 출력이 변경되었거나 중단되었습니다.';

  @override
  String get callCalling => '전화 거는 중...';

  @override
  String get callMinimize => '최소화';

  @override
  String get callReturnToCall => '통화로 돌아가기';

  @override
  String get callQualityGood => '연결 양호';

  @override
  String get callQualityMedium => '연결 보통';

  @override
  String get callQualityPoor => '연결 불량';

  @override
  String get callQualityUnknown => '—';

  @override
  String get callQualityLabel => '통화 품질';

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

  @override
  String get pairDeviceHostTitle => 'Pair another device';

  @override
  String get pairDeviceClientTitle => 'Pair with another device';

  @override
  String get pairingHostInstructions => 'Open toxee on your other device, choose \"Pair with another device\", and scan this QR code.';

  @override
  String get pairingClientScanInstructions => 'Point your camera at the QR code on your other device.';

  @override
  String get pairingClientPasteInstructions => 'Camera scanning isn\'t supported on this device. Paste the pairing URL shown on your other device below.';

  @override
  String get pairingPasteUrlLabel => 'Pairing URL';

  @override
  String get pairingConnectButton => 'Connect';

  @override
  String get pairingWaitingForPeer => 'Waiting for the other device to connect…';

  @override
  String get pairingVerifyCodeHeader => 'Verify both devices show the same code';

  @override
  String get pairingVerifyCodeInstructions => 'If the code matches what\'s shown on your other device, tap below. If they differ, cancel — someone may be intercepting the connection.';

  @override
  String get pairingCodesMatch => 'The codes match';

  @override
  String get pairingHostCompleted => 'Account sent. The other device now has your account.';

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
  String get pairingDecryptFailed => 'Couldn\'t decrypt the received profile. The pairing may have been tampered with — try again on a network you trust.';

  @override
  String get pairingNoLanInterface => 'No LAN network detected. Connect to WiFi or Ethernet and try again.';

  @override
  String get pairThisAccountToAnotherDevice => 'Pair this account to another device';

  @override
  String get pairWithAnotherDevice => 'Pair with another device that has my account';

  @override
  String get devicesSectionTitle => 'Devices';

  @override
  String get done => 'Done';
}
