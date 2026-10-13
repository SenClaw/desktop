import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'datagen_api.dart';

/// Opens the "new datagen job" dialog; `true` when a job was started.
Future<bool?> showDatagenJobDialog(BuildContext context) =>
    showDialog<bool>(context: context, builder: (_) => const _JobDialog());

class _JobDialog extends ConsumerStatefulWidget {
  const _JobDialog();

  @override
  ConsumerState<_JobDialog> createState() => _JobDialogState();
}

class _JobDialogState extends ConsumerState<_JobDialog> {
  String _pipeline = 'expand_seeds';
  final _text = <String, TextEditingController>{};
  final _choice = <String, Object?>{
    'mode': 'new',
    'checkLabel': 'auto',
    'multiHop': true,
    'verify': true,
    'format': 'sharegpt',
  };
  bool _busy = false;
  String? _error;

  TextEditingController _c(String key, [String initial = '']) =>
      _text.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// A new pipeline starts from an empty form: a field two pipelines share
  /// (Target) must not carry the last one's value into a job that never
  /// showed it. Old controllers are disposed after the frame that drops their
  /// fields, never while those fields are still mounted.
  void _switchPipeline(String v) {
    if (v == _pipeline) return;
    final old = _text.values.toList();
    setState(() {
      _pipeline = v;
      _text.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  Future<void> _start() async {
    final fields = <String, Object?>{..._choice, for (final e in _text.entries) e.key: e.value.text};
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post('/api/datagen/jobs', body: buildDatagenBody(_pipeline, fields));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // The daemon's refusal ("seeds is empty", "2 jobs are already running")
      // is the useful text; show it as is.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Widget _field(String key, String label, {String? help, int lines = 1, String initial = '', bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s12),
        child: TextField(
          controller: _c(key, initial),
          maxLines: lines,
          minLines: lines,
          keyboardType: number ? TextInputType.number : TextInputType.multiline,
          decoration: InputDecoration(
            labelText: context.tr(label),
            helperText: help == null ? null : context.tr(help),
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _dropdown(String key, String label, Map<Object, String> options) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s12),
        child: DropdownButtonFormField<Object>(
          initialValue: _choice[key],
          decoration: InputDecoration(labelText: context.tr(label), border: const OutlineInputBorder(), isDense: true),
          items: [
            for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(context.tr(e.value))),
          ],
          onChanged: (v) => setState(() => _choice[key] = v),
        ),
      );

  Widget _switch(String key, String label) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr(label)),
        value: _choice[key] == true,
        onChanged: (v) => setState(() => _choice[key] = v),
      );

  List<Widget> _pipelineFields() => switch (_pipeline) {
        'expand_seeds' => [
            _field('seeds', 'Example requests',
                lines: 6,
                help: 'One per line. Prefix a label with " | " to make a labelled set, e.g. "browser | find a cheap flight".'),
            _field('labels', 'Label descriptions', lines: 3, help: 'Optional, one per line: "label: what it means".'),
            _dropdown('mode', 'Mode', const {'new': 'New requests', 'evolve': 'Evolve seeds'}),
            _dropdown('checkLabel', 'Check labels', const {'auto': 'Auto', 'on': 'On', 'off': 'Off'}),
            _field('target', 'Target', initial: '50', number: true),
          ],
        'doc_qa' => [
            _field('texts', 'Documents', lines: 6, help: 'Paste text; separate documents with a line holding only ---.'),
            _field('paths', 'Files or folders', lines: 2, help: 'Absolute paths of .md/.txt files or folders, one per line.'),
            _field('target', 'Target', initial: '50', number: true),
            _field('perPassage', 'Pairs per passage', initial: '3', number: true),
            _switch('multiHop', 'Multi-hop'),
            _switch('verify', 'Verify grounding'),
          ],
        'reasoning_traces' => [
            _field('problems', 'Problems',
                lines: 6, help: 'One per line. Add the known answer after " || " to have it checked.'),
            _field('target', 'Target', number: true, help: 'Empty solves every problem.'),
            _field('maxIterations', 'Improvement rounds', initial: '3', number: true),
            _field('threshold', 'Score threshold', initial: '0.7', number: true),
          ],
        'executable_qa' => [
            _field('seeds', 'Example problems',
                lines: 6,
                help:
                    'One per line, optionally "question || answer". Generated programs run in the sandbox; the job refuses to start without an enforced one.'),
            _field('target', 'Target', initial: '50', number: true),
            _field('timeoutMs', 'Program timeout (ms)', initial: '10000', number: true),
          ],
        _ => [
            _field('chats', 'Chats',
                lines: 3,
                help:
                    'Chat ids, one per line, or * for every chat with recorded turns. Only chats with the trajectory turned on have any.'),
            _dropdown('format', 'Format', const {'sharegpt': 'sharegpt', 'alpaca': 'alpaca', 'messages': 'messages'}),
            _field('maxRecords', 'Max records', number: true),
          ],
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('New datagen job')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.s12),
                child: DropdownButtonFormField<String>(
                  initialValue: _pipeline,
                  decoration: InputDecoration(
                      labelText: context.tr('Pipeline'), border: const OutlineInputBorder(), isDense: true),
                  items: [
                    for (final p in datagenPipelines) DropdownMenuItem(value: p, child: Text(context.tr(p))),
                  ],
                  onChanged: (v) => _switchPipeline(v ?? _pipeline),
                ),
              ),
              _field('name', 'Dataset name', help: 'Empty uses the pipeline and the date.'),
              ..._pipelineFields(),
              if (_pipeline != 'export_logs') ...[
                _field('language', 'Language', help: 'Leave empty to write in the language of the input.'),
                _field('maxLlmCalls', 'Max LLM calls', number: true, help: 'Hard cap for the whole job. Empty uses the default.'),
                _field('profile', 'Model profile', help: 'LLM config id or label. Empty uses the active model.'),
              ],
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: _busy ? null : _start, child: Text(context.tr('Start'))),
      ],
    );
  }
}
