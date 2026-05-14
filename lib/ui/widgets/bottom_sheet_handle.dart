import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';

/// Small drag handle for the top of a modal bottom sheet.
///
/// 32×4 rounded bar in slate-300 (light) / slate-700 (dark) with
/// `AppSpacing.sm` vertical margin — the modern iOS / Material 3 affordance
/// that signals "this sheet is draggable / dismissable".
class BottomSheetHandle extends StatelessWidget {
  const BottomSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 32,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        // slate-300 (light) / slate-700 (dark) — hairline neutral
        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
