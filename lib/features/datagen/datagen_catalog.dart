import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'datagen_api.dart';

/// The dataset catalog (`GET /api/datagen/catalog`) as cards: datasets people
/// wrote, installed with one tap as an `import` job. A bundled entry installs
/// from the daemon binary with no network; a Hugging Face preset downloads
/// its pinned split. An entry whose terms need a decision (share-alike,
/// evaluation only) shows its notice and installs only after the person
/// agrees — the daemon refuses it without `acceptLicense`. Same cards as the
/// web page's "Source datasets" tab.
class DatagenCatalog extends ConsumerWidget {
  const DatagenCatalog({
    super.key,
    required this.entries,
    required this.jobs,
    required this.onView,
    required this.onUseAsSeeds,
    required this.onUseAsProblems,
  });

  final List<DatagenCatalogEntry> entries;
  final List<DatagenJob> jobs;
  final void Function(String dataset) onView;
  final void Function(String dataset) onUseAsSeeds;
  final void Function(String dataset) onUseAsProblems;

  Future<void> _install(BuildContext context, WidgetRef ref, DatagenCatalogEntry e) async {
    if (e.needsConsent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.trArgs('Install {title}?', {'title': e.title})),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${e.license} · ${e.attribution}', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (e.notice != null) ...[const SizedBox(height: AppTokens.s8), Text(e.notice!)],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('I agree, install'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/api/datagen/jobs',
            body: {
              'pipeline': 'import',
              'source': {'catalog': e.id},
              if (e.needsConsent) 'acceptLicense': true,
            },
          );
      ref.invalidate(datagenOverviewProvider);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err is ApiException ? err.message : '$err')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: Center(child: Text(context.tr('The catalog is empty'))),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        // Three cards a row on a wide window, down to one on a narrow one.
        final cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
        final width = (box.maxWidth - (cols - 1) * AppTokens.s12) / cols;
        return Wrap(
          spacing: AppTokens.s12,
          runSpacing: AppTokens.s12,
          children: [
            for (final e in entries)
              SizedBox(
                width: width,
                child: _CatalogCard(
                  entry: e,
                  // The name until the job has read its source and said where it came from.
                  running: jobs
                      .where((j) => j.running && j.pipeline == 'import' && (j.catalogId ?? j.name) == e.id)
                      .firstOrNull,
                  onInstall: () => _install(context, ref, e),
                  onView: onView,
                  onUseAsSeeds: onUseAsSeeds,
                  onUseAsProblems: onUseAsProblems,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.entry,
    required this.running,
    required this.onInstall,
    required this.onView,
    required this.onUseAsSeeds,
    required this.onUseAsProblems,
  });

  final DatagenCatalogEntry entry;
  final DatagenJob? running;
  final VoidCallback onInstall;
  final void Function(String) onView;
  final void Function(String) onUseAsSeeds;
  final void Function(String) onUseAsProblems;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final small = TextStyle(fontSize: 11, color: c.textMuted);
    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTokens.s4,
            runSpacing: AppTokens.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              _Tag(e.bundled ? context.tr('Bundled') : (e.fromUrl ? 'URL' : 'Hugging Face'), e.bundled ? Colors.green : Colors.blue),
          if (e.kit != null) _Tag('Kit · ${e.kit}', Colors.purple),
              _Tag(context.tr(e.kind), c.textSecondary),
              _Tag(e.lang, c.textSecondary),
              if (e.flags.contains('shareAlike')) const _Tag('BY-SA', Colors.orange),
              if (e.flags.contains('noTraining')) _Tag(context.tr('Eval only'), Colors.orange),
              if (e.flags.contains('nonCommercial')) const _Tag('NC', Colors.red),
              if (e.flags.contains('researchOnly')) _Tag(context.tr('Research only'), Colors.red),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          Text(e.description, style: TextStyle(fontSize: 12, color: c.textSecondary)),
          const SizedBox(height: AppTokens.s8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${context.trArgs('{n} rows', {'n': e.rows})} · ${e.license} · ${e.attribution}', style: small),
              if (e.homepage != null)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => launchUrl(Uri.parse(e.homepage!), mode: LaunchMode.externalApplication),
                  child: Text(context.tr('Source')),
                ),
            ],
          ),
          if (e.notice != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                    child: Text(e.notice!, style: const TextStyle(fontSize: 11, color: Colors.orange)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppTokens.s8),
          if (running != null)
            Row(
              children: [
                Expanded(child: LinearProgressIndicator(value: running!.progress)),
                const SizedBox(width: AppTokens.s8),
                Text(context.trArgs('{n} rows', {'n': running!.accepted}), style: small),
              ],
            )
          else if (e.installed && e.dataset != null)
            Wrap(
              spacing: AppTokens.s4,
              runSpacing: AppTokens.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(context.tr('Installed')),
                ),
                IconButton(
                  tooltip: context.tr('View records'),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  onPressed: () => onView(e.dataset!),
                ),
                if (e.kind == 'labeled_text')
                  TextButton(onPressed: () => onUseAsSeeds(e.dataset!), child: Text(context.tr('Use as seeds'))),
                if (e.kind == 'problem_answer')
                  TextButton(onPressed: () => onUseAsProblems(e.dataset!), child: Text(context.tr('Use as problems'))),
              ],
            )
          else
            FilledButton.icon(
              onPressed: onInstall,
              icon: Icon(e.bundled ? Icons.bolt : Icons.cloud_download_outlined, size: 16),
              label: Text(e.bundled ? context.tr('Install now') : context.tr('Download')),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(fontSize: 11, color: color)),
  );
}
