part of 'appearance_settings_section.dart';

class _StyleChoice extends StatelessWidget {
  const _StyleChoice({
    required this.style,
    required this.brightness,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final InterfaceStyle style;
  final Brightness brightness;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      onTap: onTap,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('settings_style_${style.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StyleThumbnail(style: style, brightness: brightness),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small native layout; no bitmap concept art is embedded in runtime controls.
class _StyleThumbnail extends StatelessWidget {
  const _StyleThumbnail({required this.style, required this.brightness});
  final InterfaceStyle style;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final palette = style.palette(brightness);
    final geometry = style.geometry;
    return ClipRRect(
      borderRadius: BorderRadius.circular(geometry.panelRadius / 2),
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          color: palette.canvas,
          border: Border.all(
            color: palette.controlBorder,
            width: math.max(1, geometry.outlineWidth),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              color: palette.rail,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [palette.primary, palette.muted, palette.muted]
                    .map(
                      (color) => Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(
                            geometry.controlRadius / 2,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 6, width: 40, color: palette.muted),
                    const SizedBox(height: 8),
                    _miniBubble(palette.received, palette, geometry),
                    const SizedBox(height: 5),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _miniBubble(palette.sent, palette, geometry),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBubble(
    Color color,
    StylePalette palette,
    StyleGeometry geometry,
  ) => Container(
    width: 42,
    height: 17,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(geometry.bubbleRadius / 2),
      border: geometry.outlineWidth > 0
          ? Border.all(color: palette.controlBorder)
          : null,
      boxShadow: geometry.shadowOffset > 0
          ? [
              BoxShadow(
                color: palette.controlBorder,
                offset: const Offset(1, 1),
              ),
            ]
          : null,
    ),
  );
}

class _BrightnessChoices extends StatelessWidget {
  const _BrightnessChoices({required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final choices = [
      (ThemeMode.system, l10n.themeSystem, Icons.brightness_auto),
      (ThemeMode.light, l10n.themeLight, Icons.light_mode),
      (ThemeMode.dark, l10n.themeDark, Icons.dark_mode),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        var requiredWidth = 0.0;
        for (final choice in choices) {
          final text = TextPainter(
            text: TextSpan(
              text: choice.$2,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          requiredWidth += text.width + 64;
        }
        if (constraints.maxWidth >= requiredWidth) {
          return SegmentedButton<ThemeMode>(
            segments: choices
                .map(
                  (choice) => ButtonSegment(
                    value: choice.$1,
                    label: Text(choice.$2),
                    icon: Icon(choice.$3, size: 18),
                  ),
                )
                .toList(),
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: onChanged == null
                ? null
                : (selection) => onChanged!(selection.first),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: choices
              .map(
                (choice) => ChoiceChip(
                  label: Text(choice.$2),
                  selected: mode == choice.$1,
                  avatar: Icon(choice.$3, size: 18),
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: onChanged == null
                      ? null
                      : (_) => onChanged!(choice.$1),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ChatPreview extends StatelessWidget {
  const _ChatPreview({required this.style, required this.brightness});
  final InterfaceStyle style;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final palette = style.palette(brightness);
    final geometry = style.geometry;
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      key: const Key('settings_appearance_preview'),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(geometry.panelRadius),
        border: Border.all(
          color: palette.controlBorder,
          width: math.max(1, geometry.outlineWidth),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: palette.selected,
                  child: Icon(
                    Icons.person_outline,
                    color: palette.text,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.appearancePreviewSender,
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.appearancePreviewOnline,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _bubble(l10n.appearancePreviewReceived, false, palette, geometry),
            const SizedBox(height: 12),
            _bubble(l10n.appearancePreviewSent, true, palette, geometry),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border.all(
                  color: palette.controlBorder,
                  width: math.max(1, geometry.outlineWidth),
                ),
                borderRadius: BorderRadius.circular(geometry.controlRadius),
              ),
              child: Row(
                children: [
                  Icon(Icons.add, size: 18, color: palette.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.typeMessage,
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.send_outlined, size: 18, color: palette.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(
    String text,
    bool sent,
    StylePalette palette,
    StyleGeometry geometry,
  ) => Align(
    alignment: sent
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: FractionallySizedBox(
      widthFactor: .85,
      alignment: sent
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sent ? palette.sent : palette.received,
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(geometry.bubbleRadius),
            topEnd: Radius.circular(geometry.bubbleRadius),
            bottomStart: Radius.circular(
              sent ? geometry.bubbleRadius : geometry.bubbleTailRadius,
            ),
            bottomEnd: Radius.circular(
              sent ? geometry.bubbleTailRadius : geometry.bubbleRadius,
            ),
          ),
          border: geometry.outlineWidth > 0
              ? Border.all(
                  color: palette.controlBorder,
                  width: geometry.outlineWidth,
                )
              : null,
          boxShadow: geometry.shadowOffset > 0
              ? [
                  BoxShadow(
                    color: palette.controlBorder,
                    offset: Offset(
                      geometry.shadowOffset,
                      geometry.shadowOffset,
                    ),
                  ),
                ]
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: sent ? palette.sentText : palette.receivedText,
          ),
        ),
      ),
    ),
  );
}
