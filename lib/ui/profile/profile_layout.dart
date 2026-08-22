import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import '../../util/responsive_layout.dart';

/// Responsive shell that lays out the profile's "main column" and the QR card
/// section side-by-side on wide screens, stacked on narrow ones.
class ProfileLayout extends StatelessWidget {
  const ProfileLayout({
    super.key,
    required this.mainColumnChildren,
    required this.qrSectionBuilder,
    required this.fallbackContentWidth,
  });

  final List<Widget> mainColumnChildren;
  final Widget Function(bool isWide) qrSectionBuilder;
  final double fallbackContentWidth;

  /// Width reserved for the QR card column on wide layouts. Matches the QR
  /// card's natural render width so it fills the column cleanly.
  static const double _qrColumnWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : fallbackContentWidth;
        final isWide = width >= ResponsiveLayout.mobileBreakpoint;
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
                        end: AppSpacing.xl,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: mainColumnChildren,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _qrColumnWidth,
                    child: qrSectionBuilder(isWide),
                  ),
                ],
              ),
            ),
          );
        }
        // Narrow: the QR card's action row is the LAST thing on the page, so
        // give it a real bottom margin (plus the home-indicator inset) instead
        // of letting it sit flush against — or under — the screen edge.
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: AppSpacing.xl + bottomInset),
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [...mainColumnChildren, qrSectionBuilder(isWide)],
            ),
          ),
        );
      },
    );
  }
}
