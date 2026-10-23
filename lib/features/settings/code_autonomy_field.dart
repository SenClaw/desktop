// Settings → General → Agent behavior → Code sessions: how much a coding chat
// may do without an approval card (`codeAutonomy` of `/api/agent-behavior`).

import 'package:flutter/material.dart';

import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';

/// The three levels the daemon accepts, in the order they are offered. Anything
/// else is a 400 there, so the field never sends a value outside this list.
const kCodeAutonomyLevels = ['ask', 'auto', 'full'];

/// What each level does, in the daemon's own terms (`docs/code-autonomy.md`).
/// The English text is the i18n key; keep `vi/settings_screen.dart` in step.
const _levelLabel = {'ask': 'Ask', 'auto': 'Auto', 'full': 'Full'};
const _levelBlurb = {
  'ask': 'Every command and every file edit asks first.',
  'auto': 'Edits inside the project and build, test, lint and local git '
      'commands run on their own; anything that leaves the project or cannot '
      'be undone still asks, and the card says why.',
  'full': 'Nothing asks: every command and edit runs on its own, including '
      'ones that cannot be undone.',
};

/// A three-way selector for `codeAutonomy`.
///
/// [onChanged] persists the choice (the caller owns the request and the
/// provider refresh, the way the neighbouring switches do). While it runs the
/// new level shows as selected and the control is disabled; a failure puts the
/// previous level back and says why.
class CodeAutonomyField extends StatefulWidget {
  const CodeAutonomyField({
    super.key,
    required this.level,
    required this.onChanged,
  });

  /// The level the daemon reports. An unknown value selects nothing.
  final String level;
  final Future<void> Function(String level) onChanged;

  @override
  State<CodeAutonomyField> createState() => _CodeAutonomyFieldState();
}

class _CodeAutonomyFieldState extends State<CodeAutonomyField> {
  String? _pending;

  Future<void> _choose(String level) async {
    if (_pending != null || level == widget.level) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = level);
    try {
      await widget.onChanged(level);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(context.trArgs(
                'Could not change the approval level: {e}', {'e': '$e'}))));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = _pending ?? widget.level;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('Approvals in code sessions'),
            style:
                TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        Text(context.tr('How much the agent may do without asking you first.'),
            style: TextStyle(color: c.textMuted, fontSize: 12)),
        const SizedBox(height: AppTokens.s12),
        SegmentedButton<String>(
          key: const ValueKey('code-autonomy'),
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [
            for (final l in kCodeAutonomyLevels)
              ButtonSegment(
                  value: l,
                  label: Text(context.tr(_levelLabel[l]!)),
                  enabled: _pending == null),
          ],
          selected: kCodeAutonomyLevels.contains(shown) ? {shown} : {},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) _choose(s.first);
          },
        ),
        const SizedBox(height: AppTokens.s12),
        for (final l in kCodeAutonomyLevels)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.s4),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: context.tr(_levelLabel[l]!),
                    style: TextStyle(
                        fontWeight:
                            l == shown ? FontWeight.w700 : FontWeight.w500)),
                TextSpan(text: ' — ${context.tr(_levelBlurb[l]!)}'),
              ]),
              style: TextStyle(
                  color: l == shown ? c.textPrimary : c.textMuted,
                  fontSize: 12),
            ),
          ),
        const SizedBox(height: AppTokens.s4),
        Text(
            context.tr(
                'Auto and Full apply only in code sessions and in folders '
                'that are git repositories — places where a checkpoint can '
                'undo the change. Other chats keep asking, whatever you '
                'choose here.'),
            style: TextStyle(color: c.textMuted, fontSize: 12)),
      ]),
    );
  }
}
