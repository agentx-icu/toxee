import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import 'profile_qr_section.dart';

/// Responsive shell that lays out the profile's "main column" and the QR card
/// section side-by-side on wide screens, stacked on narrow ones.
class ProfileLayout extends StatelessWidget {
  const ProfileLayout({
    super.key,
    required this.mainColumnChildren,
    required this.qrSection,
    required this.fallbackContentWidth,
  });

  final List<Widget> mainColumnChildren;
  final ProfileQrSection qrSection;
  final double fallbackContentWidth;

  /// Width reserved for the QR card column on wide layouts. Matches the QR
  /// card's natural render width so it fills the column cleanly.
  static const double _qrColumnWidth = 360.0;

  /// Minimum width before the two-column layout makes sense. Picked so the
  /// profile dialog (~820px inner on desktop) triggers it, while narrow phone
  /// / popover widths (<580) still stack.
  static const double _twoColumnMinWidth = 580.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : fallbackContentWidth;
        final isWide = width >= _twoColumnMinWidth;
        // Single outer scrollable so the page only scrolls when content
        // genuinely overflows — at normal desktop heights the profile fits
        // without a scrollbar.
        if (isWide) {
          return SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                          end: AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: mainColumnChildren,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _qrColumnWidth,
                    child: qrSection,
                  ),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [...mainColumnChildren, qrSection],
            ),
          ),
        );
      },
    );
  }
}
