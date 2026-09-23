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
  String get general => '일반';

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
  String get joinQueued => '오프라인 — 다시 연결되면 참가 요청을 보냅니다';

  @override
  String get offlineBanner => '오프라인 — 그룹 작업은 다시 연결되면 대기열에서 처리됩니다.';

  @override
  String get groupType => '그룹 유형';

  @override
  String get publicGroup => '공개';

  @override
  String get privateGroup => '비공개';

  @override
  String get publicGroupHint =>
      '공개 그룹 — DHT에서 검색 가능하며 채팅 ID를 아는 누구나 참가할 수 있습니다.';

  @override
  String get privateGroupHint => '비공개 그룹 — 초대 전용이며 DHT에 공지되지 않습니다.';

  @override
  String get conferenceHint => '레거시 컨퍼런스 — 오래된 프로토콜, 역할이나 지속성 없음.';

  @override
  String get searchHintBody => '연락처, 그룹, 메시지 검색';

  @override
  String get noResultsFoundHint => '더 짧은 키워드를 시도하거나 철자를 확인하세요';

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
  String get invalidLength => 'ID 길이가 올바르지 않습니다';

  @override
  String get invalidCharacters => '16진수 문자만 포함할 수 있습니다';

  @override
  String get paste => '붙여넣기';

  @override
  String get addContactHint => '상대방의 Tox 주소를 입력하세요.';

  @override
  String get addFriendInvalidToxIdHint => 'Tox 주소는 76자의 16진수 문자여야 합니다';

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
  String get reconnectConfirmMessage =>
      '선택한 Bootstrap 노드를 사용하여 재연결합니다. 계속하시겠습니까?';

  @override
  String get reconnectedWaiting => '다시 로그인했습니다. 연결 대기 중...';

  @override
  String get reconnectWithThisNode => '이 노드로 재연결';

  @override
  String get friendOfflineCannotSendFile =>
      '친구가 오프라인입니다. 파일을 보낼 수 없습니다. 온라인 상태가 될 때까지 기다려주세요.';

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
  String get deleteAccountConfirmMessage =>
      '계정과 모든 데이터가 영구적으로 삭제되며 복구할 수 없습니다. 신중하게 진행하세요.';

  @override
  String get delete => '삭제';

  @override
  String get deleteAccountEnterPasswordToConfirm =>
      '삭제를 확인하려면 현재 계정 비밀번호를 입력하세요.';

  @override
  String get deleteAccountTypeWordToConfirm =>
      '삭제를 확인하려면 아래에 표시된 영어 단어를 정확히 입력하세요.';

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
  String get downloadsDirectoryDesc =>
      '파일 다운로드의 기본 디렉토리를 설정합니다. 수신한 파일, 오디오 및 비디오는 이 디렉토리에 저장됩니다.';

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
  String get autoDownloadSizeLimitDesc =>
      '이 크기보다 작은 파일과 모든 이미지는 자동으로 다운로드됩니다. 이 크기보다 큰 파일은 수동으로 다운로드 버튼을 클릭해야 합니다.';

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
  String get canOnlySelectTestedNode => '이 노드를 선택하기 전에 부트스트랩 요청을 보내세요';

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
  String get uninstallIrcAppConfirm =>
      'IRC 채널 앱을 제거하시겠습니까? 모든 IRC 채널이 제거되고 모든 IRC 그룹에서 나가게 됩니다.';

  @override
  String get addIrcChannel => '채널 추가';

  @override
  String get ircChannels => 'IRC 채널';

  @override
  String get ircStatusDisconnected => '연결 끊김';

  @override
  String get ircStatusConnecting => '연결 중';

  @override
  String get ircStatusConnected => '연결됨';

  @override
  String get ircStatusAuthenticating => '인증 중';

  @override
  String get ircStatusReconnecting => '재연결 중';

  @override
  String get ircStatusError => '오류';

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
  String ircChannelAddedNotConnected(String channel) {
    return '채널 $channel이(가) 추가되었지만 IRC 연결을 설정할 수 없습니다';
  }

  @override
  String get ircAppInstalledNoLibrary =>
      'IRC 앱이 설치되었지만 이 기기에서는 실시간 IRC를 사용할 수 없습니다';

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
  String get ircChannelDesc =>
      'IRC 채널 이름을 입력하세요 (예: #channel). 이 채널에 대한 Tox 그룹이 생성됩니다.';

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
  String get nodeNotTestedWarning => '이 노드는 아직 테스트되지 않았습니다.';

  @override
  String get nodeTestFailedWarning => '이 노드가 응답하지 않았습니다. 사용할 수 없을 수 있습니다.';

  @override
  String get nodeTestInconclusiveWarning =>
      '이 기기에서는 이 노드를 확인할 수 없어 사용 가능 여부를 알 수 없습니다.';

  @override
  String get nicknameTooLong => '닉네임이 너무 깁니다';

  @override
  String get nicknameCannotBeEmpty => '닉네임을 입력해 주세요';

  @override
  String get statusMessageTooLong => '상태 메시지가 너무 깁니다';

  @override
  String get passwordStrengthWeak => '약함';

  @override
  String get passwordStrengthFair => '보통';

  @override
  String get passwordStrengthGood => '좋음';

  @override
  String get passwordStrengthStrong => '강함';

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
  String get nodeTestSuccess => '노드에 연결됨';

  @override
  String get nodeTestUdpUnavailable =>
      '노드 테스트에는 UDP가 필요합니다. 이 기기는 TCP 전용으로 동작 중입니다';

  @override
  String get nodeTestFailed => '노드에 연결할 수 없음';

  @override
  String get nodeTestUnavailable => '이 기기에서는 노드 테스트를 실행할 수 없습니다';

  @override
  String get failedToLoadBootstrapNodes => '부트스트랩 노드를 불러오지 못했습니다';

  @override
  String get failedToStartBootstrapService => '부트스트랩 서비스 시작에 실패했습니다';

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
  String get exportOptionProfileTox => '프로필 (.tox)';

  @override
  String get exportOptionProfileToxSubtitle => 'qTox 호환, 프로필만';

  @override
  String get exportOptionFullBackup => '전체 백업 (.zip)';

  @override
  String get exportOptionFullBackupSubtitle => '프로필 + 채팅 기록 + 설정';

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
  String daysAgo(int count) {
    return '$count일 전';
  }

  @override
  String hoursAgo(int count) {
    return '$count시간 전';
  }

  @override
  String minutesAgo(int count) {
    return '$count분 전';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => '이 계정은 이미 로그인되어 있습니다';

  @override
  String get upgradeRequiredTitle => '앱을 업그레이드하세요';

  @override
  String upgradeRequiredMessage(int storedVersion, int currentVersion) {
    return '데이터가 더 새로운 버전의 앱에서 저장되었습니다(데이터 버전: $storedVersion). 이 버전은 $currentVersion까지만 지원합니다. 계속하려면 최신 업데이트를 설치하세요.';
  }

  @override
  String get upgradeAppTitle => 'toxee';

  @override
  String get hide => '숨기기';

  @override
  String get pressBackAgainToExit => '뒤로 가기를 한 번 더 누르면 종료됩니다';

  @override
  String get startupFailed => '시작 실패';

  @override
  String get unknownError => '알 수 없는 오류';

  @override
  String get goToLogin => '로그인으로 이동';

  @override
  String get conference => '컨퍼런스';

  @override
  String get defaultJoinRequestMessage => '안녕하세요, 이 그룹에 초대해 주세요';

  @override
  String get userNotFoundPleaseRegister => '사용자를 찾을 수 없습니다. 먼저 등록하세요.';

  @override
  String get nicknameDoesNotMatch =>
      '닉네임이 일치하지 않습니다. 등록한 닉네임을 사용하거나 새 계정을 등록하세요.';

  @override
  String get accountAlreadyExistsPleaseLogin =>
      '계정이 이미 존재합니다. 로그인하거나 다른 닉네임을 사용하세요.';

  @override
  String get profileNotFoundImportRestore =>
      '이 계정의 프로필을 찾을 수 없습니다. 프로필을 가져오거나 백업을 복원하세요.';

  @override
  String get failedToInitializeTIMManager => 'TIMManager SDK 초기화에 실패했습니다';

  @override
  String get failedToGetToxId => 'Tox ID를 가져오지 못했습니다';

  @override
  String get failedToGenerateToxId => 'Tox ID를 생성하지 못했습니다';

  @override
  String get registrationCouldNotCreateProfile =>
      '고유한 프로필을 만들지 못해 등록할 수 없습니다. 다시 시도하세요.';

  @override
  String get importedAccount => '가져온 계정';

  @override
  String get unknown => '알 수 없음';

  @override
  String sendingToGroupsNotSupported(String label) {
    return '그룹에 $label 보내기는 아직 지원되지 않습니다';
  }

  @override
  String noLabelSelected(String label) {
    return '선택한 $label이(가) 없습니다';
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
  String get callSwitchCamera => '카메라 전환';

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
  String get callPermissionMicrophoneCameraRequired =>
      '통화를 계속하려면 마이크 및 카메라 권한이 필요합니다.';

  @override
  String get callIncomingNotificationPermissionRequired =>
      '알림 권한을 켤 때까지 수신 전화는 Toxee 안에서만 울립니다.';

  @override
  String get callFailedGroupUnsupported => '그룹 통화는 아직 지원되지 않습니다.';

  @override
  String get callFailedSignaling => '통화를 시작할 수 없습니다. 다시 시도해 주세요.';

  @override
  String get callFailedMediaChannel => '통화 미디어 채널을 설정할 수 없습니다.';

  @override
  String get callVideoUnsupportedPlatform =>
      '이 플랫폼에서는 아직 영상 통화를 사용할 수 없습니다(카메라 미지원).';

  @override
  String get callAudioInterrupted => '통화 중 오디오 출력이 변경되었거나 중단되었습니다.';

  @override
  String get callBusyInCall => '먼저 현재 통화를 종료하세요.';

  @override
  String get callBusyInConference => '통화를 걸거나 받기 전에 음성 회의에서 나가세요.';

  @override
  String get callBusyInOtherConference => '이미 다른 음성 회의에 참여 중입니다. 먼저 나가세요.';

  @override
  String get callPeerBusy => '상대방이 다른 통화 중입니다.';

  @override
  String get callConferenceMuteIncoming => '다른 참가자 음소거';

  @override
  String get callConferenceUnmuteIncoming => '다른 참가자 듣기';

  @override
  String get callConferenceListenOnly => '듣기 전용 — 마이크를 사용할 수 없습니다.';

  @override
  String get callCalling => '전화 거는 중...';

  @override
  String get callLeaving => '회의를 나가는 중...';

  @override
  String callReceivedFrames(int count) {
    return '수신 프레임 $count';
  }

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
    return '읽지 않은 메시지 $count개';
  }

  @override
  String matchingMessagesSemantics(int count) {
    return '일치하는 메시지 $count개';
  }

  @override
  String get statusOnline => '온라인';

  @override
  String get statusOffline => '오프라인';

  @override
  String get noIrcChannels => 'IRC 채널 없음';

  @override
  String get joinChannelToGetStarted => '채널에 참가하여 시작하세요';

  @override
  String ircUsersCount(int count) {
    return '사용자 ($count)';
  }

  @override
  String get ircNoUsers => '사용자 없음';

  @override
  String get passwordVisibility => '비밀번호 표시/숨기기';

  @override
  String get nicknameHintExample => '예: Alice';

  @override
  String get callAudioRouteSystem => '이 플랫폼에서는 시스템이 오디오 경로를 관리합니다';

  @override
  String get copyFullToxId => '전체 ID 복사';

  @override
  String get themeSystem => '시스템';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get idLabel => 'ID:';

  @override
  String errorBannerLabel(String message) {
    return '오류: $message';
  }

  @override
  String searchResultContactSemantics(String name) {
    return '$name, 연락처';
  }

  @override
  String searchResultGroupSemantics(String name) {
    return '$name, 그룹';
  }

  @override
  String searchResultMessageSemantics(String name) {
    return '$name, 메시지';
  }

  @override
  String searchResultConversationSemantics(String name) {
    return '$name, 대화';
  }

  @override
  String get importNoFileSelected => '선택한 파일이 없습니다';

  @override
  String get importCancelled => '취소됨';

  @override
  String get recoveryBlockedTitle => '계정 복구가 완료되지 않았습니다';

  @override
  String get recoveryBlockedBody =>
      'toxee가 읽을 수 없는 미완료 계정 복원 또는 삭제 작업을 발견하여 어떤 계정도 열지 않았습니다. 계속 진행하면 데이터가 손상될 수 있습니다.\n\n계정과 프로필은 아직 이 기기에 남아 있습니다. 다시 등록하거나 앱 데이터를 지우지 마세요. 어느 쪽이든 데이터가 영구적으로 손실됩니다. 복구할 수 있도록 아래 세부 정보를 보고해 주세요.';

  @override
  String get secureStorageUnavailable =>
      '보안 저장소를 사용할 수 없어 toxee가 이 계정의 비밀번호를 확인할 수 없습니다. 보통 일시적인 문제입니다. 다시 시도하거나 기기의 키체인 잠금을 해제하세요.';

  @override
  String get recoverLegacyDataAction => '이전 버전의 데이터 복구';

  @override
  String get recoverLegacyDataConfirm =>
      '이 기기에는 toxee가 다중 계정을 지원하기 전의 채팅 기록, 대기 중인 메시지, 연락처 아바타가 남아 있습니다. 현재 로그인한 계정에 추가하시겠습니까?\n\n본인의 데이터인 경우에만 진행하세요. 이 데이터는 한 계정에서 한 번만 가져올 수 있습니다.\n\n다음 로그인 시 병합되도록 로그아웃됩니다.';

  @override
  String get recoverLegacyDataClaimed =>
      '이 계정이 이전 데이터를 가져옵니다. 병합하려면 로그아웃한 후 다시 로그인하세요. 로그인 시 병합해야 현재 기록과 대기 중인 메시지가 그대로 유지됩니다.';

  @override
  String get recoverLegacyDataDone => '이전 데이터를 이 계정에 추가했습니다.';

  @override
  String get recoverLegacyDataUnavailable =>
      '데이터를 가져올 수 없습니다. 이 기기의 다른 계정에 이미 속해 있을 수 있습니다.';

  @override
  String get accountRegistryUnreadable =>
      '저장된 계정을 읽을 수 없습니다. 프로필은 아직 이 기기에 남아 있으니 다시 등록하지 마세요. 계정 목록을 복구할 수 있도록 이 문제를 보고해 주세요.';

  @override
  String get importedAccountDefaultName => '가져온 계정';

  @override
  String failedToImport(String error) {
    return '가져오기 실패: $error';
  }

  @override
  String get selectConversationEmptyState => '대화를 선택하여 채팅을 시작하세요';

  @override
  String get newConversationTooltip => '새 대화';

  @override
  String get pinConversation => '고정';

  @override
  String get unpinConversation => '고정 해제';

  @override
  String get markConversationAsRead => '읽음으로 표시';

  @override
  String get deleteConversationTitle => '대화를 삭제하시겠습니까?';

  @override
  String deleteConversationBody(String name) {
    return '채팅 목록에서 \"$name\"을(를) 제거합니다. 메시지 기록은 디스크에 남아 있습니다.';
  }

  @override
  String get firstRunBackupWizardTitle => '계정 파일 저장';

  @override
  String get firstRunBackupWizardBody =>
      '계정은 이 기기에만 저장되어 있습니다. .tox 파일을 안전한 곳(클라우드 저장소, 비밀번호 관리자, USB 드라이브)에 저장하세요. 파일이 없으면 이 기기를 분실할 경우 계정과 모든 연락처를 영구적으로 잃게 됩니다.';

  @override
  String get firstRunBackupWizardExportNow => '지금 내보내기';

  @override
  String get firstRunBackupWizardLater => '나중에 하기';

  @override
  String get firstRunBackupWizardDismissTitle => '백업을 건너뛰시겠습니까?';

  @override
  String get firstRunBackupWizardDismissBody =>
      '이 기기를 분실하면 계정과 모든 연락처를 잃게 됩니다. 복구할 방법이 없습니다.';

  @override
  String get firstRunBackupWizardDismissConfirm => '이해했습니다. 계속';

  @override
  String firstRunBackupWizardExportFailed(String error) {
    return '계정 파일을 저장하지 못했습니다: $error';
  }

  @override
  String get restoreFromToxFile => '.tox 파일에서 복원';

  @override
  String restoreFromToxFileSuccess(String nickname) {
    return '계정을 복원했습니다: $nickname';
  }

  @override
  String get restoreFromToxFileInvalidFile => '유효한 Tox 프로필 파일이 아닙니다.';

  @override
  String get pairDeviceHostTitle => '다른 기기 페어링';

  @override
  String get pairDeviceClientTitle => '다른 기기와 페어링';

  @override
  String get pairingHostInstructions =>
      '다른 기기에서 toxee를 열고 \"다른 기기와 페어링\"을 선택한 다음 이 QR 코드를 스캔하세요.';

  @override
  String get pairingClientScanInstructions => '다른 기기에 표시된 QR 코드에 카메라를 맞추세요.';

  @override
  String get pairingClientPasteInstructions =>
      '이 기기에서는 카메라 스캔이 지원되지 않습니다. 다른 기기에 표시된 페어링 URL을 아래에 붙여넣으세요.';

  @override
  String get pairingPasteUrlLabel => '페어링 URL';

  @override
  String get pairingConnectButton => '연결';

  @override
  String get pairingWaitingForPeer => '다른 기기의 연결을 기다리는 중…';

  @override
  String get pairingVerifyCodeHeader => '두 기기에 같은 코드가 표시되는지 확인하세요';

  @override
  String get pairingVerifyCodeInstructions =>
      '코드가 다른 기기에 표시된 코드와 일치하면 아래를 탭하세요. 다르면 취소하세요. 누군가 연결을 가로채고 있을 수 있습니다.';

  @override
  String get pairingCodesMatch => '코드가 일치합니다';

  @override
  String get pairingHostCompleted => '계정을 보냈습니다. 이제 다른 기기에서 계정을 사용할 수 있습니다.';

  @override
  String get pairingClientCompleted => '계정을 받았습니다. 페어링이 완료되었습니다.';

  @override
  String get pairingCancelled => '페어링이 취소되었습니다.';

  @override
  String get pairingTimeout => '페어링 시간이 초과되었습니다. 다시 시도하세요.';

  @override
  String pairingNetworkError(String detail) {
    return '페어링 중 네트워크 오류: $detail';
  }

  @override
  String pairingProtocolError(String detail) {
    return '페어링 핸드셰이크 실패: $detail';
  }

  @override
  String pairingInvalidUrl(String detail) {
    return '유효한 페어링 초대 QR 코드가 아닙니다: $detail';
  }

  @override
  String get pairingDecryptFailed =>
      '받은 프로필을 복호화하지 못했습니다. 페어링이 변조되었을 수 있습니다. 신뢰할 수 있는 네트워크에서 다시 시도하세요.';

  @override
  String get pairingNoLanInterface =>
      'LAN 네트워크가 감지되지 않았습니다. Wi-Fi 또는 이더넷에 연결한 후 다시 시도하세요.';

  @override
  String get pairThisAccountToAnotherDevice => '이 계정을 다른 기기와 페어링';

  @override
  String get pairWithAnotherDevice => '내 계정이 있는 다른 기기와 페어링';

  @override
  String get devicesSectionTitle => '기기';

  @override
  String get done => '완료';

  @override
  String get runtimeForegroundTitle => 'Toxee 실행 중';

  @override
  String get runtimeForegroundBody => '메시지와 통화를 받을 수 있도록 연결을 유지합니다.';

  @override
  String get runtimeForegroundSettingsLabel => '알림 설정';

  @override
  String get runtimeForegroundCallTitle => '통화 중';

  @override
  String get runtimeForegroundCallBody => 'Toxee가 통화 연결을 유지하고 있습니다.';

  @override
  String runtimeForegroundCallBodyWithCaller(String name) {
    return '$name님과 통화 중';
  }

  @override
  String get appTagline => '프라이빗 P2P 메신저';

  @override
  String get noBootstrapNodes => '부트스트랩 노드가 없습니다';

  @override
  String get importMayHaveCompleted =>
      '가져오기를 되돌리지 못해 이 계정이 아직 남아 있을 수 있습니다. 다시 가져오기 전에 계정 목록을 확인하세요.';

  @override
  String get importBlockedByPendingImport =>
      '중단된 다른 계정 가져오기가 아직 정리되지 않았습니다. toxee를 다시 시작하여 되돌리기를 완료한 후 다시 가져오세요.';

  @override
  String get friendRequestQueued => '오프라인 — 요청이 대기열에 추가되었으며 다시 연결되면 전송됩니다';

  @override
  String get cannotAddSelfAsFriend => '자신을 친구로 추가할 수 없습니다';

  @override
  String get friendRequestAlreadySent => '이번 세션에서 이미 친구 요청을 보냈습니다';

  @override
  String get alreadyInFriendList => '이 사용자는 이미 친구 목록에 있습니다';

  @override
  String get addFriendOfflineBanner =>
      '오프라인 — 친구 요청은 대기열에 추가되며 다시 연결되면 자동으로 전송됩니다.';

  @override
  String get scanQr => 'QR 스캔';

  @override
  String get sendingInProgress => '보내는 중...';

  @override
  String get firewallHintWindows =>
      'Windows에서는 방화벽이 들어오는 연결을 차단할 수 있습니다. 메시지가 표시되면 앱을 허용하세요.';

  @override
  String get firewallHintLinux =>
      'Linux에서는 네트워크 작업에 적절한 권한이나 방화벽 규칙이 필요할 수 있습니다.';

  @override
  String get nodePublicKeyHint => '공개 키 (16진수)';

  @override
  String get failedToAddBootstrapNode => '부트스트랩 노드를 추가하지 못했습니다';

  @override
  String get couldNotRemovePassword => '비밀번호를 제거할 수 없습니다';

  @override
  String get couldNotSavePassword => '비밀번호를 저장할 수 없습니다';

  @override
  String mediaSent(String label) {
    return '$label을(를) 보냈습니다';
  }

  @override
  String get dhtUnreachableUsingFallback =>
      'DHT에 연결할 수 없습니다. 대체 부트스트랩 노드를 사용합니다. 네트워크에서 UDP를 차단하고 있거나 노드가 다운되었을 수 있습니다.';

  @override
  String get dhtUnreachableTimeout =>
      '30초 후에도 DHT에 연결할 수 없습니다. 네트워크 연결을 확인하세요.';

  @override
  String chatSdkInitFailed(String error) {
    return '채팅 SDK 초기화 실패: $error';
  }

  @override
  String messageTooLongMaxBytes(int maxBytes) {
    return '메시지가 너무 깁니다(최대 $maxBytes바이트)';
  }

  @override
  String get friendOfflineWillRetry => '친구가 오프라인입니다 — 다시 연결되면 재시도합니다';

  @override
  String get groupFileTransferUnsupported => '그룹 채팅에서는 파일 전송이 지원되지 않습니다';

  @override
  String fileSendFailed(String error) {
    return '파일 전송 실패: $error';
  }

  @override
  String errorWithCode(int code) {
    return '오류 $code';
  }

  @override
  String pairingLanUnreachable(String detail) {
    return '이 네트워크에서는 기기끼리 서로 찾을 수 없습니다. 개인용 핫스팟을 사용하거나 내보내기 → 파일로 가져오기를 이용하세요. ($detail)';
  }

  @override
  String get notificationNewFriendRequest => '새 친구 요청';

  @override
  String notificationFriendRequestFrom(String name) {
    return '친구 요청: $name';
  }

  @override
  String get notificationMissedCall => '부재중 전화';

  @override
  String get notificationMissedVideoCall => '부재중 영상 통화';

  @override
  String get notificationIncomingCall => '수신 전화';

  @override
  String get notificationIncomingVideoCall => '수신 영상 통화';

  @override
  String get notificationUnknownCaller => 'Toxee 연락처';

  @override
  String get notificationNewMessage => '새 메시지';

  @override
  String get previewImage => '[이미지]';

  @override
  String get previewVideo => '[비디오]';

  @override
  String get previewVoice => '[음성]';

  @override
  String previewVoiceWithDuration(int seconds) {
    return '[음성 $seconds초]';
  }

  @override
  String get previewFile => '[파일]';

  @override
  String previewFileWithName(String name) {
    return '[파일] $name';
  }

  @override
  String get previewSticker => '[스티커]';

  @override
  String get previewLocation => '[위치]';

  @override
  String get previewCustomMessage => '[사용자 정의 메시지]';

  @override
  String get previewGroupEvent => '[그룹 이벤트]';

  @override
  String get previewMessage => '[메시지]';

  @override
  String get channelMessagesName => '메시지';

  @override
  String get channelMessagesDescription => 'Tox 연락처로부터 새 메시지가 도착하면 알림을 표시합니다.';

  @override
  String get channelFriendRequestsName => '친구 요청';

  @override
  String get channelFriendRequestsDescription => '누군가 친구 요청을 보내면 알림을 표시합니다.';

  @override
  String get channelGroupInvitesName => '그룹 초대';

  @override
  String get channelGroupInvitesDescription => '누군가 그룹에 초대하면 알림을 표시합니다.';

  @override
  String get channelMissedCallsName => '부재중 전화';

  @override
  String get channelMissedCallsDescription =>
      '수신 전화를 받지 못했거나 연결되지 않았을 때 알림을 표시합니다.';

  @override
  String get channelIncomingCallsName => '수신 전화';

  @override
  String get channelIncomingCallsDescription => 'Toxee 수신 전화에 대한 전체 화면 알림입니다.';

  @override
  String get notificationOpenAction => 'Toxee 열기';

  @override
  String trayUnreadTooltip(int count) {
    return '읽지 않음: $count';
  }

  @override
  String get unknownErrorReason => '알 수 없는 오류';

  @override
  String get notificationNoMessage => '(메시지 없음)';

  @override
  String notificationGroupedSummary(int count, String name) {
    return '$name님의 새 메시지 $count개';
  }

  @override
  String pairingConnectTimedOut(String endpoint) {
    return '제한 시간 안에 다른 기기($endpoint)에 연결하지 못했습니다. 두 기기가 같은 네트워크에 있는지 확인하거나, 개인용 핫스팟을 사용하거나, 파일로 내보내기 → 가져오기를 이용하세요.';
  }

  @override
  String get groupInviteTitle => '그룹 초대';

  @override
  String groupInviteBody(String inviter, String group) {
    return '$inviter 님이 “$group” 그룹에 초대했습니다.';
  }

  @override
  String groupInviteBodyUnnamed(String inviter) {
    return '$inviter 님이 그룹에 초대했습니다.';
  }

  @override
  String get groupInviteDecline => '거절';

  @override
  String get groupInviteLater => '나중에';

  @override
  String get groupInviteAcceptFailed =>
      '참가할 수 없습니다. 초대한 사람이 오프라인일 수 있습니다. 상대가 온라인일 때 다시 시도하세요.';

  @override
  String get alreadyInGroup => '이미 이 그룹에 참가 중입니다';

  @override
  String get groupNameTooLong => '그룹 이름이 너무 깁니다';

  @override
  String get leaveGroupFailed => '그룹에서 나가지 못했습니다. 다시 시도하세요.';

  @override
  String get groupPassword => '그룹 비밀번호 (선택)';

  @override
  String get groupPasswordTooLong => '그룹 비밀번호는 최대 32바이트입니다';

  @override
  String get groupJoinRefusedPassword => '이 그룹은 비밀번호가 필요하거나 비밀번호가 올바르지 않습니다.';

  @override
  String get groupJoinRefusedFull => '이 그룹은 정원이 가득 찼습니다.';

  @override
  String get groupJoinRefusedUnknown => '그룹이 참가를 거부했습니다.';

  @override
  String get groupJoinEnterPassword => '비밀번호 입력';

  @override
  String get groupPasswordRequired => '그룹 비밀번호를 입력하세요';
}
