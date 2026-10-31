import 'package:flutter/material.dart';

import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';
import '../dock/workbench_provider.dart';

/// The agent's current artifact above the Browser pane, with its Close.
class ArtifactHeader extends StatelessWidget {
  const ArtifactHeader({
    super.key,
    required this.artifact,
    required this.onClose,
    this.onOpen,
  });
  final WorkbenchArtifact artifact;
  final VoidCallback onClose;

  /// Shows the artifact when the pane did not do so by itself.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.widgets_outlined, size: 16, color: c.accent),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: Text(artifact.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.textPrimary, fontWeight: FontWeight.w700)),
          ),
          Text(artifact.mode, style: TextStyle(color: c.textMuted, fontSize: 12)),
          if (onOpen != null)
            TextButton(onPressed: onOpen, child: Text(context.tr('Open'))),
          IconButton(
            tooltip: context.tr('Close artifact'),
            icon: const Icon(Icons.close, size: 16),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// A static artifact's files, each opened in place as text.
class ArtifactFiles extends StatefulWidget {
  const ArtifactFiles({super.key, required this.files, required this.readFile});
  final List<String> files;
  final Future<String> Function(String path) readFile;

  @override
  State<ArtifactFiles> createState() => _ArtifactFilesState();
}

class _ArtifactFilesState extends State<ArtifactFiles> {
  String? _openFile;
  String? _content;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_openFile == null) {
      return ListView(
        children: [
          for (final f in widget.files)
            ListTile(
              dense: true,
              leading: const Icon(Icons.insert_drive_file_outlined, size: 16),
              title: Text(f, style: const TextStyle(fontSize: 12)),
              onTap: () async {
                final content = await widget.readFile(f);
                if (!mounted) return;
                setState(() {
                  _openFile = f;
                  _content = content;
                });
              },
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s12, vertical: AppTokens.s4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() {
                  _openFile = null;
                  _content = null;
                }),
                icon: const Icon(Icons.arrow_back, size: 14),
                label: Text(context.tr('Files')),
              ),
              const SizedBox(width: AppTokens.s8),
              Expanded(
                child: Text(_openFile!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textMuted, fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.s12),
            child: SelectableText(
              _content ?? '',
              style: TextStyle(
                color: c.textSecondary,
                fontFamily: AppTokens.fontMono,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
