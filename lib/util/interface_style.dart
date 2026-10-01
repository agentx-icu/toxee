import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Device-wide visual identity, independent of light/dark preference.
enum InterfaceStyle {
  classic,
  modern,
  night,
  paper,
  cartoon;

  static InterfaceStyle parse(String? value) =>
      values.firstWhere((style) => style.name == value, orElse: () => classic);

  StylePalette palette(Brightness brightness) =>
      _palettes[this]![brightness == Brightness.dark ? 1 : 0];

  StyleGeometry get geometry => _geometry[this]!;
}

@immutable
class StylePalette {
  final Color canvas;
  final Color panel;
  final Color rail;
  final Color selected;
  final Color primary;
  final Color onPrimary;
  final Color text;
  final Color muted;
  final Color divider;
  final Color controlBorder;
  final Color sent;
  final Color received;
  final Color link;
  final Color online;
  final Color error;
  final Color warning;
  final Color unread;
  final Color onUnread;
  final Color sentText;
  final Color receivedText;
  const StylePalette({
    required this.canvas,
    required this.panel,
    required this.rail,
    required this.selected,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.muted,
    required this.divider,
    required this.controlBorder,
    required this.sent,
    required this.received,
    required this.link,
    required this.online,
    required this.error,
    required this.warning,
    required this.unread,
    required this.onUnread,
    required this.sentText,
    required this.receivedText,
  });
}

@immutable
class StyleGeometry {
  final double panelRadius, controlRadius, bubbleRadius, bubbleTailRadius;
  final double outlineWidth, shadowOffset;
  const StyleGeometry({
    required this.panelRadius,
    required this.controlRadius,
    required this.bubbleRadius,
    required this.bubbleTailRadius,
    this.outlineWidth = 0,
    this.shadowOffset = 0,
  });
}

const _geometry = <InterfaceStyle, StyleGeometry>{
  InterfaceStyle.classic: StyleGeometry(
    panelRadius: 12,
    controlRadius: 8,
    bubbleRadius: 12,
    bubbleTailRadius: 12,
  ),
  InterfaceStyle.modern: StyleGeometry(
    panelRadius: 16,
    controlRadius: 10,
    bubbleRadius: 14,
    bubbleTailRadius: 14,
    outlineWidth: 0,
    shadowOffset: 0,
  ),
  InterfaceStyle.night: StyleGeometry(
    panelRadius: 8,
    controlRadius: 6,
    bubbleRadius: 8,
    bubbleTailRadius: 8,
    outlineWidth: 0,
    shadowOffset: 0,
  ),
  InterfaceStyle.paper: StyleGeometry(
    panelRadius: 4,
    controlRadius: 4,
    bubbleRadius: 6,
    bubbleTailRadius: 6,
    outlineWidth: 0,
    shadowOffset: 0,
  ),
  InterfaceStyle.cartoon: StyleGeometry(
    panelRadius: 20,
    controlRadius: 12,
    bubbleRadius: 18,
    bubbleTailRadius: 6,
    outlineWidth: 2,
    shadowOffset: 2,
  ),
};

