// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get chats => 'الدردشات';

  @override
  String get contacts => 'جهات الاتصال';

  @override
  String get requests => 'الطلبات';

  @override
  String get groups => 'المجموعات';

  @override
  String get settings => 'الإعدادات';

  @override
  String get searchConversations => 'البحث بالاسم المستعار / المجموعة / الرسالة';

  @override
  String get searchContacts => 'البحث في جهات الاتصال';

  @override
  String get searchResults => 'نتائج البحث';

  @override
  String get enterKeywordToSearch => 'أدخل كلمة للبحث';

  @override
  String get noResultsFound => 'لم يتم العثور على نتائج';

  @override
  String get searchSectionMessages => 'الرسائل';

  @override
  String get searchSectionConversations => 'المحادثات';

  @override
  String get searchHint => 'بحث...';

  @override
  String messageCount(int count) {
    return '$count رسائل';
  }

  @override
  String get searchChatHistory => 'البحث في سجل الدردشة';

  @override
  String searchResultsCount(int count, String keyword) {
    return 'هناك $count نتائج لـ \"$keyword\"';
  }

  @override
  String get openChat => 'فتح الدردشة';

  @override
  String relatedChats(int count) {
    return '$count رسائل ذات صلة';
  }

  @override
  String get newItem => 'جديد';

  @override
  String get addFriend => 'إضافة صديق';

  @override
  String get createGroup => 'إنشاء مجموعة';

  @override
  String get friendUserId => 'معرف المستخدم للصديق (hex)';

  @override
  String get groupNameOptional => 'اسم المجموعة (اختياري)';

  @override
  String get typeMessage => 'اكتب رسالة';

  @override
  String get messageToGroup => 'رسالة إلى المجموعة';

  @override
  String get selfId => 'معرفي';

  @override
  String get appearance => 'المظهر';

  @override
  String get light => 'فاتح';

  @override
  String get dark => 'داكن';

  @override
  String get language => 'اللغة';

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
  String get profile => 'الملف الشخصي';

  @override
  String get nickname => 'الاسم المستعار';

  @override
  String get statusMessage => 'رسالة الحالة';

  @override
  String get saveProfile => 'حفظ الملف الشخصي';

  @override
  String get ok => 'موافق';

  @override
  String get cancel => 'إلغاء';

  @override
  String get group => 'مجموعة';

  @override
  String get file => 'ملف';

  @override
  String get audio => 'صوتي';

  @override
  String get friendRequestSent => 'تم إرسال طلب الصداقة';

  @override
  String get joinGroup => 'انضم إلى المجموعة';

  @override
  String get groupId => 'معرف المجموعة';

  @override
  String get createAndOpen => 'إنشاء وفتح';

  @override
  String get joinAndOpen => 'انضم وافتح';

  @override
  String get knownGroups => 'المجموعات المعروفة';

  @override
  String get selectAChat => 'اختر محادثة';

  @override
  String get photo => 'صورة';

  @override
  String get video => 'فيديو';

  @override
  String get autoAcceptFriendRequests => 'قبول طلبات الصداقة تلقائياً';

  @override
  String get autoAcceptFriendRequestsDesc => 'قبول طلبات الصداقة الواردة تلقائياً';

  @override
  String get autoAcceptGroupInvites => 'قبول دعوات المجموعة تلقائياً';

  @override
  String get autoAcceptGroupInvitesDesc => 'قبول دعوات المجموعة الواردة تلقائياً';

  @override
  String get bootstrapNodes => 'عقد Bootstrap';

  @override
  String get currentNode => 'العقدة الحالية';

  @override
  String get viewAndTestNodes => 'عرض واختبار العقد';

  @override
  String get currentlyOnlineNoReconnect => 'متصل حالياً، لا حاجة لإعادة الاتصال';

  @override
  String get addOrCreateGroup => 'إضافة / إنشاء مجموعة';

  @override
  String get joinGroupById => 'انضم إلى المجموعة بالمعرف';

  @override
  String get enterGroupId => 'يرجى إدخال معرف المجموعة';

  @override
  String get requestMessage => 'رسالة الطلب';

  @override
  String get groupAlias => 'اسم المجموعة المحلي (اختياري)';

  @override
  String get joinAction => 'إرسال طلب الانضمام';

  @override
  String get joinSuccess => 'تم إرسال طلب الانضمام';

  @override
  String get joinFailed => 'فشل الانضمام إلى المجموعة';

  @override
  String get groupName => 'اسم المجموعة';

  @override
  String get enterGroupName => 'يرجى إدخال اسم المجموعة';

  @override
  String get createAction => 'إنشاء مجموعة';

  @override
  String get createSuccess => 'تم إنشاء المجموعة';

  @override
  String get createFailed => 'فشل إنشاء المجموعة';

  @override
  String get createdGroupId => 'معرف المجموعة الجديدة';

  @override
  String get copyId => 'نسخ المعرف';

  @override
  String get copied => 'تم النسخ إلى الحافظة';

  @override
  String get addFailed => 'فشل الإضافة';

  @override
  String get enterId => 'يرجى إدخال Tox ID';

  @override
  String get invalidLength => 'يجب أن يكون المعرف 64 أو 76 حرفاً سداسياً عشرياً';

  @override
  String get invalidCharacters => 'يمكن أن يحتوي فقط على أحرف سداسية عشرية';

  @override
  String get paste => 'لصق';

  @override
  String get addContactHint => 'أدخل Tox ID للصديق (64 أو 76 حرفاً سداسياً عشرياً).';

  @override
  String get verificationMessage => 'رسالة التحقق';

  @override
  String get defaultFriendRequestMessage => 'مرحباً، أود إضافتك كصديق.';

  @override
  String get friendRequestMessageTooLong => 'لا يمكن أن تتجاوز رسالة طلب الصداقة 921 حرفاً';

  @override
  String get enterMessage => 'يرجى إدخال رسالة';

  @override
  String get autoAcceptedNewFriendRequest => 'تم قبول طلب الصداقة الجديد تلقائياً';

  @override
  String get scanQrCodeToAddContact => 'امسح رمز QR لإضافتي كجهة اتصال';

  @override
  String get generateCard => 'إنشاء بطاقة';

  @override
  String get customCardText => 'نص البطاقة المخصص';

  @override
  String get userId => 'معرف المستخدم';

  @override
  String get saveImage => 'حفظ الصورة';

  @override
  String get copy => 'نسخ';

  @override
  String get fileCopiedSuccessfully => 'تم نسخ الملف بنجاح';

  @override
  String get idCopiedToClipboard => 'تم نسخ المعرف إلى الحافظة';

  @override
  String get establishingEncryptedChannel => 'جاري إنشاء قناة مشفرة...';

  @override
  String get checkingUserInfo => 'جارٍ التحقق من معلومات المستخدم...';

  @override
  String get initializingService => 'جارٍ تهيئة الخدمة...';

  @override
  String get loggingIn => 'جارٍ تسجيل الدخول...';

  @override
  String get initializingSDK => 'جارٍ تهيئة SDK...';

  @override
  String get updatingProfile => 'جارٍ تحديث الملف الشخصي...';

  @override
  String get initializationCompleted => 'اكتملت التهيئة!';

  @override
  String get loadingFriends => 'جارٍ تحميل معلومات الأصدقاء...';

  @override
  String get inProgress => 'قيد التنفيذ';

  @override
  String get completed => 'مكتمل';

  @override
  String get personalCard => 'البطاقة الشخصية';

  @override
  String get appTitle => 'toxee';

  @override
  String get startChat => 'بدء الدردشة';

  @override
  String get pasteServerUserId => 'الصق معرف المستخدم للخادم هنا';

  @override
  String get groupProfile => 'ملف المجموعة';

  @override
  String get invalidGroupId => 'معرف المجموعة غير صالح';

  @override
  String maintainer(String maintainer) {
    return 'المشرف: $maintainer';
  }

  @override
  String get success => 'نجح';

  @override
  String get failed => 'فشل';

  @override
  String error(String error) {
    return 'خطأ: $error';
  }

  @override
  String get saved => 'تم الحفظ';

  @override
  String failedToSave(String error) {
    return 'فشل الحفظ: $error';
  }

  @override
  String copyFailed(String error) {
    return 'فشل النسخ: $error';
  }

  @override
  String failedToUpdateAvatar(String error) {
    return 'فشل تحديث الصورة الرمزية: $error';
  }

  @override
  String get failedToLoadQr => 'فشل تحميل رمز QR';

  @override
  String get helloFromToxee => 'تحية من toxee';

  @override
  String attachFailed(String error) {
    return 'فشل المرفق: $error';
  }

  @override
  String get autoFriendRequestFromToxee => 'طلب صداقة تلقائي من toxee';

  @override
  String get reconnect => 'إعادة الاتصال';

  @override
  String get reconnectConfirmMessage => 'سيتم إعادة الاتصال باستخدام عقدة Bootstrap المحددة. هل تريد المتابعة؟';

  @override
  String get reconnectedWaiting => 'تم تسجيل الدخول مرة أخرى، في انتظار الاتصال...';

  @override
  String get reconnectWithThisNode => 'إعادة الاتصال بهذه العقدة';

  @override
  String get friendOfflineCannotSendFile => 'الصديق غير متصل. لا يمكن إرسال الملف. يرجى الانتظار حتى يكون متصلاً.';

  @override
  String get friendOfflineSendCardFailed => 'الصديق غير متصل. فشل إرسال البطاقة الشخصية.';

  @override
  String get friendOfflineSendImageFailed => 'الصديق غير متصل. فشل إرسال الصورة.';

  @override
  String get friendOfflineSendVideoFailed => 'الصديق غير متصل. فشل إرسال الفيديو.';

  @override
  String get friendOfflineSendFileFailed => 'الصديق غير متصل. فشل إرسال الملف.';

  @override
  String get userNotInFriendList => 'هذا المستخدم غير موجود في قائمة أصدقائك.';

  @override
  String sendFailed(String error) {
    return 'فشل الإرسال: $error';
  }

  @override
  String get myId => 'معرفي';

  @override
  String get sendPersonalCardToGroup => 'إرسال البطاقة الشخصية إلى المجموعة';

  @override
  String get personalCardSent => 'تم إرسال البطاقة الشخصية';

  @override
  String get sentPersonalCardToGroup => 'تم إرسال البطاقة الشخصية إلى المجموعة';

  @override
  String get bootstrapNodesTitle => 'عقد Bootstrap';

  @override
  String get refresh => 'تحديث';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String lastPing(String seconds) {
    return 'آخر ping: منذ $seconds ثانية';
  }

  @override
  String get testNode => 'اختبار العقدة';

  @override
  String get deleteAccount => 'حذف الحساب';

  @override
  String get deleteAccountConfirmMessage => 'سيتم حذف حسابك وجميع البيانات نهائياً ولا يمكن استردادها. يرجى المتابعة بحذر.';

  @override
  String get delete => 'حذف';

  @override
  String get deleteAccountEnterPasswordToConfirm => 'أدخل كلمة مرور حسابك لتأكيد الحذف.';

  @override
  String get deleteAccountTypeWordToConfirm => 'أدخل الكلمة الإنجليزية المعروضة أدناه بشكل صحيح لتأكيد الحذف.';

  @override
  String deleteAccountConfirmWordPrompt(String word) {
    return 'أدخل الكلمة التالية في المربع أدناه للتأكيد: $word';
  }

  @override
  String get deleteAccountWrongWord => 'الكلمة التي أدخلتها غير صحيحة.';

  @override
  String get applications => 'التطبيقات';

  @override
  String get applicationsComingSoon => 'المزيد من التطبيقات قريباً...';

  @override
  String get notificationSound => 'صوت الإشعارات';

  @override
  String get notificationSoundDesc => 'تشغيل الصوت عند تلقي رسائل جديدة وطلبات الصداقة وطلبات المجموعة';

  @override
  String get downloadsDirectory => 'مجلد التنزيلات';

  @override
  String get selectDownloadsDirectory => 'اختر مجلد التنزيلات';

  @override
  String get changeDownloadsDirectory => 'تغيير مجلد التنزيلات';

  @override
  String get downloadsDirectoryDesc => 'قم بتعيين المجلد الافتراضي لتنزيل الملفات. سيتم حفظ الملفات والصوتيات والفيديوهات المستلمة في هذا المجلد.';

  @override
  String get downloadsDirectorySet => 'تم تعيين مجلد التنزيلات';

  @override
  String get downloadsDirectoryReset => 'تم إعادة تعيين مجلد التنزيلات إلى الافتراضي';

  @override
  String get failedToSelectDirectory => 'فشل في اختيار المجلد';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get autoDownloadSizeLimit => 'حد حجم التنزيل التلقائي';

  @override
  String get sizeLimitInMB => 'حد الحجم (MB)';

  @override
  String get autoDownloadSizeLimitDesc => 'سيتم تنزيل الملفات الأصغر من هذا الحجم وجميع الصور تلقائياً. تتطلب الملفات الأكبر من هذا الحجم التنزيل اليدوي عبر زر التنزيل.';

  @override
  String get autoDownloadSizeLimitSet => 'تم تعيين حد حجم التنزيل التلقائي إلى';

  @override
  String get invalidSizeLimit => 'حد حجم غير صالح، يرجى إدخال رقم بين 1 و 10000';

  @override
  String get save => 'حفظ';

  @override
  String get routeSelection => 'اختيار المسار';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get canOnlySelectOnlineNode => 'يمكن اختيار العقد المتصلة فقط';

  @override
  String get canOnlySelectTestedNode => 'يمكن اختيار العقد التي تم اختبارها بنجاح فقط، يرجى اختبار العقدة أولاً';

  @override
  String get switchNode => 'تبديل العقدة';

  @override
  String switchNodeConfirm(String node) {
    return 'هل أنت متأكد من أنك تريد التبديل إلى العقدة $node؟ يلزم إعادة الاتصال بعد التبديل.';
  }

  @override
  String get nodeSwitched => 'تم تبديل العقدة، جاري إعادة الاتصال...';

  @override
  String get selectThisNode => 'اختيار هذه العقدة';

  @override
  String nodeSwitchFailed(String error) {
    return 'فشل تبديل العقدة: $error';
  }

  @override
  String get ircChannelApp => 'قناة IRC';

  @override
  String get ircChannelAppDesc => 'ربط قنوات IRC بمجموعات Tox لمزامنة الرسائل';

  @override
  String get install => 'تثبيت';

  @override
  String get uninstall => 'إلغاء التثبيت';

  @override
  String get ircAppInstalled => 'تم تثبيت تطبيق قناة IRC';

  @override
  String get ircAppUninstalled => 'تم إلغاء تثبيت تطبيق قناة IRC';

  @override
  String get uninstallIrcApp => 'إلغاء تثبيت تطبيق قناة IRC';

  @override
  String get uninstallIrcAppConfirm => 'هل أنت متأكد أنك تريد إلغاء تثبيت تطبيق قناة IRC؟ سيتم إزالة جميع قنوات IRC وستغادر جميع مجموعات IRC.';

  @override
  String get addIrcChannel => 'إضافة قناة';

  @override
  String get ircChannels => 'قنوات IRC';

  @override
  String get ircServerConfig => 'إعدادات خادم IRC';

  @override
  String get ircServer => 'الخادم';

  @override
  String get ircPort => 'المنفذ';

  @override
  String get ircUseSasl => 'استخدام مصادقة SASL';

  @override
  String get ircUseSaslDesc => 'استخدام المفتاح العام لـ Tox لمصادقة SASL (يتطلب تسجيل NickServ)';

  @override
  String get ircServerRequired => 'عنوان خادم IRC مطلوب';

  @override
  String get ircConfigSaved => 'تم حفظ إعدادات IRC';

  @override
  String ircChannelAdded(String channel) {
    return 'تمت إضافة قناة IRC: $channel';
  }

  @override
  String get ircChannelAddFailed => 'فشل إضافة قناة IRC';

  @override
  String ircChannelRemoved(String channel) {
    return 'تمت إزالة قناة IRC: $channel';
  }

  @override
  String get removeIrcChannel => 'إزالة قناة IRC';

  @override
  String removeIrcChannelConfirm(String channel) {
    return 'هل أنت متأكد أنك تريد إزالة $channel؟ ستغادر المجموعة المقابلة.';
  }

  @override
  String get remove => 'إزالة';

  @override
  String get joinIrcChannel => 'الانضمام إلى قناة IRC';

  @override
  String get ircChannelName => 'اسم قناة IRC';

  @override
  String get ircChannelHint => '#قناة';

  @override
  String get ircChannelDesc => 'أدخل اسم قناة IRC (مثلاً: #channel). سيتم إنشاء مجموعة Tox لهذه القناة.';

  @override
  String get enterIrcChannel => 'يرجى إدخال اسم قناة IRC';

  @override
  String get invalidIrcChannel => 'يجب أن تبدأ قناة IRC بـ # أو &';

  @override
  String get join => 'انضمام';

  @override
  String get ircAppNotInstalled => 'يرجى تثبيت تطبيق قناة IRC من صفحة التطبيقات أولاً';

  @override
  String get ircChannelPassword => 'كلمة مرور القناة';

  @override
  String get ircChannelPasswordHint => 'اتركه فارغاً إذا لم تكن هناك كلمة مرور';

  @override
  String get ircCustomNickname => 'اسم مستعار مخصص لـ IRC';

  @override
  String get ircCustomNicknameHint => 'اتركه فارغاً لاستخدام الاسم المستعار المُنشأ تلقائياً';

  @override
  String deleteAccountFailed(String error) {
    return 'فشل حذف الحساب: $error';
  }

  @override
  String get directorySelectionNotSupported => 'اختيار المجلد غير مدعوم على هذه المنصة';

  @override
  String failedToSendFriendRequest(String error) {
    return 'فشل إرسال طلب الصداقة: $error';
  }

  @override
  String get fileDoesNotExist => 'الملف غير موجود';

  @override
  String get fileIsEmpty => 'الملف فارغ';

  @override
  String failedToSendFile(String label, String error) {
    return 'فشل إرسال $label: $error';
  }

  @override
  String get noReceivers => 'لا يوجد مستقبلون بعد';

  @override
  String messageReceivers(String count) {
    return 'مستقبلو الرسائل ($count)';
  }

  @override
  String get close => 'إغلاق';

  @override
  String get nodeNotTestedWarning => 'ملاحظة: لم يتم اختبار هذه العقدة وقد لا تكون قابلة للاتصال.';

  @override
  String get nodeTestFailedWarning => 'ملاحظة: فشل اختبار هذه العقدة وقد لا تكون قابلة للاتصال.';

  @override
  String get nicknameTooLong => 'الاسم المستعار طويل جداً';

  @override
  String get nicknameCannotBeEmpty => 'الاسم المستعار لا يمكن أن يكون فارغاً';

  @override
  String get statusMessageTooLong => 'رسالة الحالة طويلة جداً';

  @override
  String get manualNodeInput => 'إدخال العقدة يدوياً';

  @override
  String get nodeHost => 'الخادم';

  @override
  String get nodePort => 'المنفذ';

  @override
  String get nodePublicKey => 'المفتاح العام';

  @override
  String get setAsCurrentNode => 'تعيين كعقدة حالية';

  @override
  String get nodeTestSuccess => 'نجح اختبار العقدة';

  @override
  String get nodeTestFailed => 'فشل اختبار العقدة';

  @override
  String get invalidNodeInfo => 'يرجى إدخال معلومات عقدة صالحة (الخادم والمنفذ والمفتاح العام)';

  @override
  String get nodeSetSuccess => 'تم تعيين العقدة كعقدة حالية بنجاح';

  @override
  String get bootstrapNodeMode => 'وضع عقدة Bootstrap';

  @override
  String get manualMode => 'يدوي';

  @override
  String get autoMode => 'تلقائي (جلب من الويب)';

  @override
  String get manualModeDesc => 'تحديد معلومات عقدة Bootstrap يدوياً';

  @override
  String get autoModeDesc => 'جلب واستخدام عقد Bootstrap تلقائياً من الويب';

  @override
  String get autoModeDescPrefix => 'جلب واستخدام عقد Bootstrap تلقائياً من ';

  @override
  String get lanMode => 'وضع LAN';

  @override
  String get lanModeDesc => 'استخدام خدمة Bootstrap للشبكة المحلية';

  @override
  String get startLocalBootstrapService => 'بدء خدمة Bootstrap المحلية';

  @override
  String get stopLocalBootstrapService => 'إيقاف خدمة Bootstrap المحلية';

  @override
  String get bootstrapServiceStatus => 'حالة الخدمة';

  @override
  String get serviceRunning => 'قيد التشغيل';

  @override
  String get serviceStopped => 'متوقف';

  @override
  String get scanLanBootstrapServices => 'فحص خدمات Bootstrap للشبكة المحلية';

  @override
  String get scanLanBootstrapServicesTitle => 'خدمات Bootstrap للشبكة المحلية';

  @override
  String get scanPort => 'منفذ الفحص';

  @override
  String get startScan => 'بدء الفحص';

  @override
  String scanningAliveIPs(int current, int total) {
    return 'جارٍ فحص عناوين IP النشطة: $current/$total';
  }

  @override
  String probingBootstrapServices(int current, int total) {
    return 'جارٍ التحقق من خدمات Bootstrap: $current/$total';
  }

  @override
  String get scanning => 'جارٍ الفحص...';

  @override
  String get probing => 'جارٍ التحقق...';

  @override
  String aliveIPsFound(int count) {
    return 'تم العثور على عناوين IP نشطة: $count';
  }

  @override
  String get noAliveIPsFound => 'لم يتم العثور على عناوين IP نشطة';

  @override
  String get bootstrapServiceFound => 'تم العثور على خدمة Bootstrap';

  @override
  String get noBootstrapService => 'لم يتم العثور على خدمة Bootstrap';

  @override
  String get noServicesFound => 'لم يتم العثور على خدمات';

  @override
  String get useAsBootstrapNode => 'استخدام كعقدة Bootstrap';

  @override
  String get ipAddress => 'عنوان IP';

  @override
  String get probeStatus => 'حالة التحقق';

  @override
  String get probeSingleIP => 'التحقق من عنوان IP هذا';

  @override
  String probingIP(String ip) {
    return 'جارٍ التحقق من $ip...';
  }

  @override
  String get refreshAliveIPs => 'تحديث عناوين IP النشطة';

  @override
  String get aliveIPsList => 'قائمة عناوين IP النشطة';

  @override
  String get notProbedYet => 'لم يتم التحقق بعد';

  @override
  String get probeSuccess => 'تم العثور على خدمة Bootstrap';

  @override
  String get probeFailed => 'لم يتم العثور على خدمة Bootstrap';

  @override
  String bootstrapServiceRunning(String ip, int port) {
    return 'خدمة Bootstrap قيد التشغيل: $ip:$port';
  }

  @override
  String get logOut => 'تسجيل الخروج';

  @override
  String get logOutConfirm => 'هل أنت متأكد أنك تريد تسجيل الخروج؟';

  @override
  String get autoLogin => 'تسجيل الدخول التلقائي';

  @override
  String get autoLoginEnabled => 'تسجيل الدخول التلقائي: مفعّل';

  @override
  String get autoLoginDisabled => 'تسجيل الدخول التلقائي: معطّل';

  @override
  String get autoLoginDesc => 'بعد التفعيل، سيتم تسجيل الدخول تلقائياً عند بدء التطبيق.';

  @override
  String get disable => 'تعطيل';

  @override
  String get enable => 'تفعيل';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get register => 'التسجيل';

  @override
  String get registerNewAccount => 'تسجيل حساب جديد';

  @override
  String get unnamedAccount => 'حساب بدون اسم';

  @override
  String get accountInfo => 'معلومات الحساب';

  @override
  String get accountManagement => 'إدارة الحساب';

  @override
  String get localAccounts => 'الحسابات المحلية';

  @override
  String showMore(int count) {
    return 'عرض $count المزيد';
  }

  @override
  String get showLess => 'إخفاء';

  @override
  String get current => 'الحالي';

  @override
  String get lastLogin => 'آخر تسجيل دخول';

  @override
  String get switchAccount => 'تبديل الحساب';

  @override
  String get exportAccount => 'تصدير الحساب';

  @override
  String get exportOptionProfileTox => 'Profile (.tox)';

  @override
  String get exportOptionProfileToxSubtitle => 'qTox compatible, profile only';

  @override
  String get exportOptionFullBackup => 'Full Backup (.zip)';

  @override
  String get exportOptionFullBackupSubtitle => 'Profile + chat history + settings';

  @override
  String get importAccount => 'استيراد الحساب';

  @override
  String get setPassword => 'تعيين كلمة المرور';

  @override
  String get changePassword => 'تغيير كلمة المرور';

  @override
  String get enterPasswordToExport => 'أدخل كلمة المرور لتصدير الحساب';

  @override
  String get enterPasswordToImport => 'أدخل كلمة المرور لاستيراد الحساب';

  @override
  String enterPasswordForAccount(String nickname) {
    return 'أدخل كلمة مرور الحساب \"$nickname\"';
  }

  @override
  String get invalidPassword => 'كلمة المرور غير صحيحة';

  @override
  String accountExportedSuccessfully(String filePath) {
    return 'تم تصدير الحساب بنجاح إلى: $filePath';
  }

  @override
  String get accountImportedSuccessfully => 'تم استيراد الحساب بنجاح';

  @override
  String get passwordSetSuccessfully => 'تم تعيين كلمة المرور بنجاح';

  @override
  String get passwordRemoved => 'تم إزالة كلمة المرور';

  @override
  String failedToSwitchAccount(String error) {
    return 'فشل تبديل الحساب: $error';
  }

  @override
  String failedToExportAccount(String error) {
    return 'فشل تصدير الحساب: $error';
  }

  @override
  String failedToImportAccount(String error) {
    return 'فشل استيراد الحساب: $error';
  }

  @override
  String failedToSetPassword(String error) {
    return 'فشل تعيين كلمة المرور: $error';
  }

  @override
  String get noAccountToExport => 'لا يوجد حساب للتصدير';

  @override
  String get noAccountSelected => 'لم يتم اختيار حساب';

  @override
  String get accountAlreadyExists => 'الحساب موجود بالفعل';

  @override
  String get accountAlreadyExistsMessage => 'يوجد حساب بهذا المعرف بالفعل. هل تريد تحديثه؟';

  @override
  String get update => 'تحديث';

  @override
  String switchAccountConfirm(String nickname) {
    return 'هل أنت متأكد أنك تريد التبديل إلى \"$nickname\"؟ سيتم تسجيل الخروج من الحساب الحالي.';
  }

  @override
  String get savedAccounts => 'الحسابات المحفوظة';

  @override
  String get tapToSelectDoubleTapToLogin => 'اضغط للاختيار، اضغط مرتين لتسجيل الدخول السريع';

  @override
  String get tapToLogIn => 'اضغط لتسجيل الدخول';

  @override
  String get switchToThisAccount => 'التبديل إلى هذا الحساب';

  @override
  String get password => 'كلمة المرور';

  @override
  String get newPassword => 'كلمة المرور الجديدة';

  @override
  String get confirmPassword => 'تأكيد كلمة المرور';

  @override
  String get leaveEmptyToRemovePassword => 'اتركه فارغاً لإزالة كلمة المرور';

  @override
  String get passwordsDoNotMatch => 'كلمات المرور غير متطابقة';

  @override
  String get never => 'أبداً';

  @override
  String get justNow => 'الآن';

  @override
  String daysAgo(int count, String plural) {
    return 'منذ $count يوم$plural';
  }

  @override
  String hoursAgo(int count, String plural) {
    return 'منذ $count ساعة$plural';
  }

  @override
  String minutesAgo(int count, String plural) {
    return 'منذ $count دقيقة$plural';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => 'هذا الحساب مسجل دخول بالفعل';

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
    return 'تم العثور على $contacts جهة اتصال و$groups مجموعة و$messages سلسلة رسائل';
  }

  @override
  String get searchFailed => 'فشل البحث، عرض نتائج جزئية';

  @override
  String get callVideoCall => 'مكالمة فيديو';

  @override
  String get callAudioCall => 'مكالمة صوتية';

  @override
  String get callReject => 'رفض';

  @override
  String get callAccept => 'قبول';

  @override
  String get callRemoteVideo => 'فيديو الطرف الآخر';

  @override
  String get callUnmute => 'إلغاء كتم الصوت';

  @override
  String get callMute => 'كتم الصوت';

  @override
  String get callVideoOff => 'إيقاف الفيديو';

  @override
  String get callVideoOn => 'تشغيل الفيديو';

  @override
  String get callSpeakerOff => 'إيقاف السماعة';

  @override
  String get callSpeakerOn => 'تشغيل السماعة';

  @override
  String get callHangUp => 'إنهاء المكالمة';

  @override
  String get callEnded => 'انتهت المكالمة';

  @override
  String get callPermissionMicrophoneRequired => 'يلزم إذن الميكروفون لمتابعة المكالمة.';

  @override
  String get callPermissionCameraRequired => 'يلزم إذن الكاميرا لمتابعة المكالمة.';

  @override
  String get callPermissionMicrophoneCameraRequired => 'يلزم إذن الميكروفون والكاميرا لمتابعة المكالمة.';

  @override
  String get callAudioInterrupted => 'تم تغيير إخراج الصوت أو انقطاعه أثناء المكالمة.';

  @override
  String get callCalling => 'جارٍ الاتصال...';

  @override
  String get callMinimize => 'تصغير';

  @override
  String get callReturnToCall => 'العودة إلى المكالمة';

  @override
  String get callQualityGood => 'اتصال جيد';

  @override
  String get callQualityMedium => 'اتصال مقبول';

  @override
  String get callQualityPoor => 'اتصال ضعيف';

  @override
  String get callQualityUnknown => '—';

  @override
  String get callQualityLabel => 'جودة المكالمة';

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
}
