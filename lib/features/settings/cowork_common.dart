import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

// Building blocks shared by Settings → Claude Code and Settings → sen-link,
// in the same visual language as the other settings sections.

/// A titled settings card.
Widget coworkCard(BuildContext context,
    {required String title, required Widget child, Widget? trailing}) {
  final c = context.colors;
  return Container(
    margin: const EdgeInsets.only(bottom: AppTokens.s16),
    padding: const EdgeInsets.all(AppTokens.s12),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(AppTokens.rMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: c.textPrimary, fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ]),
        const SizedBox(height: AppTokens.s8),
        child,
      ],
    ),
  );
}

/// A tinted notice box (success / warning / danger / info accent).
Widget coworkNotice(BuildContext context, String text, {Color? color}) {
  final tint = color ?? context.colors.accent;
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: AppTokens.s12),
    padding: const EdgeInsets.all(AppTokens.s12),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppTokens.rMd),
      border: Border.all(color: tint.withValues(alpha: 0.3)),
    ),
    child: Text(text, style: TextStyle(color: context.colors.textPrimary, fontSize: 13)),
  );
}

/// A labelled form row with an optional help line.
Widget coworkField(BuildContext context,
    {required String label, required Widget child, String? help}) {
  final c = context.colors;
  return Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.s12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w500, fontSize: 13)),
        const SizedBox(height: AppTokens.s4),
        child,
        if (help != null) ...[
          const SizedBox(height: AppTokens.s4),
          Text(help, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ],
    ),
  );
}

/// Empty text → null, so an unset optional stays unset in config.json.
String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