const _palettes = <InterfaceStyle, List<StylePalette>>{
  InterfaceStyle.classic: [
    StylePalette(
      canvas: DesignTokens.scaffoldLight,
      panel: DesignTokens.cardLight,
      rail: DesignTokens.railLight,
      selected: DesignTokens.selectedLight,
      primary: DesignTokens.primary,
      onPrimary: DesignTokens.onPrimary,
      text: DesignTokens.textPrimaryLight,
      muted: DesignTokens.textSecondaryLight,
      divider: DesignTokens.dividerLight,
      controlBorder: DesignTokens.inputBorderLight,
      sent: DesignTokens.selfBubbleLight,
      received: DesignTokens.otherBubbleLight,
      link: DesignTokens.primary,
      online: DesignTokens.online,
      error: DesignTokens.errorLight,
      warning: DesignTokens.warningLight,
      unread: DesignTokens.unreadBadge,
      onUnread: DesignTokens.onUnreadBadge,
      sentText: DesignTokens.selfBubbleTextLight,
      receivedText: DesignTokens.textPrimaryLight,
    ),
    StylePalette(
      canvas: DesignTokens.scaffoldDark,
      panel: DesignTokens.cardDark,
      rail: DesignTokens.railDark,
      selected: DesignTokens.selectedDark,
      primary: DesignTokens.primary,
      onPrimary: DesignTokens.onPrimary,
      text: DesignTokens.textPrimaryDark,
      muted: DesignTokens.textSecondaryDark,
      divider: DesignTokens.dividerDark,
      controlBorder: DesignTokens.inputBorderDark,
      sent: DesignTokens.selfBubbleDark,
      received: DesignTokens.otherBubbleDark,
      link: DesignTokens.linkDark,
      online: DesignTokens.online,
      error: DesignTokens.errorDark,
      warning: DesignTokens.warningDark,
      unread: DesignTokens.unreadBadge,
      onUnread: DesignTokens.onUnreadBadge,
      sentText: DesignTokens.selfBubbleTextDark,
      receivedText: DesignTokens.textPrimaryDark,
    ),
  ],
  InterfaceStyle.modern: [
    StylePalette(
      canvas: Color(0xFFF5F8F7),
      panel: Color(0xFFFFFFFF),
      rail: Color(0xFFEDF3F0),
      selected: Color(0xFFE0EFE8),
      primary: Color(0xFF147D68),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF18352D),
      muted: Color(0xFF566B63),
      divider: Color(0xFFDCE6E1),
      controlBorder: Color(0xFF758C81),
      sent: Color(0xFFDDF0E7),
      received: Color(0xFFEFF3F1),
      link: Color(0xFF147D68),
      online: Color(0xFF1F754C),
      error: Color(0xFFB42331),
      warning: Color(0xFF875800),
      unread: Color(0xFFB42331),
      onUnread: Color(0xFFFFFFFF),
      sentText: Color(0xFF18352D),
      receivedText: Color(0xFF18352D),
    ),
    StylePalette(
      canvas: Color(0xFF12221C),
      panel: Color(0xFF192D24),
      rail: Color(0xFF101E18),
      selected: Color(0xFF28463A),
      primary: Color(0xFF64DAB2),
      onPrimary: Color(0xFF10251C),
      text: Color(0xFFECF4EF),
      muted: Color(0xFFAEC5B9),
      divider: Color(0xFF365045),
      controlBorder: Color(0xFF718F7E),
      sent: Color(0xFF244C3B),
      received: Color(0xFF22382D),
      link: Color(0xFF8BE2BC),
      online: Color(0xFF7BD8A9),
      error: Color(0xFFFF929F),
      warning: Color(0xFFEDC879),
      unread: Color(0xFFFF929F),
      onUnread: Color(0xFF291218),
      sentText: Color(0xFFECF4EF),
      receivedText: Color(0xFFECF4EF),
    ),
  ],
  InterfaceStyle.night: [
    StylePalette(
      canvas: Color(0xFFF1F5F8),
      panel: Color(0xFFFFFFFF),
      rail: Color(0xFFE3EBF0),
      selected: Color(0xFFDDE9EF),
      primary: Color(0xFF165F6A),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF172B34),
      muted: Color(0xFF526772),
      divider: Color(0xFFD1DEE5),
      controlBorder: Color(0xFF6F8793),
      sent: Color(0xFFDBEBEF),
      received: Color(0xFFE8EFF3),
      link: Color(0xFF165F6A),
      online: Color(0xFF226C53),
      error: Color(0xFFB42331),
      warning: Color(0xFF815600),
      unread: Color(0xFF815600),
      onUnread: Color(0xFFFFFFFF),
      sentText: Color(0xFF172B34),
      receivedText: Color(0xFF172B34),
    ),
    StylePalette(
      canvas: Color(0xFF111923),
      panel: Color(0xFF1B2733),
      rail: Color(0xFF0E1620),
      selected: Color(0xFF294453),
      primary: Color(0xFF64D8C2),
      onPrimary: Color(0xFF102620),
      text: Color(0xFFEDF3F6),
      muted: Color(0xFFADC0CC),
      divider: Color(0xFF354754),
      controlBorder: Color(0xFF8099A7),
      sent: Color(0xFF244943),
      received: Color(0xFF25333F),
      link: Color(0xFF80DECC),
      online: Color(0xFF84D7B2),
      error: Color(0xFFFF929F),
      warning: Color(0xFFEABF76),
      unread: Color(0xFFEABF76),
      onUnread: Color(0xFF2E220E),
      sentText: Color(0xFFEDF3F6),
      receivedText: Color(0xFFEDF3F6),
    ),
  ],
  InterfaceStyle.paper: [
    StylePalette(
      canvas: Color(0xFFF4F0E7),
      panel: Color(0xFFFFFCF5),
      rail: Color(0xFFECE6D9),
      selected: Color(0xFFF0DECF),
      primary: Color(0xFFA34432),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF302D26),
      muted: Color(0xFF665F51),
      divider: Color(0xFFD8CEBC),
      controlBorder: Color(0xFF8B7E68),
      sent: Color(0xFFF5E1D5),
      received: Color(0xFFEEE9DE),
      link: Color(0xFFA34432),
      online: Color(0xFF426A48),
      error: Color(0xFFAE2F35),
      warning: Color(0xFF855B09),
      unread: Color(0xFFAE2F35),
      onUnread: Color(0xFFFFFFFF),
      sentText: Color(0xFF302D26),
      receivedText: Color(0xFF302D26),
    ),
    StylePalette(
      canvas: Color(0xFF231F1A),
      panel: Color(0xFF2D2821),
      rail: Color(0xFF1D1A16),
      selected: Color(0xFF48382D),
      primary: Color(0xFFF0A087),
      onPrimary: Color(0xFF322017),
      text: Color(0xFFF5F0E5),
      muted: Color(0xFFC4B9A6),
      divider: Color(0xFF514739),
      controlBorder: Color(0xFFA69984),
      sent: Color(0xFF49332A),
      received: Color(0xFF373027),
      link: Color(0xFFF0A087),
      online: Color(0xFFACCEA0),
      error: Color(0xFFF6A0A0),
      warning: Color(0xFFE2C486),
      unread: Color(0xFFF6A0A0),
      onUnread: Color(0xFF301616),
      sentText: Color(0xFFF5F0E5),
      receivedText: Color(0xFFF5F0E5),
    ),
  ],
  InterfaceStyle.cartoon: [
    StylePalette(
      canvas: Color(0xFFFFF8EE),
      panel: Color(0xFFFFFEF8),
      rail: Color(0xFFFFF0D8),
      selected: Color(0xFFFFE6A5),
      primary: Color(0xFFB53B50),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF342F40),
      muted: Color(0xFF6C5E73),
      divider: Color(0xFFDDCFCB),
      controlBorder: Color(0xFF342F40),
      sent: Color(0xFFFFE0DB),
      received: Color(0xFFECE9FF),
      link: Color(0xFFA93048),
      online: Color(0xFF35613F),
      error: Color(0xFFA52A40),
      warning: Color(0xFF77520D),
      unread: Color(0xFFA52A40),
      onUnread: Color(0xFFFFFFFF),
      sentText: Color(0xFF342F40),
      receivedText: Color(0xFF342F40),
    ),
    StylePalette(
      canvas: Color(0xFF211D2C),
      panel: Color(0xFF2D263B),
      rail: Color(0xFF1C1826),
      selected: Color(0xFF473825),
      primary: Color(0xFFFFB2AE),
      onPrimary: Color(0xFF342431),
      text: Color(0xFFF9F1EB),
      muted: Color(0xFFCCBDD7),
      divider: Color(0xFF53465F),
      controlBorder: Color(0xFFC6B6CA),
      sent: Color(0xFF5C343E),
      received: Color(0xFF3A3357),
      link: Color(0xFFFFB2AE),
      online: Color(0xFFAFD4A9),
      error: Color(0xFFFFAFBD),
      warning: Color(0xFFEED39B),
      unread: Color(0xFFFFAFBD),
      onUnread: Color(0xFF34202B),
      sentText: Color(0xFFF9F1EB),
      receivedText: Color(0xFFF9F1EB),
    ),
  ],
};
