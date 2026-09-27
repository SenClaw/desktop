// Small pieces shared by the Decision (Laya) section and its playground.

import 'package:flutter/material.dart';

import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';

/// A titled card, the same shape as the other settings sections' cards.
Widget decisionCard(
  BuildContext context, {
  required String title,
  required Widget child,
  Widget? trailing,
  IconData? icon,
}) {
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
          if (icon != null) ...[
            Icon(icon, size: 16, color: c.textSecondary),
            const SizedBox(width: AppTokens.s8),
          ],
          Expanded(
            child: Text(title, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ]),
        const SizedBox(height: AppTokens.s12),
        child,
      ],
    ),
  );
}

/// A tinted notice box — warning, error or plain information.
Widget decisionNotice(BuildContext context, String text, {Color? tone, String? title}) {
  final c = context.colors;
  final color = tone ?? c.textSecondary;
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: AppTokens.s12),
    padding: const EdgeInsets.all(AppTokens.s12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppTokens.rMd),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.s4),
            child: Text(title, style: TextStyle(color: tone ?? c.textPrimary, fontWeight: FontWeight.w600)),
          ),
        SelectableText(text, style: TextStyle(color: tone ?? c.textSecondary, fontSize: 12.5)),
      ],
    ),
  );
}

/// A small rounded label.
class DecisionChip extends StatelessWidget {
  const DecisionChip(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.rFull),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// A number with the reader's decimal separator (comma in Vietnamese).
String decisionNum(BuildContext context, num v, [int digits = 2]) {
  var s = v.toStringAsFixed(digits);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return L10n.of(context).isVi ? s.replaceAll('.', ',') : s;
}

String decisionPct(BuildContext context, double p) => '${decisionNum(context, p * 100, 1)}%';

String decisionBytes(BuildContext context, int n) {
  if (n <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = n.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${decisionNum(context, v, 2)} ${units[i]}';
}
