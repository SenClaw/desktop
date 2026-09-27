// Settings → Runtime, modelled on LM Studio's Runtime screen: the engines the
// daemon installs and launches as child processes (runtime-protocol.md §5.1)
// — one selection per slot (GGUF, MLX, Decision, OCR, Speech to text, Text to
// speech), the update channel, the "Engines & Frameworks" catalog browser
// (runtime_catalog.dart) and the live process list.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'decision_widgets.dart' show decisionCard, decisionNotice, DecisionChip;
import 'runtime_catalog.dart';
import 'runtime_models.dart';
import 'settings_screen.dart' show SettingsBody;

class RuntimeSection extends ConsumerStatefulWidget {
  const RuntimeSection({super.key});

  @override
  ConsumerState<RuntimeSection> createState() => _RuntimeSectionState();
}

class _RuntimeSectionState extends ConsumerState<RuntimeSection> {
  Timer? _poll;
  bool _checkingUpdates = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Refresh every second while a process is starting/stopping, so the
  /// Running list and slot dropdowns settle without a manual reload.
  void _syncPoll(RuntimesState state) {
    final active =
        state.processes.any((p) => p.state == 'starting' || p.state == 'stopping');
    if (active && _poll == null) {
      _poll = Timer.periodic(
          const Duration(seconds: 1), (_) => ref.invalidate(runtimesProvider));
    } else if (!active && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  void _refreshAll() {
    ref.invalidate(runtimesProvider);
    ref.invalidate(runtimeCatalogProvider);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _selectSlot(RuntimeSlot slot, RuntimeCandidate? candidate) async {
    // `version: null` means "track the newest installed version of this id"
    // and is what a normal pick sends (runtime-protocol.md §5.1); pin an
    // explicit version only when the slot actually offers more than one
    // version of the chosen id to choose between — picking the only one on
    // offer is not "picking a specific version", it's just picking the engine.
    final sameId = candidate == null
        ? const <RuntimeCandidate>[]
        : slot.candidates.where((c) => c.id == candidate.id).toList();
    final version = sameId.length > 1 ? candidate!.version : null;
    try {
      await ref.read(apiClientProvider).put('/api/runtimes/selections', body: {
        'slot': slot.slot,
        'id': candidate?.id,
        'version': version,
      });
      ref.invalidate(runtimesProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _saveSettings(RuntimesState state,
      {bool? autoUpdate, String? channel}) async {
    try {
      await ref.read(apiClientProvider).put('/api/runtimes/settings', body: {
        'autoUpdate': autoUpdate ?? state.settings.autoUpdate,
        'channel': channel ?? state.settings.channel,
        'idleTimeoutSecs': {
          'service': state.settings.idleTimeoutSecs.service,
          'model': state.settings.idleTimeoutSecs.model,
        },
      });
      ref.invalidate(runtimesProvider);
      // A channel switch changes which version each catalog entry resolves
      // to (stable vs. beta) — without this the Engines & Frameworks card
      // keeps showing install/update state for the old channel.
      if (channel != null) ref.invalidate(runtimeCatalogProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _checkUpdates() async {
    setState(() => _checkingUpdates = true);
    try {
      await ref.read(apiClientProvider).post('/api/runtimes/check-updates');
      _refreshAll();
      if (mounted) _toast(context.tr('Checked for runtime updates'));
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _stopProcess(RuntimeProcessInfo p) async {
    try {
      await ref
          .read(apiClientProvider)
          .post('/api/runtimes/processes/${Uri.encodeComponent(p.key)}/stop');
      ref.invalidate(runtimesProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(runtimesProvider);
    return SettingsBody(
      title: context.tr('Runtime'),
      onRefresh: _refreshAll,
      children: [
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => decisionNotice(
              context, e is ApiException ? e.message : '$e',
              tone: AppTokens.danger),
          data: (state) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncPoll(state);
            });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                decisionCard(
                  context,
                  title: context.tr('Runtime Selections'),
                  icon: Icons.tune,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final slot in state.slots)
                        _SlotRow(
                          slot: slot,
                          onChanged: (c) => _selectSlot(slot, c),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppTokens.s8),
                        child: Divider(height: 1),
                      ),
                      _ToggleRow(
                        label: context
                            .tr('Auto-update selected runtime packages'),
                        desc: context.tr(
                            'When a newer version of a selected engine is published, download and install it in the background, and switch to it once nothing is using the old one.'),
                        value: state.settings.autoUpdate,
                        onChanged: (v) => _saveSettings(state, autoUpdate: v),
                      ),
                    ],
                  ),
                ),
                decisionCard(
                  context,
                  title: context.tr('Runtime updates channel'),
                  icon: Icons.update,
                  trailing: Tooltip(
                    message: context.tr(
                        'Stable installs the version each engine\'s release marks stable; Beta tracks its newest published build.'),
                    child: Icon(Icons.info_outline,
                        size: 16, color: context.colors.textMuted),
                  ),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _checkingUpdates ? null : _checkUpdates,
                        icon: _checkingUpdates
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 16),
                        label: Text(context.tr('Check for updates')),
                      ),
                      const SizedBox(width: AppTokens.s12),
                      DropdownButton<String>(
                        value: state.settings.channel,
                        items: [
                          DropdownMenuItem(
                              value: 'stable', child: Text(context.tr('Stable'))),
                          DropdownMenuItem(
                              value: 'beta', child: Text(context.tr('Beta'))),
                        ],
                        onChanged: (v) {
                          if (v != null) _saveSettings(state, channel: v);
                        },
                      ),
                    ],
                  ),
                ),
                RuntimeCatalogCard(
                  installed: state.installed,
                  processes: state.processes,
                  onChanged: _refreshAll,
                ),
                if (state.processes.isNotEmpty)
                  decisionCard(
                    context,
                    title: context.tr('Running'),
                    icon: Icons.play_circle_outline,
                    child: Column(
                      children: [
                        for (final p in state.processes)
                          _ProcessRow(
                              process: p, onStop: () => _stopProcess(p)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One "Runtime Selections" row: a slot's label plus a dropdown of candidates,
/// each rendered as `name` + a monospace version chip (LM Studio's "GGUF →
/// Metal llama.cpp v2.13.0" row).
class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.onChanged});
  final RuntimeSlot slot;
  final ValueChanged<RuntimeCandidate?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final candidates = [...slot.candidates];
    RuntimeCandidate? current;
    for (final cand in candidates) {
      if (cand.id == slot.selected?.id && cand.version == slot.selected?.version) {
        current = cand;
        break;
      }
    }
    // A selection whose package was since uninstalled still deserves a
    // visible row — DropdownButton throws if `value` matches no item.
    if (current == null && slot.selected != null) {
      current = slot.selected;
      candidates.insert(0, current!);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(context.tr(slot.label),
                style:
                    TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: candidates.isEmpty
                ? Text(context.tr('No compatible engine installed'),
                    style: TextStyle(color: c.textMuted, fontSize: 12.5))
                : DropdownButton<RuntimeCandidate>(
                    isExpanded: true,
                    value: current,
                    hint: Text(context.tr('None selected'),
                        style: TextStyle(color: c.textMuted)),
                    items: [
                      for (final cand in candidates)
                        DropdownMenuItem(
                          value: cand,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                  child: Text(cand.name,
                                      overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: AppTokens.s8),
                              DecisionChip(cand.version),
                            ],
                          ),
                        ),
                    ],
                    onChanged: onChanged,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Simple label + description + [Switch] row, matching the shared-settings
/// look used across every settings section.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.desc,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(color: c.textMuted, fontSize: 12)),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// One row of the "Running" list: `processes[]` with state, model, port,
/// uptime, launches and a Stop button.
class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.process, required this.onStop});
  final RuntimeProcessInfo process;
  final VoidCallback onStop;

  Color _stateColor() => switch (process.state) {
        'ready' => AppTokens.success,
        'failed' => AppTokens.danger,
        _ => AppTokens.warning, // starting | stopping
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final uptime = process.startedAt > 0
        ? DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(process.startedAt))
        : null;
    final detail = [
      if (process.modelKey != null) process.modelKey!,
      context.trArgs('port {p}', {'p': process.port}),
      if (uptime != null) context.trArgs('up {m}m', {'m': uptime.inMinutes}),
      context.trArgs('{n} launches', {'n': process.launches}),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Row(
        children: [
          DecisionChip(context.tr(process.state), color: _stateColor()),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${process.runtimeId} · ${process.version}',
                    style: TextStyle(
                        color: c.textPrimary, fontWeight: FontWeight.w600)),
                Text(detail,
                    style: TextStyle(
                        color: c.textMuted,
                        fontSize: 11.5,
                        fontFamily: 'monospace')),
                if (process.error != null)
                  Text(process.error!,
                      style: const TextStyle(color: AppTokens.danger, fontSize: 12)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            label: Text(context.tr('Stop')),
          ),
        ],
      ),
    );
  }
}
