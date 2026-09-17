// Simplified-Chinese seed copy for the product-screenshot pipeline — the same
// people, group and weekend-hike story as the English [seedEn] in
// seed_data.dart, written as Chinese users would actually chat rather than
// translated line by line. Keys are shared with English; the `*_zh.png`
// avatars carry Chinese initials in the English tiles' colours.

import 'seed_data.dart';

const seedZh = SeedScript(
  heroNickname: '林小雨',
  heroStatusMessage: '徒步、咖啡和点对点聊天',
  alex: Persona(
    pubKey: keyAlex,
    nickname: '陈亮',
    statusMessage: '在某条山路上',
    avatarFile: 'avatar_alex_zh.png',
  ),
  sofia: Persona(
    pubKey: keySofia,
    nickname: '苏思雨 🌸',
    statusMessage: '大概在看书',
    avatarFile: 'avatar_sofia_zh.png',
  ),
  kenta: Persona(
    pubKey: keyKenta,
    nickname: '周健',
    statusMessage: '上海 ⇄ 到处飞',
    avatarFile: 'avatar_kenta_zh.png',
  ),
  applicants: [
    Applicant(pubKey: keyApplicant1, nickname: '李佳', wording: '我是周六徒步小队的李佳 🥾'),
    Applicant(pubKey: keyApplicant2, nickname: '张悦', wording: '上周末在登山口见过面！'),
    Applicant(
      pubKey: keyApplicant3,
      nickname: '唐明',
      wording: '加一下，想要湖边路线的照片 📷',
    ),
  ],
  withAlex: [
    C2cLine(false, '小雨！我从巴塔哥尼亚回来啦 🎒'),
    C2cLine(true, '亮哥！欢迎回来，W 线走得怎么样？'),
    C2cLine(false, '太震撼了，就是膝盖在正式抗议'),
    C2cLine(true, '哈哈，值了 😄'),
    C2cLine(false, '这周六去湖边徒步？落叶松刚变黄 🍂'),
    C2cLine(true, '去！走北环线还是从湖边出发？'),
    C2cLine(false, '湖边出发，早上 7 点登山口集合，下雨前回来'),
    C2cLine(true, '成交，我带那个好用的保温壶 ☕'),
    C2cLine(false, '好嘞，今晚把路线发你 🗺️'),
    C2cLine(true, '周六见 🥾'),
  ],
  withSofia: [
    C2cLine(false, '看到周六的天气预报了吗？☀️'),
    C2cLine(true, '下午三点前都是晴天，完美。'),
    C2cLine(false, '那我带上最好吃的坚果 🥜'),
  ],
  withKenta: [
    C2cLine(true, '周健！这个月回来吗？'),
    C2cLine(false, '周五落地 🛬 下次徒步给我留个位置'),
    C2cLine(true, '没问题，马上拉你进「周末徒步队」🏔'),
  ],
  groupName: '周末徒步队 🏔',
  groupAvatarFile: 'avatar_group_zh.png',
  groupScript: [
    ('self', '给周六的徒步建了个群 🏔'),
    (keyAlex, '好！早上 7 点北停车场集合？'),
    (keySofia, '我来！带坚果 🥜'),
    ('self', '7 点可以，天气预报说下午 3 点前都是晴天'),
    (keyAlex, '地图和急救包我来带'),
    (keySofia, '谁带个正经相机吧 📷'),
    ('self', '我带。走到一半在湖边吃午饭？'),
    (keyAlex, '批准 🙌'),
  ],
);
