import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'datagen_api.dart';

/// Opens the import dialog; `true` when an import job was started.
Future<bool?> showDatagenImportDialog(BuildContext context) =>
    showDialog<bool>(context: context, builder: (_) => const _ImportDialog());

/// The daemon reads an inline file of at most 8 MB; bigger goes by URL.
const _maxFileBytes = 8 * 1024 * 1024;

const _licenses = ['MIT', 'Apache-2.0', 'CC-BY-4.0', 'CC-BY-SA-4.0', 'CC0-1.0', 'private', 'unknown'];

/// Import a dataset that is not in the catalog: a file, a URL, or any public
/// Hugging Face dataset. Nothing is written until Import: Preview asks the
/// daemon (`POST /api/datagen/import/preview`) for the columns, a guessed
/// kind and mapping, and the first rows as the records they would become —
/// or why each would be dropped. The license is required because it travels
/// with the records. Same flow as the web page's import drawer.
class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  String _tab = 'file';
  ({String name, String content})? _file;
  final _url = TextEditingController();
  final _hfDataset = TextEditingController();
  String? _hfConfig;
  String? _hfSplit;
  final _name = TextEditingController();
  final _maxRecords = TextEditingController();
  final _license = TextEditingController();
  final _attribution = TextEditingController();
  Map<String, dynamic>? _preview;
  String? _kind;
  Map<String, String?> _mapping = {};
  bool _stale = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_url, _hfDataset, _name, _maxRecords, _license, _attribution]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _source() => switch (_tab) {
    'file' =>
      _file == null
          ? null
          : {
              'file': {'name': _file!.name, 'content': _file!.content},
            },
    'url' => _url.text.trim().isEmpty ? null : {'url': _url.text.trim()},
    _ =>
      _hfDataset.text.trim().isEmpty
          ? null
          : {
              'hf': {'dataset': _hfDataset.text.trim(), 'config': ?_hfConfig, 'split': ?_hfSplit},
            },
  };

  Map<String, String> get _cleanMapping => {
    for (final e in _mapping.entries)
      if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
  };

  void _reset() => setState(() {
    _preview = null;
    _kind = null;
    _mapping = {};
    _error = null;
  });

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jsonl', 'ndjson', 'json', 'csv', 'tsv'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.size > _maxFileBytes) {
      setState(() => _error = context.tr('The file is larger than 8 MB — import it from a URL instead'));
      return;
    }
    try {
      final content = utf8.decode(f.bytes!);
      _reset();
      setState(() => _file = (name: f.name, content: content));
    } on FormatException {
      setState(() => _error = context.tr('UTF-8 only. In Excel: Save As → CSV UTF-8.'));
    }
  }

  /// Ask for a preview. A new kind drops the mapping so the daemon guesses one for it.
  Future<void> _runPreview({String? kind, bool keepMapping = true}) async {
    final src = _source();
    if (src == null) {
      setState(() => _error = context.tr('Choose a file, a URL or a dataset first'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final k = kind ?? _kind;
      final body = await ref
          .read(apiClientProvider)
          .post(
            '/api/datagen/import/preview',
            body: {'source': src, 'kind': ?k, if (keepMapping && _cleanMapping.isNotEmpty) 'mapping': _cleanMapping},
          );
      final p = Map<String, dynamic>.from(body as Map);
      final suggested = p['suggested'] as Map?;
      setState(() {
        _preview = p;
        _stale = false;
        _kind = k ?? suggested?['kind'] as String?;
        if (!keepMapping || _cleanMapping.isEmpty) {
          _mapping = {for (final e in ((suggested?['mapping'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
        }
        if (p['config'] is String) _hfConfig = p['config'] as String;
        if (p['split'] is String) _hfSplit = p['split'] as String;
        if (_license.text.isEmpty && p['license'] is String) _license.text = p['license'] as String;
        if (_name.text.isEmpty) {
          final n = _tab == 'file'
              ? _file?.name.replaceAll(RegExp(r'\.[^.]+$'), '')
              : (_tab == 'hf' ? _hfDataset.text.split('/').last : null);
          if (n != null && n.isNotEmpty) _name.text = n;
        }
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _preview = null;
        _busy = false;
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  bool get _missingRequired =>
      _kind == null || (datagenKindFields[_kind] ?? const []).any((f) => f.$2 && (_mapping[f.$1] ?? '').isEmpty);

  Future<void> _import() async {
    final src = _source();
    if (src == null || _kind == null) return;
    if (_license.text.trim().isEmpty) {
      setState(() => _error = context.tr('Say the license, or private / unknown'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final max = int.tryParse(_maxRecords.text.trim());
      await ref
          .read(apiClientProvider)
          .post(
            '/api/datagen/jobs',
            body: {
              'pipeline': 'import',
              'source': src,
              'kind': _kind,
              'mapping': _cleanMapping,
              if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
              'maxRecords': ?max,
              'license': _license.text.trim(),
              if (_attribution.text.trim().isNotEmpty) 'attribution': _attribution.text.trim(),
            },
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  InputDecoration _deco(String label, {String? help}) => InputDecoration(
    labelText: context.tr(label),
    helperText: help == null ? null : context.tr(help),
    border: const OutlineInputBorder(),
    isDense: true,
  );

  Widget _sourceInput() => switch (_tab) {
    'file' => Row(
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file, size: 16),
          label: Text(context.tr('Choose file')),
          onPressed: _busy ? null : _pickFile,
        ),
        const SizedBox(width: AppTokens.s8),
        Expanded(
          child: Text(
            _file?.name ?? context.tr('A .jsonl, .json, .csv or .tsv file, UTF-8'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ),
      ],
    ),
    'url' => TextField(
      controller: _url,
      decoration: _deco('URL').copyWith(hintText: 'https://…/data.jsonl'),
      onChanged: (_) => _reset(),
      onSubmitted: (_) => _runPreview(keepMapping: false),
    ),
    _ => Row(
      children: [
        Expanded(
          child: TextField(
            controller: _hfDataset,
            decoration: _deco('Hugging Face dataset').copyWith(hintText: 'owner/dataset'),
            onChanged: (_) {
              _hfConfig = null;
              _hfSplit = null;
              _reset();
            },
            onSubmitted: (_) => _runPreview(keepMapping: false),
          ),
        ),
        if ((_preview?['splits'] as List?)?.isNotEmpty ?? false) ...[
          const SizedBox(width: AppTokens.s8),
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<String>(
              initialValue: '$_hfConfig/$_hfSplit',
              decoration: _deco('Config · split'),
              items: [
                for (final s in (_preview!['splits'] as List).whereType<Map>())
                  DropdownMenuItem(
                    value: '${s['config']}/${s['split']}',
                    child: Text('${s['config']} · ${s['split']}'),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                final i = v.indexOf('/');
                setState(() {
                  _hfConfig = v.substring(0, i);
                  _hfSplit = v.substring(i + 1);
                  _stale = true;
                });
              },
            ),
          ),
        ],
      ],
    ),
  };

  List<Widget> _previewSection() {
    final p = _preview!;
    final c = context.colors;
    final columns = ((p['columns'] as List?) ?? const []).map((e) => '$e').toList();
    final fields = datagenKindFields[_kind] ?? const [];
    final records = (p['records'] as List?) ?? const [];
    return [
      Wrap(
        spacing: AppTokens.s8,
        runSpacing: AppTokens.s8,
        children: [
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: ValueKey('kind-$_kind'),
              initialValue: _kind,
              decoration: _deco('Kind'),
              items: [for (final k in datagenKindFields.keys) DropdownMenuItem(value: k, child: Text(context.tr(k)))],
              onChanged: (k) {
                if (k == null) return;
                setState(() => _kind = k);
                _runPreview(kind: k, keepMapping: false);
              },
            ),
          ),
          for (final (field, required) in fields)
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String?>(
                key: ValueKey('map-$_kind-$field-${_mapping[field]}'),
                initialValue: columns.contains(_mapping[field]) ? _mapping[field] : null,
                decoration: _deco(required ? '$field *' : field),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final col in columns)
                    DropdownMenuItem<String?>(
                      value: col,
                      child: Text(col, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _mapping[field] = v;
                  _stale = true;
                }),
              ),
            ),
        ],
      ),
      if (p['mappingError'] is String)
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.s8),
          child: Text('${p['mappingError']}', style: const TextStyle(color: Colors.orange, fontSize: 12)),
        ),
      if (p['partial'] == true)
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.s8),
          child: Text(
            context.tr('The dataset viewer serves only the first part of this split.'),
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
        ),
      const SizedBox(height: AppTokens.s8),
      for (final r in records.whereType<Map>())
        Container(
          margin: const EdgeInsets.only(bottom: AppTokens.s4),
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8, vertical: AppTokens.s4),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(4)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  r['record'] is Map ? _recordText(r['record'] as Map, fields) : '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: AppTokens.s8),
              Text(
                r['rejected'] is String ? '${r['rejected']}' : context.tr('kept'),
                style: TextStyle(fontSize: 11, color: r['rejected'] is String ? Colors.red : Colors.green),
              ),
            ],
          ),
        ),
      const SizedBox(height: AppTokens.s12),
      Wrap(
        spacing: AppTokens.s8,
        runSpacing: AppTokens.s8,
        children: [
          SizedBox(
            width: 220,
            child: TextField(controller: _name, decoration: _deco('Dataset name')),
          ),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _maxRecords,
              keyboardType: TextInputType.number,
              decoration: _deco('Max records', help: 'Empty: 20,000'),
            ),
          ),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _license,
              decoration: _deco('License *').copyWith(
                suffixIcon: PopupMenuButton<String>(
                  tooltip: context.tr('License'),
                  icon: const Icon(Icons.arrow_drop_down),
                  onSelected: (v) => setState(() => _license.text = v),
                  itemBuilder: (_) => [for (final l in _licenses) PopupMenuItem(value: l, child: Text(l))],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _attribution,
              decoration: _deco('Attribution').copyWith(hintText: context.tr('Author, source')),
            ),
          ),
        ],
      ),
    ];
  }

  String _recordText(Map rec, List<(String, bool)> fields) {
    if (_kind == 'chat') {
      return ((rec['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => '${m['role']}: ${m['content']}')
          .join(' · ');
    }
    return [
      for (final (f, _) in fields)
        if (rec[f] != null) '$f: ${rec[f]}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final total = p?['total'];
    return AlertDialog(
      title: Text(context.tr('Import dataset')),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'file', label: Text(context.tr('File'))),
                    const ButtonSegment(value: 'url', label: Text('URL')),
                    const ButtonSegment(value: 'hf', label: Text('Hugging Face')),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _tab = s.first);
                    _reset();
                  },
                ),
              ),
              const SizedBox(height: AppTokens.s12),
              _sourceInput(),
              const SizedBox(height: AppTokens.s12),
              Wrap(
                spacing: AppTokens.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(context.tr(p == null ? 'Preview' : 'Refresh preview')),
                    onPressed: _busy ? null : () => _runPreview(keepMapping: p != null),
                  ),
                  if (total is num)
                    Text(
                      '${context.trArgs('{n} rows', {'n': total})}${p?['format'] is String ? ' · ${p!['format']}' : ''}',
                      style: TextStyle(fontSize: 12, color: context.colors.textMuted),
                    ),
                  if (_stale)
                    Text(
                      context.tr('Changed — refresh the preview'),
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.s12),
              if (p != null) ..._previewSection(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.s8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
        FilledButton(
          onPressed: _busy || p == null || _missingRequired ? null : _import,
          child: Text(context.tr('Import')),
        ),
      ],
    );
  }
}
