import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/daemon/core_version.dart';
import '../../core/daemon/daemon_provider.dart';
import '../../core/daemon/daemon_supervisor.dart';
import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/core_mismatch_banner.dart' show confirmUseBundledCore;

/// Settings → Updates: which senclaw core is running, where it runs from, and
/// whether this app started it. The app's own version (the card above) is a
/// different number — a desktop release carries whatever core was current
/// when it was built, and an adopted daemon can be any release.
class CoreVersionCard extends ConsumerWidget {
  const CoreVersionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final phase = ref.watch(daemonSupervisorProvider.select((s) => s.phase));
    final running = ref.watch(runningCoreProvider);
    // Probing the bundled binary means running it; only worth it when what
    // runs might be something else.
    final bundled = phase == DaemonPhase.adopted
        ? ref.watch(bundledCoreProvider).valueOrNull
        : null;
    final mismatch = ref.watch(coreMismatchProvider);

    final mono = TextStyle(
        color: c.textMuted, fontSize: 12, fontFamily: AppTokens.fontMono);
    final core = running.valueOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(
            color: mismatch == null
                ? c.border
                : AppTokens.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('SenClaw Core',
                  style: TextStyle(
                      color: c.textPrimary, fontWeight: FontWeight.w600)),
              if (core?.installKind != null) ...[
                const SizedBox(width: AppTokens.s8),
                _Chip(_kindLabel(context, core!.installKind!)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          if (running.isLoading && core == null)
            Text(context.tr('Reading the core version…'), style: mono)
          else if (core == null)
            Text(
              phase == DaemonPhase.crashed || phase == DaemonPhase.idle
                  ? context.tr('No core is running.')
                  : context.tr('The running core did not report its version.'),
              style: mono,
            )
          else ...[
            Text(
              context.trArgs('Version {v}', {'v': core.version}) +
                  [
                    if (core.gitHash != null) core.gitHash!,
                    if (core.buildTarget != null) core.buildTarget!,
                  ].map((s) => ' · $s').join(),
              style: mono,
            ),
            if (core.exePath != null) ...[
              const SizedBox(height: 2),
              Text(
                context.trArgs('Running from {path}', {'path': core.exePath!}),
                style: mono.copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
          const SizedBox(height: AppTokens.s8),
          Text(_originLine(context, phase),
              style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
          // The bundled core is worth a line only when it is not what runs.
          if (bundled != null) ...[
            const SizedBox(height: 2),
            Text(
              context.trArgs('Core in this app: {v}', {'v': bundled.label}),
              style: mono,
            ),
          ],
          if (mismatch != null) ...[
            const SizedBox(height: AppTokens.s12),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppTokens.warning),
                const SizedBox(width: AppTokens.s8),
                Expanded(
                  child: Text(
                    context.tr(
                        'The running core is a different build from the one in '
                        'this app. Screens may offer things it does not support, '
                        'or miss things it does.'),
                    style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: AppTokens.s8),
                FilledButton(
                  onPressed: () =>
                      confirmUseBundledCore(context, ref, mismatch),
                  child: Text(context.tr('Use bundled core')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _originLine(BuildContext context, DaemonPhase phase) =>
      switch (phase) {
        DaemonPhase.running || DaemonPhase.starting =>
          context.tr('Started by this app from its own bundle.'),
        DaemonPhase.adopted => context.tr(
            'Already running when this app started — this app did not start it.'),
        DaemonPhase.external =>
          context.tr('Served by the daemon this console is connected to.'),
        DaemonPhase.idle || DaemonPhase.crashed =>
          context.tr('The app has no core running.'),
      };

  static String _kindLabel(BuildContext context, String kind) => switch (kind) {
        'desktop-bundle' => context.tr('App bundle'),
        'standalone' => context.tr('Standalone install'),
        'dev' => context.tr('Development build'),
        _ => kind,
      };
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
      child: Text(label, style: TextStyle(color: c.textMuted, fontSize: 11)),
    );
  }
}
