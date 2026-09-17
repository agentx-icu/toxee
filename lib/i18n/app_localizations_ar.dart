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
  String get searchConversations =>
      'البحث بالاسم المستعار / المجموعة / الرسالة';

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
  String get general => 'عام';

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
  String get autoAcceptFriendRequestsDesc =>
      'قبول طلبات الصداقة الواردة تلقائياً';

  @override
  String get autoAcceptGroupInvites => 'قبول دعوات المجموعة تلقائياً';

  @override
  String get autoAcceptGroupInvitesDesc =>
      'قبول دعوات المجموعة الواردة تلقائياً';

  @override
  String get bootstrapNodes => 'عقد Bootstrap';

  @override
  String get currentNode => 'العقدة الحالية';

  @override
  String get viewAndTestNodes => 'عرض واختبار العقد';

  @override
  String get currentlyOnlineNoReconnect =>
      'متصل حالياً، لا حاجة لإعادة الاتصال';

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
  String get joinQueued =>
      'غير متصل — سيتم إرسال طلب الانضمام عند إعادة الاتصال';

  @override
  String get offlineBanner =>
      'غير متصل — سيتم وضع عمليات المجموعة في قائمة الانتظار ومعالجتها عند إعادة الاتصال.';

  @override
  String get groupType => 'نوع المجموعة';

  @override
  String get publicGroup => 'عام';

  @override
  String get privateGroup => 'خاص';

  @override
  String get publicGroupHint =>
      'مجموعة عامة — قابلة للاكتشاف على DHT ويمكن لأي شخص لديه معرف المحادثة الانضمام إليها.';

  @override
  String get privateGroupHint =>
      'مجموعة خاصة — بالدعوة فقط، غير معلنة على DHT.';

  @override
  String get conferenceHint =>
      'مؤتمر قديم — بروتوكول قديم، بدون أدوار أو استمرارية.';

  @override
  String get searchHintBody => 'ابحث عن جهات الاتصال والمجموعات والرسائل';

  @override
  String get noResultsFoundHint => 'جرّب كلمة مفتاحية أقصر أو تحقق من الإملاء';

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
  String get invalidLength => 'طول المعرف غير صالح';

  @override
  String get invalidCharacters => 'يمكن أن يحتوي فقط على أحرف سداسية عشرية';

  @override
  String get paste => 'لصق';

  @override
  String get addContactHint => 'أدخل عنوان Tox الخاص بالطرف الآخر.';

  @override
  String get addFriendInvalidToxIdHint =>
      'يجب أن يكون عنوان Tox 76 حرفاً سداسياً عشرياً';

  @override
  String get verificationMessage => 'رسالة التحقق';

  @override
  String get defaultFriendRequestMessage => 'مرحباً، أود إضافتك كصديق.';

  @override
  String get friendRequestMessageTooLong =>
      'لا يمكن أن تتجاوز رسالة طلب الصداقة 921 حرفاً';

  @override
  String get enterMessage => 'يرجى إدخال رسالة';

  @override
  String get noGroupMembers => 'لا يوجد أعضاء بعد';

  @override
  String get autoAcceptedNewFriendRequest =>
      'تم قبول طلب الصداقة الجديد تلقائياً';

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
  String get reconnectConfirmMessage =>
      'سيتم إعادة الاتصال باستخدام عقدة Bootstrap المحددة. هل تريد المتابعة؟';

  @override
  String get reconnectedWaiting =>
      'تم تسجيل الدخول مرة أخرى، في انتظار الاتصال...';

  @override
  String get reconnectWithThisNode => 'إعادة الاتصال بهذه العقدة';

  @override
  String get friendOfflineCannotSendFile =>
      'الصديق غير متصل. لا يمكن إرسال الملف. يرجى الانتظار حتى يكون متصلاً.';

  @override
  String get friendOfflineSendCardFailed =>
      'الصديق غير متصل. فشل إرسال البطاقة الشخصية.';

  @override
  String get friendOfflineSendImageFailed =>
      'الصديق غير متصل. فشل إرسال الصورة.';

  @override
  String get friendOfflineSendVideoFailed =>
      'الصديق غير متصل. فشل إرسال الفيديو.';

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
  String get deleteAccountConfirmMessage =>
      'سيتم حذف حسابك وجميع البيانات نهائياً ولا يمكن استردادها. يرجى المتابعة بحذر.';

  @override
  String get delete => 'حذف';

  @override
  String get deleteAccountEnterPasswordToConfirm =>
      'أدخل كلمة مرور حسابك لتأكيد الحذف.';

  @override
  String get deleteAccountTypeWordToConfirm =>
      'أدخل الكلمة الإنجليزية المعروضة أدناه بشكل صحيح لتأكيد الحذف.';

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
  String get notificationSoundDesc =>
      'تشغيل الصوت عند تلقي رسائل جديدة وطلبات الصداقة وطلبات المجموعة';

  @override
  String get downloadsDirectory => 'مجلد التنزيلات';

  @override
  String get selectDownloadsDirectory => 'اختر مجلد التنزيلات';

  @override
  String get changeDownloadsDirectory => 'تغيير مجلد التنزيلات';

  @override
  String get downloadsDirectoryDesc =>
      'قم بتعيين المجلد الافتراضي لتنزيل الملفات. سيتم حفظ الملفات والصوتيات والفيديوهات المستلمة في هذا المجلد.';

  @override
  String get downloadsDirectorySet => 'تم تعيين مجلد التنزيلات';

  @override
  String get downloadsDirectoryReset =>
      'تم إعادة تعيين مجلد التنزيلات إلى الافتراضي';

  @override
  String get failedToSelectDirectory => 'فشل في اختيار المجلد';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get autoDownloadSizeLimit => 'حد حجم التنزيل التلقائي';

  @override
  String get sizeLimitInMB => 'حد الحجم (MB)';

  @override
  String get autoDownloadSizeLimitDesc =>
      'سيتم تنزيل الملفات الأصغر من هذا الحجم وجميع الصور تلقائياً. تتطلب الملفات الأكبر من هذا الحجم التنزيل اليدوي عبر زر التنزيل.';

  @override
  String get autoDownloadSizeLimitSet => 'تم تعيين حد حجم التنزيل التلقائي إلى';

  @override
  String get invalidSizeLimit =>
      'حد حجم غير صالح، يرجى إدخال رقم بين 1 و 10000';

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
  String get canOnlySelectTestedNode =>
      'أرسل طلب تمهيد بنجاح قبل اختيار هذه العقدة';

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
  String get uninstallIrcAppConfirm =>
      'هل أنت متأكد أنك تريد إلغاء تثبيت تطبيق قناة IRC؟ سيتم إزالة جميع قنوات IRC وستغادر جميع مجموعات IRC.';

  @override
  String get addIrcChannel => 'إضافة قناة';

  @override
  String get ircChannels => 'قنوات IRC';

  @override
  String get ircStatusDisconnected => 'غير متصل';

  @override
  String get ircStatusConnecting => 'جارٍ الاتصال';

  @override
  String get ircStatusConnected => 'متصل';

  @override
  String get ircStatusAuthenticating => 'جارٍ المصادقة';

  @override
  String get ircStatusReconnecting => 'جارٍ إعادة الاتصال';

  @override
  String get ircStatusError => 'خطأ';

  @override
  String get ircServerConfig => 'إعدادات خادم IRC';

  @override
  String get ircServer => 'الخادم';

  @override
  String get ircPort => 'المنفذ';

  @override
  String get ircUseSasl => 'استخدام مصادقة SASL';

  @override
  String get ircUseSaslDesc =>
      'استخدام المفتاح العام لـ Tox لمصادقة SASL (يتطلب تسجيل NickServ)';

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
  String ircChannelAddedNotConnected(String channel) {
    return 'تمت إضافة القناة $channel، لكن تعذّر إنشاء اتصال IRC';
  }

  @override
  String get ircAppInstalledNoLibrary =>
      'تم تثبيت تطبيق IRC، لكن اتصال IRC المباشر غير متاح على هذا الجهاز';

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
  String get ircChannelDesc =>
      'أدخل اسم قناة IRC (مثلاً: #channel). سيتم إنشاء مجموعة Tox لهذه القناة.';

  @override
  String get enterIrcChannel => 'يرجى إدخال اسم قناة IRC';

  @override
  String get invalidIrcChannel => 'يجب أن تبدأ قناة IRC بـ # أو &';

  @override
  String get join => 'انضمام';

  @override
  String get ircAppNotInstalled =>
      'يرجى تثبيت تطبيق قناة IRC من صفحة التطبيقات أولاً';

  @override
  String get ircChannelPassword => 'كلمة مرور القناة';

  @override
  String get ircChannelPasswordHint => 'اتركه فارغاً إذا لم تكن هناك كلمة مرور';

  @override
  String get ircCustomNickname => 'اسم مستعار مخصص لـ IRC';

  @override
  String get ircCustomNicknameHint =>
      'اتركه فارغاً لاستخدام الاسم المستعار المُنشأ تلقائياً';

  @override
  String deleteAccountFailed(String error) {
    return 'فشل حذف الحساب: $error';
  }

  @override
  String get directorySelectionNotSupported =>
      'اختيار المجلد غير مدعوم على هذه المنصة';

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
  String get nodeNotTestedWarning => 'لم يتم اختبار هذه العقدة بعد.';

  @override
  String get nodeTestFailedWarning => 'لم تستجب هذه العقدة؛ قد تكون غير متاحة.';

  @override
  String get nodeTestInconclusiveWarning =>
      'تعذّر فحص هذه العقدة من هذا الجهاز، لذا لا يُعرف شيء عن حالتها.';

  @override
  String get nicknameTooLong => 'الاسم المستعار طويل جداً';

  @override
  String get nicknameCannotBeEmpty => 'الاسم المستعار لا يمكن أن يكون فارغاً';

  @override
  String get statusMessageTooLong => 'رسالة الحالة طويلة جداً';

  @override
  String get passwordStrengthWeak => 'ضعيفة';

  @override
  String get passwordStrengthFair => 'مقبولة';

  @override
  String get passwordStrengthGood => 'جيدة';

  @override
  String get passwordStrengthStrong => 'قوية';

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
  String get nodeTestSuccess => 'العقدة متاحة';

  @override
  String get nodeTestUdpUnavailable =>
      'يتطلب اختبار العقدة UDP؛ يعمل هذا الجهاز عبر TCP فقط';

  @override
  String get nodeTestFailed => 'العقدة غير متاحة';

  @override
  String get nodeTestUnavailable => 'اختبار العقدة غير متاح على هذا الجهاز';

  @override
  String get failedToLoadBootstrapNodes => 'فشل تحميل عُقد التمهيد';

  @override
  String get failedToStartBootstrapService => 'فشل بدء خدمة الإقلاع';

  @override
  String get invalidNodeInfo =>
      'يرجى إدخال معلومات عقدة صالحة (الخادم والمنفذ والمفتاح العام)';

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
  String get autoLoginDesc =>
      'بعد التفعيل، سيتم تسجيل الدخول تلقائياً عند بدء التطبيق.';

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
  String get exportOptionProfileTox => 'الملف الشخصي (.tox)';

  @override
  String get exportOptionProfileToxSubtitle =>
      'متوافق مع qTox، الملف الشخصي فقط';

  @override
  String get exportOptionFullBackup => 'نسخة احتياطية كاملة (.zip)';

  @override
  String get exportOptionFullBackupSubtitle =>
      'الملف الشخصي + سجل الدردشة + الإعدادات';

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
  String get accountAlreadyExistsMessage =>
      'يوجد حساب بهذا المعرف بالفعل. هل تريد تحديثه؟';

  @override
  String get update => 'تحديث';

  @override
  String switchAccountConfirm(String nickname) {
    return 'هل أنت متأكد أنك تريد التبديل إلى \"$nickname\"؟ سيتم تسجيل الخروج من الحساب الحالي.';
  }

  @override
  String get savedAccounts => 'الحسابات المحفوظة';

  @override
  String get tapToSelectDoubleTapToLogin =>
      'اضغط للاختيار، اضغط مرتين لتسجيل الدخول السريع';

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
  String daysAgo(int count) {
    return 'منذ $count يوم';
  }

  @override
  String hoursAgo(int count) {
    return 'منذ $count ساعة';
  }

  @override
  String minutesAgo(int count) {
    return 'منذ $count دقيقة';
  }

  @override
  String get thisAccountIsAlreadyLoggedIn => 'هذا الحساب مسجل دخول بالفعل';

  @override
  String get upgradeRequiredTitle => 'يرجى تحديث التطبيق';

  @override
  String upgradeRequiredMessage(int storedVersion, int currentVersion) {
    return 'تم حفظ بياناتك بواسطة إصدار أحدث من التطبيق (إصدار البيانات: $storedVersion). يدعم هذا الإصدار حتى $currentVersion. يرجى تثبيت آخر تحديث للمتابعة.';
  }

  @override
  String get upgradeAppTitle => 'toxee';

  @override
  String get hide => 'إخفاء';

  @override
  String get pressBackAgainToExit => 'اضغط رجوع مرة أخرى للخروج';

  @override
  String get startupFailed => 'فشل بدء التشغيل';

  @override
  String get unknownError => 'خطأ غير معروف';

  @override
  String get goToLogin => 'الانتقال إلى تسجيل الدخول';

  @override
  String get conference => 'مؤتمر';

  @override
  String get defaultJoinRequestMessage => 'مرحباً، يرجى دعوتي إلى هذه المجموعة';

  @override
  String get userNotFoundPleaseRegister =>
      'المستخدم غير موجود. يرجى التسجيل أولاً.';

  @override
  String get nicknameDoesNotMatch =>
      'الاسم المستعار غير مطابق. يرجى استخدام الاسم المستعار المسجل أو تسجيل حساب جديد.';

  @override
  String get accountAlreadyExistsPleaseLogin =>
      'الحساب موجود بالفعل. يرجى تسجيل الدخول بدلاً من ذلك أو استخدام اسم مستعار مختلف.';

  @override
  String get profileNotFoundImportRestore =>
      'لم يتم العثور على ملف شخصي لهذا الحساب. يرجى استيراد نسخة احتياطية أو استعادتها.';

  @override
  String get failedToInitializeTIMManager => 'فشل تهيئة TIMManager SDK';

  @override
  String get failedToGetToxId => 'فشل الحصول على Tox ID';

  @override
  String get failedToGenerateToxId => 'فشل إنشاء Tox ID';

  @override
  String get registrationCouldNotCreateProfile =>
      'تعذّر على التسجيل إنشاء ملف شخصي فريد. يرجى المحاولة مرة أخرى.';

  @override
  String get importedAccount => 'حساب مستورد';

  @override
  String get unknown => 'غير معروف';

  @override
  String sendingToGroupsNotSupported(String label) {
    return 'إرسال $label إلى المجموعات غير مدعوم بعد';
  }

  @override
  String noLabelSelected(String label) {
    return 'لم يتم اختيار $label';
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
  String get callSwitchCamera => 'تبديل الكاميرا';

  @override
  String get callSpeakerOff => 'إيقاف السماعة';

  @override
  String get callSpeakerOn => 'تشغيل السماعة';

  @override
  String get callHangUp => 'إنهاء المكالمة';

  @override
  String get callEnded => 'انتهت المكالمة';

  @override
  String get callPermissionMicrophoneRequired =>
      'يلزم إذن الميكروفون لمتابعة المكالمة.';

  @override
  String get callPermissionCameraRequired =>
      'يلزم إذن الكاميرا لمتابعة المكالمة.';

  @override
  String get callPermissionMicrophoneCameraRequired =>
      'يلزم إذن الميكروفون والكاميرا لمتابعة المكالمة.';

  @override
  String get callIncomingNotificationPermissionRequired =>
      'لا يمكن أن ترن المكالمات الواردة إلا داخل Toxee حتى يتم تفعيل إذن الإشعارات.';

  @override
  String get callFailedGroupUnsupported => 'المكالمات الجماعية غير مدعومة بعد.';

  @override
  String get callFailedSignaling =>
      'تعذّر بدء المكالمة. يُرجى المحاولة مرة أخرى.';

  @override
  String get callFailedMediaChannel => 'تعذّر إنشاء قناة الوسائط للمكالمة.';

  @override
  String get callVideoUnsupportedPlatform =>
      'مكالمات الفيديو غير متاحة على هذه المنصة بعد (لا يوجد دعم للكاميرا).';

  @override
  String get callAudioInterrupted =>
      'تم تغيير إخراج الصوت أو انقطاعه أثناء المكالمة.';

  @override
  String get callCalling => 'جارٍ الاتصال...';

  @override
  String get callLeaving => 'جارٍ مغادرة المؤتمر...';

  @override
  String callReceivedFrames(int count) {
    return 'تم استلام $count إطارًا';
  }

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
    return '$count رسائل غير مقروءة';
  }

  @override
  String matchingMessagesSemantics(int count) {
    return '$count رسائل مطابقة';
  }

  @override
  String get statusOnline => 'متصل';

  @override
  String get statusOffline => 'غير متصل';

  @override
  String get noIrcChannels => 'لا توجد قنوات IRC';

  @override
  String get joinChannelToGetStarted => 'انضم إلى قناة للبدء';

  @override
  String ircUsersCount(int count) {
    return 'المستخدمون ($count)';
  }

  @override
  String get ircNoUsers => 'لا يوجد مستخدمون';

  @override
  String get passwordVisibility => 'تبديل رؤية كلمة المرور';

  @override
  String get nicknameHintExample => 'مثلاً: Alice';

  @override
  String get callAudioRouteSystem => 'يدير النظام مسار الصوت على هذه المنصة';

  @override
  String get copyFullToxId => 'نسخ المعرّف الكامل';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get idLabel => 'المعرّف:';

  @override
  String errorBannerLabel(String message) {
    return 'خطأ: $message';
  }

  @override
  String searchResultContactSemantics(String name) {
    return '$name، جهة اتصال';
  }

  @override
  String searchResultGroupSemantics(String name) {
    return '$name، مجموعة';
  }

  @override
  String searchResultMessageSemantics(String name) {
    return '$name، رسالة';
  }

  @override
  String searchResultConversationSemantics(String name) {
    return '$name، محادثة';
  }

  @override
  String get importNoFileSelected => 'لم يتم تحديد ملف';

  @override
  String get importCancelled => 'تم الإلغاء';

  @override
  String get recoveryBlockedTitle => 'لم تكتمل استعادة الحساب';

  @override
  String get recoveryBlockedBody =>
      'عثر toxee على عملية استعادة أو حذف حساب غير مكتملة تعذّرت قراءتها، لذا لم يفتح أي حساب — فقد تؤدي المتابعة إلى إتلاف البيانات.\n\nلا تزال حساباتك وملفاتها الشخصية على هذا الجهاز. يرجى عدم إعادة التسجيل وعدم مسح بيانات التطبيق؛ فكلاهما سيجعل الفقدان دائماً. أبلغ عن التفاصيل أدناه ليتسنى إصلاح المشكلة.';

  @override
  String get secureStorageUnavailable =>
      'التخزين الآمن غير متاح، لذا لا يستطيع toxee التحقق من كلمة مرور هذا الحساب. عادةً ما يكون هذا مؤقتاً — حاول مرة أخرى، أو افتح سلسلة مفاتيح جهازك.';

  @override
  String get recoverLegacyDataAction => 'استرداد البيانات من إصدار أقدم';

  @override
  String get recoverLegacyDataConfirm =>
      'لا يزال هذا الجهاز يحتفظ بسجل الدردشة والرسائل المنتظرة والصور الرمزية لجهات الاتصال من قبل أن يدعم toxee تعدد الحسابات. هل تريد إضافتها إلى الحساب المسجل الدخول به حالياً؟\n\nافعل ذلك فقط إذا كانت هذه البيانات تخصك. لا يمكن المطالبة بها إلا مرة واحدة ومن حساب واحد.\n\nسيتم تسجيل خروجك حتى يتم الدمج عند تسجيل الدخول التالي.';

  @override
  String get recoverLegacyDataClaimed =>
      'سيتولى هذا الحساب البيانات الأقدم. سجّل الخروج ثم سجّل الدخول مرة أخرى لدمجها — فإجراء الدمج عند تسجيل الدخول هو ما يحافظ على سجلك الحالي والرسائل المنتظرة سليمة.';

  @override
  String get recoverLegacyDataDone =>
      'تمت إضافة البيانات الأقدم إلى هذا الحساب.';

  @override
  String get recoverLegacyDataUnavailable =>
      'تعذّرت المطالبة بتلك البيانات — ربما تخص بالفعل حساباً آخر على هذا الجهاز.';

  @override
  String get accountRegistryUnreadable =>
      'تعذّرت قراءة حساباتك المحفوظة. لا تزال ملفاتها الشخصية على هذا الجهاز — لا تُعِد التسجيل؛ أبلغ عن ذلك ليتسنى إصلاح قائمة الحسابات.';

  @override
  String get importedAccountDefaultName => 'حساب مستورد';

  @override
  String failedToImport(String error) {
    return 'فشل الاستيراد: $error';
  }

  @override
  String get selectConversationEmptyState => 'اختر محادثة لبدء الدردشة';

  @override
  String get newConversationTooltip => 'محادثة جديدة';

  @override
  String get pinConversation => 'تثبيت';

  @override
  String get unpinConversation => 'إلغاء التثبيت';

  @override
  String get markConversationAsRead => 'وضع علامة كمقروء';

  @override
  String get deleteConversationTitle => 'حذف المحادثة؟';

  @override
  String deleteConversationBody(String name) {
    return 'ستتم إزالة \"$name\" من قائمة الدردشة. سيبقى سجل الرسائل على القرص.';
  }

  @override
  String get firstRunBackupWizardTitle => 'احفظ ملف حسابك';

  @override
  String get firstRunBackupWizardBody =>
      'حسابك موجود على هذا الجهاز فقط. احفظ ملف .tox في مكان آمن (تخزين سحابي، مدير كلمات مرور، ذاكرة USB). بدونه، فإن فقدان هذا الجهاز يعني فقدان حسابك وجميع جهات اتصالك نهائياً.';

  @override
  String get firstRunBackupWizardExportNow => 'تصدير الآن';

  @override
  String get firstRunBackupWizardLater => 'سأفعل ذلك لاحقاً';

  @override
  String get firstRunBackupWizardDismissTitle => 'تخطي النسخ الاحتياطي؟';

  @override
  String get firstRunBackupWizardDismissBody =>
      'إذا فقدت هذا الجهاز، فستفقد حسابك وجميع جهات الاتصال. لا توجد طريقة للاستعادة.';

  @override
  String get firstRunBackupWizardDismissConfirm => 'أفهم ذلك، متابعة';

  @override
  String firstRunBackupWizardExportFailed(String error) {
    return 'تعذّر حفظ ملف حسابك: $error';
  }

  @override
  String get restoreFromToxFile => 'الاستعادة من ملف .tox';

  @override
  String restoreFromToxFileSuccess(String nickname) {
    return 'تمت استعادة الحساب: $nickname';
  }

  @override
  String get restoreFromToxFileInvalidFile =>
      'لا يبدو أن هذا الملف ملف شخصي صالح لـ Tox.';

  @override
  String get pairDeviceHostTitle => 'إقران جهاز آخر';

  @override
  String get pairDeviceClientTitle => 'الإقران مع جهاز آخر';

  @override
  String get pairingHostInstructions =>
      'افتح toxee على جهازك الآخر، واختر \"الإقران مع جهاز آخر\"، ثم امسح رمز QR هذا.';

  @override
  String get pairingClientScanInstructions =>
      'وجّه الكاميرا نحو رمز QR على جهازك الآخر.';

  @override
  String get pairingClientPasteInstructions =>
      'المسح بالكاميرا غير مدعوم على هذا الجهاز. الصق رابط الإقران المعروض على جهازك الآخر أدناه.';

  @override
  String get pairingPasteUrlLabel => 'رابط الإقران';

  @override
  String get pairingConnectButton => 'اتصال';

  @override
  String get pairingWaitingForPeer => 'في انتظار اتصال الجهاز الآخر…';

  @override
  String get pairingVerifyCodeHeader => 'تحقق من أن الجهازين يعرضان الرمز نفسه';

  @override
  String get pairingVerifyCodeInstructions =>
      'إذا كان الرمز مطابقاً لما يظهر على جهازك الآخر، فاضغط أدناه. وإذا اختلفا، فألغِ العملية — فقد يكون هناك من يعترض الاتصال.';

  @override
  String get pairingCodesMatch => 'الرمزان متطابقان';

  @override
  String get pairingHostCompleted =>
      'تم إرسال الحساب. أصبح حسابك الآن على الجهاز الآخر.';

  @override
  String get pairingClientCompleted => 'تم استلام الحساب. اكتمل الإقران.';

  @override
  String get pairingCancelled => 'تم إلغاء الإقران.';

  @override
  String get pairingTimeout => 'انتهت مهلة الإقران — حاول مرة أخرى.';

  @override
  String pairingNetworkError(String detail) {
    return 'خطأ في الشبكة أثناء الإقران: $detail';
  }

  @override
  String pairingProtocolError(String detail) {
    return 'فشلت مصافحة الإقران: $detail';
  }

  @override
  String pairingInvalidUrl(String detail) {
    return 'رمز QR هذا ليس دعوة إقران صالحة: $detail';
  }

  @override
  String get pairingDecryptFailed =>
      'تعذّر فك تشفير الملف الشخصي المستلم. ربما تم العبث بعملية الإقران — حاول مرة أخرى على شبكة تثق بها.';

  @override
  String get pairingNoLanInterface =>
      'لم يتم اكتشاف شبكة LAN. اتصل بشبكة Wi-Fi أو Ethernet وحاول مرة أخرى.';

  @override
  String get pairThisAccountToAnotherDevice => 'إقران هذا الحساب بجهاز آخر';

  @override
  String get pairWithAnotherDevice => 'الإقران مع جهاز آخر يحتوي على حسابي';

  @override
  String get devicesSectionTitle => 'الأجهزة';

  @override
  String get done => 'تم';

  @override
  String get runtimeForegroundTitle => 'Toxee قيد التشغيل';

  @override
  String get runtimeForegroundBody =>
      'البقاء متصلاً لاستقبال الرسائل والمكالمات.';

  @override
  String get runtimeForegroundSettingsLabel => 'إعدادات الإشعارات';

  @override
  String get runtimeForegroundCallTitle => 'مكالمة جارية';

  @override
  String get runtimeForegroundCallBody => 'يحافظ Toxee على اتصال مكالمتك.';

  @override
  String runtimeForegroundCallBodyWithCaller(String name) {
    return 'مكالمة مع $name';
  }

  @override
  String get appTagline => 'مراسلة خاصة عبر الند للند';

  @override
  String get noBootstrapNodes => 'لا توجد عقد تمهيد';

  @override
  String get importMayHaveCompleted =>
      'تعذّر التراجع عن الاستيراد، لذا قد يظل هذا الحساب موجوداً. تحقق من قائمة حساباتك قبل الاستيراد مرة أخرى.';

  @override
  String get importBlockedByPendingImport =>
      'تمت مقاطعة عملية استيراد حساب أخرى ولم يتم تنظيفها بعد. أعد تشغيل toxee لإكمال التراجع عنها، ثم أعد الاستيراد.';

  @override
  String get friendRequestQueued =>
      'غير متصل — تم وضع الطلب في قائمة الانتظار وسيُرسل عند إعادة الاتصال';

  @override
  String get cannotAddSelfAsFriend => 'لا يمكنك إضافة نفسك كصديق';

  @override
  String get friendRequestAlreadySent =>
      'تم إرسال طلب صداقة بالفعل في هذه الجلسة';

  @override
  String get alreadyInFriendList =>
      'هذا المستخدم موجود بالفعل في قائمة أصدقائك';

  @override
  String get addFriendOfflineBanner =>
      'غير متصل — سيتم وضع طلب الصداقة في قائمة الانتظار وإرساله تلقائياً عند إعادة الاتصال.';

  @override
  String get scanQr => 'مسح رمز QR';

  @override
  String get sendingInProgress => 'جارٍ الإرسال...';

  @override
  String get firewallHintWindows =>
      'على Windows، قد يحظر جدار الحماية الاتصالات الواردة؛ اسمح للتطبيق إذا طُلب منك ذلك.';

  @override
  String get firewallHintLinux =>
      'على Linux، قد تتطلب عمليات الشبكة أذونات أو قواعد جدار حماية مناسبة.';

  @override
  String get nodePublicKeyHint => 'المفتاح العام (hex)';

  @override
  String get failedToAddBootstrapNode => 'فشل إضافة عقدة Bootstrap';

  @override
  String get couldNotRemovePassword => 'تعذّرت إزالة كلمة المرور';

  @override
  String get couldNotSavePassword => 'تعذّر حفظ كلمة المرور';

  @override
  String mediaSent(String label) {
    return 'تم إرسال $label';
  }

  @override
  String get dhtUnreachableUsingFallback =>
      'تعذّر الوصول إلى DHT. يتم استخدام عقد Bootstrap الاحتياطية — ربما تحظر شبكتك UDP، أو أن العقد معطلة.';

  @override
  String get dhtUnreachableTimeout =>
      'تعذّر الوصول إلى DHT بعد 30 ثانية. تحقق من اتصالك بالشبكة.';

  @override
  String chatSdkInitFailed(String error) {
    return 'فشل تهيئة SDK الدردشة: $error';
  }

  @override
  String messageTooLongMaxBytes(int maxBytes) {
    return 'الرسالة طويلة جداً (الحد الأقصى $maxBytes بايت)';
  }

  @override
  String get friendOfflineWillRetry =>
      'الصديق غير متصل — ستتم إعادة المحاولة عند اتصاله';

  @override
  String get groupFileTransferUnsupported =>
      'نقل الملفات في الدردشات الجماعية غير مدعوم';

  @override
  String fileSendFailed(String error) {
    return 'فشل إرسال الملف: $error';
  }

  @override
  String errorWithCode(int code) {
    return 'الخطأ $code';
  }

  @override
  String pairingLanUnreachable(String detail) {
    return 'لا يمكن للجهازين رؤية بعضهما على هذه الشبكة. جرّب نقطة اتصال شخصية، أو استخدم التصدير ← الاستيراد عبر ملف بدلاً من ذلك. ($detail)';
  }

  @override
  String get notificationNewFriendRequest => 'طلب صداقة جديد';

  @override
  String notificationFriendRequestFrom(String name) {
    return 'طلب صداقة: $name';
  }

  @override
  String get notificationMissedCall => 'مكالمة فائتة';

  @override
  String get notificationMissedVideoCall => 'مكالمة فيديو فائتة';

  @override
  String get notificationIncomingCall => 'مكالمة واردة';

  @override
  String get notificationIncomingVideoCall => 'مكالمة فيديو واردة';

  @override
  String get notificationUnknownCaller => 'جهة اتصال Toxee';

  @override
  String get notificationNewMessage => 'رسالة جديدة';

  @override
  String get previewImage => '[صورة]';

  @override
  String get previewVideo => '[فيديو]';

  @override
  String get previewVoice => '[رسالة صوتية]';

  @override
  String previewVoiceWithDuration(int seconds) {
    return '[رسالة صوتية $seconds ث]';
  }

  @override
  String get previewFile => '[ملف]';

  @override
  String previewFileWithName(String name) {
    return '[ملف] $name';
  }

  @override
  String get previewSticker => '[ملصق]';

  @override
  String get previewLocation => '[موقع]';

  @override
  String get previewCustomMessage => '[رسالة مخصصة]';

  @override
  String get previewGroupEvent => '[حدث مجموعة]';

  @override
  String get previewMessage => '[رسالة]';

  @override
  String get channelMessagesName => 'الرسائل';

  @override
  String get channelMessagesDescription =>
      'إشعارات الرسائل الجديدة الواردة من جهات اتصالك على Tox.';

  @override
  String get channelFriendRequestsName => 'طلبات الصداقة';

  @override
  String get channelFriendRequestsDescription =>
      'إشعارات عندما يرسل إليك أحدهم طلب صداقة.';

  @override
  String get channelMissedCallsName => 'المكالمات الفائتة';

  @override
  String get channelMissedCallsDescription =>
      'إشعارات عندما تتعذّر تلبية مكالمة واردة أو تفوتك.';

  @override
  String get channelIncomingCallsName => 'المكالمات الواردة';

  @override
  String get channelIncomingCallsDescription =>
      'تنبيهات بملء الشاشة لمكالمات Toxee الواردة.';

  @override
  String get notificationOpenAction => 'فتح Toxee';

  @override
  String trayUnreadTooltip(int count) {
    return 'غير مقروءة: $count';
  }

  @override
  String get unknownErrorReason => 'خطأ غير معروف';

  @override
  String get notificationNoMessage => '(بدون رسالة)';

  @override
  String notificationGroupedSummary(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رسالة جديدة من $name',
      many: '$count رسالة جديدة من $name',
      few: '$count رسائل جديدة من $name',
      two: 'رسالتان جديدتان من $name',
    );
    return '$_temp0';
  }

  @override
  String pairingConnectTimedOut(String endpoint) {
    return 'تعذّر الوصول إلى الجهاز الآخر على $endpoint في الوقت المحدد. تأكد من أن الجهازين على الشبكة نفسها، أو جرّب نقطة اتصال شخصية، أو استخدم التصدير ← الاستيراد عبر ملف بدلاً من ذلك.';
  }
}
