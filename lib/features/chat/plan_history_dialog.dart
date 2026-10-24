import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_markdown.dart';
import 'plan_history_provider.dart';

/// Browse past plans for a group (web PlanHistoryPanel). Persistent in SQLite.
/// Asks the daemon for the list itself when it opens, so it works from any
/// caller and shows "loading" until the daemon has answered — an empty list is
/// only ever "no plans", never "not loaded yet".
class PlanHistoryDialog extends ConsumerStatefulWidget {
  const PlanHistoryDialog({super.key, required this.jid});
  final String jid;
  @override
  ConsumerState<PlanHistoryDialog> createState() => _PlanHistoryDialogState();
}

class _PlanHistoryDialogState extends ConsumerState<PlanHistoryDialog> {
  /// How long to wait for the daemon before saying the list could not load.
  static const _loadTimeout = Duration(seconds: 8);

  String? _selected;
  Timer? _timeout;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _timeout?.cancel();
    setState(() => _timedOut = false);
    ref.read(planHistoryProvider.notifier).requestList(widget.jid);
    _timeout = Timer(_loadTimeout, () {
      if (mounted && !ref.read(planHistoryProvider).hasLoaded(widget.jid)) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final st = ref.watch(planHistoryProvider);
    final plans = st.forJid(widget.jid);
    final content = _selected == null ? null : st.contentById[_selected];
    final selectedPlan = plans.where((p) => p.id == _selected).firstOrNull;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.history_edu_outlined, size: 18, color: c.accent),
                const SizedBox(width: AppTokens.s8),
                Text(context.tr('Plan history'),
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: AppTokens.s8),
              Expanded(
                child: !st.hasLoaded(widget.jid)
                    ? _Centered(
                        child: _timedOut
                            ? Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(context.tr('Could not load plans'),
                                    style: TextStyle(color: c.textMuted)),
                                const SizedBox(height: AppTokens.s8),
                                OutlinedButton(
                                    onPressed: _load,
                                    child: Text(context.tr('Retry'))),
                              ])
                            : const CircularProgressIndicator())
                    : plans.isEmpty
                        ? _Centered(
                            child: Text(context.tr('No plans yet'),
                                style: TextStyle(color: c.textMuted)))
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 280,
                                child: ListView.builder(
                                  itemCount: plans.length,
                                  itemBuilder: (_, i) => _PlanRow(
                                    plan: plans[i],
                                    selected: plans[i].id == _selected,
                                    onTap: () {
                                      ref
                                          .read(planHistoryProvider.notifier)
                                          .requestGet(plans[i].id);
                                      setState(() => _selected = plans[i].id);
                                    },
                                  ),
                                ),
                              ),
                              Container(width: 1, color: c.border),
                              Expanded(
                                child: _selected == null
                                    ? _Centered(
                                        child: Text(context.tr('Select a plan'),
                                            style:
                                                TextStyle(color: c.textMuted)))
                                    : content == null
                                        ? const _Centered(
                                            child: CircularProgressIndicator())
                                        : SingleChildScrollView(
                                            padding: const EdgeInsets.all(
                                                AppTokens.s12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (selectedPlan != null &&
                                                    selectedPlan
                                                        .filePath.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom:
                                                                AppTokens.s8),
                                                    child: SelectableText(
                                                        selectedPlan.filePath,
                                                        style: TextStyle(
                                                            color: c.textMuted,
                                                            fontSize: 11)),
                                                  ),
                                                if (content.trim().isEmpty)
                                                  Text(
                                                      context.tr(
                                                          'This plan has no content'),
                                                      style: TextStyle(
                                                          color: c.textMuted))
                                                else
                                                  AppMarkdown(content),
                                              ],
                                            ),
                                          ),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(
      {required this.plan, required this.selected, required this.onTap});
  final PlanSummary plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, color) = _approval(context, plan.approval);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s12, vertical: AppTokens.s8),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Wrap(
              spacing: AppTokens.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (label.isNotEmpty)
                  Text(label,
                      style: TextStyle(
                          color: color ?? c.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                if (plan.createdAt != null)
                  Text(_when(plan.createdAt!),
                      style: TextStyle(color: c.textMuted, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The daemon's `approval` word as a label and a colour; an unknown word shows
/// as sent, so a newer daemon's state is visible rather than blank.
(String, Color?) _approval(BuildContext context, String approval) =>
    switch (approval) {
      'pending' => (context.tr('Awaiting approval'), AppTokens.warning),
      'startEditing' => (context.tr('Approved'), AppTokens.success),
      'clearContextAndStart' => (
          context.tr('Approved · fresh start'),
          AppTokens.success
        ),
      'cancelled' => (context.tr('Cancelled'), null),
      _ => (approval, null),
    };

String _when(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
