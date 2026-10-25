// Shown above every screen when the app adopted a daemon that is another build
// than the core shipped inside it (`coreMismatchProvider`). Settings → Updates
// carries the same facts in its SenClaw Core card; both offer the same way out
// through [confirmUseBundledCore].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/shell.dart' show openUpdatesPage;
import '../core/daemon/core_version.dart';
import '../core/daemon/daemon_provider.dart';
import '../core/i18n/l10n.dart';
import '../theme/tokens.dart';

class CoreMismatchBanner extends ConsumerWidget {
  const CoreMismatchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mismatch = ref.watch(coreMismatchProvider);
    final dismissed = ref.watch(dismissedCoreMismatchProvider);
    if (mismatch == null || dismissed == mismatch.key) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16, vertical: AppTokens.s8),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: 0.10),
        border: Border(
            bottom: BorderSide(color: AppTokens.warning.withValues(alpha: 0.35))),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppTokens.warning),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: Text(
              context.trArgs(
                'This app is connected to SenClaw core {running}, which it did '
                'not start. The core in this app is {bundled}.',
                {
                  'running': mismatch.running.label,
                  'bundled': mismatch.bundled.label,
                },
              ),
              style: TextStyle(color: c.textPrimary, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          TextButton(
            onPressed: () => openUpdatesPage(context, ref),
            child: Text(context.tr('Details')),
          ),
          const SizedBox(width: AppTokens.s4),
          FilledButton(
            onPressed: () => confirmUseBundledCore(context, ref, mismatch),
            child: Text(context.tr('Use bundled core')),
          ),
          IconButton(
            tooltip: context.tr('Close'),
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => ref
                .read(dismissedCoreMismatchProvider.notifier)
                .state = mismatch.key,
          ),
        ],
      ),
    );
  }
}

/// Ask, then stop the adopted daemon and start the core in this app. The
/// daemon being replaced may be one the person runs on purpose (a terminal, a
/// dev build), so this never happens without the question.
Future<void> confirmUseBundledCore(
    BuildContext context, WidgetRef ref, CoreMismatch mismatch) async {
  // Read before any await: the widget that asked may be gone by the time the
  // restart returns (the banner hides itself once the phase changes).
  final sup = ref.read(daemonSupervisorProvider);
  final port = sup.uiPort;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('Switch to the core in this app?')),
      content: Text(ctx.trArgs(
        'SenClaw core {running} on port {port} is stopped and core {bundled} '
        'from this app starts in its place. Replies in progress are cut off. '
        'If you started that core yourself, it does not come back on its own.',
        {
          'running': mismatch.running.label,
          'port': '$port',
          'bundled': mismatch.bundled.label,
        },
      )),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('Cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr('Use bundled core')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final done = context.tr('Now running the core in this app.');
  try {
    // [DaemonSupervisor.restart] kills whatever holds the UI port when no
    // child of ours runs there, then spawns the bundled binary; the phase
    // change makes `runningCoreProvider` read the new core by itself.
    await sup.restart();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
