// Settings → General → Agent behavior → Design before code: whether the agent
// needs an approved spec before it changes code (`specFlow` of
// `/api/agent-behavior`).

import 'package:flutter/material.dart';

import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';

/// The three modes the daemon accepts, in the order they are offered. Anything
/// else is a 400 there, so the field never sends a value outside this list.
const kSpecFlowModes = ['required', 'on', 'off'];

/// What each mode does, in the daemon's own terms. The English text is the i18n
/// key; keep `vi/settings_screen.dart` in step.
const _modeLabel = {
  'required': 'Design first',
  'on': 'When a spec exists',
  'off': 'Off',
};
const _modeBlurb = {
  'required': 'A code session or project chat needs an approved spec before '
      'its first code change; /spec skip waives it for a small fix.',
  'on': 'Only a folder that already has an open spec is held — one started '
      'with /brainstorm.',
  'off': 'No spec flow: the agent changes code without a design step.',
};

/// A three-way selector for `specFlow`.
///
/// [onChanged] persists the choice (the caller owns the request and the
/// provider refresh, the way the neighbouring switches do). While it runs the
/// new mode shows as selected and the control is disabled; a failure puts the
/// previous mode back and says why.
class SpecFlowField extends StatefulWidget {
  const SpecFlowField({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  /// The mode the daemon reports. An unknown value selects nothing.
  final String mode;
  final Future<void> Function(String mode) onChanged;

  @override
  State<SpecFlowField> createState() => _SpecFlowFieldState();
}

class _SpecFlowFieldState extends State<SpecFlowField> {
  String? _pending;

  Future<void> _choose(String mode) async {
    if (_pending != null || mode == widget.mode) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = mode);
    try {
      await widget.onChanged(mode);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(context
                .trArgs('Could not change design before code: {e}', {'e': '$e'}))));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = _pending ?? widget.mode;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('Design before code'),
            style:
                TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        Text(
            context.tr(
                'Whether the agent needs an approved spec before it changes code.'),
            style: TextStyle(color: c.textMuted, fontSize: 12)),
        const SizedBox(height: AppTokens.s12),
        SegmentedButton<String>(
          key: const ValueKey('spec-flow'),
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [
            for (final m in kSpecFlowModes)
              ButtonSegment(
                  value: m,
                  label: Text(context.tr(_modeLabel[m]!)),
                  enabled: _pending == null),
          ],
          selected: kSpecFlowModes.contains(shown) ? {shown} : {},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) _choose(s.first);
          },
        ),
        const SizedBox(height: AppTokens.s12),
        for (final m in kSpecFlowModes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.s4),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: context.tr(_modeLabel[m]!),
                    style: TextStyle(
                        fontWeight:
                            m == shown ? FontWeight.w700 : FontWeight.w500)),
                TextSpan(text: ' — ${context.tr(_modeBlurb[m]!)}'),
              ]),
              style: TextStyle(
                  color: m == shown ? c.textPrimary : c.textMuted,
                  fontSize: 12),
            ),
          ),
        const SizedBox(height: AppTokens.s4),
        Text(
            context.tr(
                'Type /brainstorm, /draft, /review and /approve in the chat to '
                'move a spec along; /spec shows the open one, switches, closes '
                'or skips it.'),
            style: TextStyle(color: c.textMuted, fontSize: 12)),
      ]),
    );
  }
}
