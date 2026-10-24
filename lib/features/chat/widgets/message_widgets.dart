import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/transport/api_client.dart';
import '../../../core/transport/connection.dart';
import '../../../core/transport/runtime_missing.dart';
import '../../../models/chat_message.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/app_markdown.dart';
import '../../../widgets/runtime_missing_banner.dart' show showRuntimeMissingSnack;
import '../../dock/dispatch_provider.dart';
import '../audio_service.dart';
import 'form_card.dart';
import 'question_card.dart';
import 'tool_params.dart';
import 'widget_card.dart';

/// Dispatches a [ChatMessage] to the right bubble/card by kind.
class MessageItem extends StatelessWidget {
  const MessageItem({
    super.key,
    required this.message,
    required this.onPermission,
    required this.onQuestion,
    required this.onForm,
  });
  final ChatMessage message;
  final void Function(String requestId, String optionKey) onPermission;
  final void Function(
    String requestId,
    Map<int, dynamic> answers,
    Map<int, String> otherTexts,
  ) onQuestion;
  final void Function(
    String requestId,
    Map<String, dynamic> values,
    bool submitted,
  ) onForm;

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case MessageKind.tool:
        return _ToolCard(message: message);
      case MessageKind.permission:
        return _PermissionCard(message: message, onResolve: onPermission);
      case MessageKind.question:
        return QuestionCard(message: message, onSubmit: onQuestion);
      case MessageKind.form:
        return FormCard(message: message, onSubmit: onForm);
      case MessageKind.widget:
        return WidgetCard(spec: message.widget ?? const {});
      case MessageKind.system:
        return _SystemNote(text: message.text ?? '');
      default:
        return _TextBubble(message: message);
    }
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Cross-channel user messages (e.g. from the mobile channel_app) arrive as
    // MessageKind.other. They're still the user's own input, just from another
    // client, so render them user-side (right-aligned, user bubble) while the
    // source label below keeps showing where they came from ("mobile-app").
    final isUser = message.kind == MessageKind.user;
    final isOther = message.kind == MessageKind.other;
    final userSide = isUser || isOther;
    final align = userSide ? Alignment.centerRight : Alignment.centerLeft;
    final bg = userSide ? c.bubbleUser : c.bubbleAgent;
    final parts = _splitThink(message.text ?? '');
    // Reasoning is a line of its own, above whatever the message says; every
    // block of it goes into that one line.
    final thinks = [for (final p in parts) if (p.isThink) p.text];
    final body = [for (final p in parts) if (!p.isThink) p];

    // Don't render an empty bubble (e.g. a reasoning-only message after the
    // tags were stripped) — that was the stray "pending" box at the top.
    if (parts.isEmpty &&
        message.attachments.isEmpty &&
        !message.streaming) {
      return const SizedBox.shrink();
    }

    // A message that is nothing but reasoning is just that line, with its size
    // after it in place of the bubble's footer.
    if (thinks.isNotEmpty && body.isEmpty && message.attachments.isEmpty) {
      return _ThinkLine(
        text: thinks.join('\n\n'),
        tokens: message.streaming
            ? '…'
            : message.tokens == null
                ? null
                : context.trArgs('{n} tok', {'n': message.tokens}),
      );
    }

    final bubble = Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s24,
        vertical: AppTokens.s4,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16,
            vertical: AppTokens.s12,
          ),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Only label real incoming senders, never the agent itself.
              if (message.kind == MessageKind.other && message.sender != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.s4),
                  child: Text(
                    message.sender!,
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              for (final part in body)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: AppMarkdown(
                    part.text,
                    style: TextStyle(
                        color: c.textPrimary, height: 1.5, fontSize: 14),
                  ),
                ),
              if (message.attachments.isNotEmpty)
                _Attachments(attachments: message.attachments),
              // Footer: tokens + actions (left) · timestamp (bottom-right).
              Builder(builder: (_) {
                final hasContent = body.isNotEmpty;
                final isAgent = message.kind == MessageKind.agent;
                final showTokens =
                    message.tokens != null || message.streaming;
                // Agent messages get the full row (copy · save · TTS); user-side
                // messages (own input, incl. cross-channel "other") get copy only.
                final showActions = !message.streaming &&
                    hasContent &&
                    (isAgent || userSide);
                final contentText = body.map((p) => p.text).join('\n\n');
                final time = hasContent ? _fmtTime(context, message.ts) : '';
                if (!showTokens && !showActions && time.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: AppTokens.s6),
                  child: Row(
                    // User bubbles hug their content; agent footers span so the
                    // timestamp sits flush right past the actions/tokens.
                    mainAxisSize:
                        userSide ? MainAxisSize.min : MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showTokens)
                        Padding(
                          padding: const EdgeInsets.only(right: AppTokens.s8),
                          child: Text(
                            message.streaming
                                ? '…'
                                : context.trArgs(
                                    '{n} tok', {'n': message.tokens}),
                            style:
                                TextStyle(color: c.textMuted, fontSize: 12),
                          ),
                        ),
                      if (showActions)
                        _MessageActions(
                          text: contentText,
                          showSave: isAgent,
                          showTts: isAgent,
                        ),
                      if (!userSide)
                        const Spacer()
                      else if (showActions && time.isNotEmpty)
                        const SizedBox(width: AppTokens.s8),
                      if (time.isNotEmpty)
                        Text(time,
                            style:
                                TextStyle(color: c.textMuted, fontSize: 11)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (thinks.isEmpty) return bubble;
    return Column(
      children: [_ThinkLine(text: thinks.join('\n\n')), bubble],
    );
  }
}

/// Format a message timestamp (ISO or "YYYY-MM-DD HH:MM:SS"). Within 30 minutes
/// it's relative ("now" / "Nm"); same-day → HH:mm; another day → "dd/MM HH:mm".
String _fmtTime(BuildContext context, String? s) {
  if (s == null || s.isEmpty) return '';
  final dt = DateTime.tryParse(s) ??
      (s.contains(' ') ? DateTime.tryParse(s.replaceFirst(' ', 'T')) : null);
  if (dt == null) return '';
  final l = dt.toLocal();
  final now = DateTime.now();
  final diff = now.difference(l);
  if (diff.inSeconds >= 0 && diff.inSeconds < 60) return context.tr('now');
  if (diff.inMinutes >= 0 && diff.inMinutes < 30) {
    return context.trArgs('{n}m', {'n': diff.inMinutes});
  }
  final hm =
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  final sameDay = l.year == now.year && l.month == now.month && l.day == now.day;
  if (sameDay) return hm;
  final dm = '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  return '$dm $hm';
}

/// Persistent action row under a message: Copy is always available; save-to-
/// notes and the Play/Stop TTS toggle are agent-only (a user's own input needs
/// neither). Mirrors the web MessageBubble actions.
class _MessageActions extends ConsumerStatefulWidget {
  const _MessageActions({
    required this.text,
    this.showSave = true,
    this.showTts = true,
  });
  final String text;
  final bool showSave;
  final bool showTts;
  @override
  ConsumerState<_MessageActions> createState() => _MessageActionsState();
}

class _MessageActionsState extends ConsumerState<_MessageActions> {
  String? _flash; // transient "Copied" / "Saved"

  void _flashMsg(String m) {
    setState(() => _flash = m);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s6),
      child: Row(
        children: [
          _act(Icons.copy_outlined, context.tr('Copy'), () async {
            // Resolve before the await — no BuildContext across async gaps.
            final copied = context.tr('Copied');
            await Clipboard.setData(ClipboardData(text: widget.text));
            _flashMsg(copied);
          }),
          if (widget.showSave) ...[
            const SizedBox(width: AppTokens.s4),
            _act(Icons.bookmark_add_outlined, context.tr('Save note'), () async {
              final saved = context.tr('Saved');
              final failed = context.tr('Failed');
              try {
                await ref
                    .read(apiClientProvider)
                    .post('/api/quicknotes', body: {'text': widget.text});
                _flashMsg(saved);
              } catch (_) {
                _flashMsg(failed);
              }
            }),
          ],
          if (widget.showTts) ...[
            const SizedBox(width: AppTokens.s4),
            // Play ⇄ Stop toggle: while THIS message is synthesizing/playing the
            // icon becomes a stop button; stopping also cancels a synthesis that
            // has not started playing yet.
            ValueListenableBuilder<String?>(
              valueListenable: ref.read(audioServiceProvider).speaking,
              builder: (_, speakingText, child) {
                final active = speakingText == widget.text;
                if (active) {
                  return _act(Icons.stop_circle_outlined, context.tr('Stop'),
                      () {
                    ref.read(audioServiceProvider).stop();
                  });
                }
                return _act(Icons.volume_up_outlined, context.tr('Play (TTS)'),
                    () async {
                  final ttsFailed = context.tr('TTS failed');
                  try {
                    _flashMsg(context.tr('Speaking…'));
                    await ref.read(audioServiceProvider).speak(widget.text);
                  } catch (e) {
                    final missing = runtimeMissingFrom(e);
                    if (missing != null && context.mounted) {
                      showRuntimeMissingSnack(context, ref, missing);
                    } else {
                      _flashMsg(ttsFailed);
                    }
                  }
                });
              },
            ),
          ],
          if (_flash != null) ...[
            const SizedBox(width: AppTokens.s8),
            Text(_flash!,
                style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _act(IconData icon, String tip, VoidCallback onTap) {
    final c = context.colors;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: c.textMuted),
        ),
      ),
    );
  }
}

/// A segment of an agent message: either reasoning (`<think>…`) or content.
class _Part {
  final bool isThink;
  final String text;
  const _Part(this.isThink, this.text);
}

/// Split agent text into reasoning vs content parts. Handles multiple think
/// blocks, an unterminated `<think>` (still streaming), AND a dangling
/// `</think>` whose opener was lost (streamed/stored separately) — the latter
/// is why raw `</think>` used to leak into the UI.
// Reasoning wrappers emitted by different models (mirrors the web
// reasoningBlocks util): Qwen `think`, `thinking`, DeepSeek
// `redacted_reasoning` / `redacted_thinking`. Tags may carry attributes.
const _reasoningTags = 'think|thinking|redacted_reasoning|redacted_thinking';
final _reasoningOpenRe = RegExp('<(?:$_reasoningTags)\\b[^>]*>', caseSensitive: false);
final _reasoningCloseRe = RegExp('</(?:$_reasoningTags)>', caseSensitive: false);
final _reasoningBlockRe = RegExp(
    '<(?:$_reasoningTags)\\b[^>]*>([\\s\\S]*?)(?:</(?:$_reasoningTags)>|\$)',
    caseSensitive: false);

List<_Part> _splitThink(String text) {
  var norm = text;
  final firstOpen = _reasoningOpenRe.firstMatch(norm)?.start ?? -1;
  final firstClose = _reasoningCloseRe.firstMatch(norm)?.start ?? -1;
  // Reasoning that starts the message but lost its opening tag.
  if (firstClose != -1 && (firstOpen == -1 || firstClose < firstOpen)) {
    norm = '<think>$norm';
  }
  if (!_reasoningOpenRe.hasMatch(norm)) {
    final t = norm.trim();
    return t.isEmpty ? const [] : [_Part(false, t)];
  }
  final parts = <_Part>[];
  var cursor = 0;
  for (final m in _reasoningBlockRe.allMatches(norm)) {
    if (m.start > cursor) {
      final before = norm.substring(cursor, m.start).trim();
      if (before.isNotEmpty) parts.add(_Part(false, before));
    }
    final think = (m.group(1) ?? '').trim();
    if (think.isNotEmpty) parts.add(_Part(true, think));
    cursor = m.end;
  }
  if (cursor < norm.length) {
    final rest = norm.substring(cursor).trim();
    if (rest.isNotEmpty) parts.add(_Part(false, rest));
  }
  // Strip any stray reasoning tags that slipped through, drop empties.
  return parts
      .map((p) => _Part(
          p.isThink,
          p.text
              .replaceAll(_reasoningOpenRe, '')
              .replaceAll(_reasoningCloseRe, '')
              .trim()))
      .where((p) => p.text.isNotEmpty)
      .toList();
}

/// A model's reasoning, on a line of its own: the word "think" and a caret,
/// closed; opened, the same rounded box a tool group opens into. It is never
/// part of a message bubble and never counted in a tool group.
class _ThinkLine extends StatefulWidget {
  const _ThinkLine({required this.text, this.tokens});
  final String text;

  /// The reasoning's own size, for a message that is nothing but reasoning.
  final String? tokens;
  @override
  State<_ThinkLine> createState() => _ThinkLineState();
}

class _ThinkLineState extends State<_ThinkLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _QuietFrame(
      children: [
        _QuietHeader(
          label: context.tr('think'),
          open: _open,
          onTap: () => setState(() => _open = !_open),
          trailing: [
            if (widget.tokens != null) ...[
              const SizedBox(width: AppTokens.s8),
              Text(widget.tokens!,
                  style: TextStyle(color: c.textMuted, fontSize: 12.5)),
            ],
          ],
        ),
        if (_open)
          _QuietBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: _kStepPadX, vertical: AppTokens.s12),
              child: AppMarkdown(
                widget.text,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s24,
        vertical: AppTokens.s4,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s12,
          vertical: AppTokens.s8,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
        child: Row(
          children: [
            Icon(
              message.toolOk ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: message.toolOk ? AppTokens.cyan : AppTokens.danger,
            ),
            const SizedBox(width: AppTokens.s8),
            Flexible(
              child: Text(
                message.toolName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: AppTokens.s8),
            Expanded(
              flex: 2,
              child: Text(
                message.toolTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
            if (message.toolSummary.isNotEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: AppTokens.s8),
                  child: Text(
                    message.toolSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.message, required this.onResolve});
  final ChatMessage message;
  final void Function(String requestId, String optionKey) onResolve;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final resolvedKey = message.resolvedKey;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s24,
        vertical: AppTokens.s8,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.s16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: AppTokens.warning.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(AppTokens.rLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 16, color: AppTokens.warning),
                const SizedBox(width: AppTokens.s8),
                Text(
                  message.permTitle.isNotEmpty
                      ? message.permTitle
                      : context.tr('Permission required'),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (message.permContent.isNotEmpty) ...[
              const SizedBox(height: AppTokens.s8),
              ToolParams(content: message.permContent),
            ],
            const SizedBox(height: AppTokens.s12),
            if (message.resolved)
              Text(
                context.trArgs('Resolved: {key}',
                    {'key': resolvedKey ?? context.tr('answered')}),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              )
            else
              Wrap(
                spacing: AppTokens.s8,
                runSpacing: AppTokens.s8,
                children: [
                  for (final opt in message.permOptions)
                    FilledButton.tonal(
                      onPressed: () =>
                          onResolve(message.requestId, '${opt['key']}'),
                      child: Text('${opt['label'] ?? opt['key']}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SystemNote extends StatelessWidget {
  const _SystemNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s24,
        vertical: AppTokens.s8,
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}

/// Collapse any run of whitespace (incl. newlines from pretty-printed JSON
/// results) into single spaces so a Text with maxLines+ellipsis stays on one
/// tidy line instead of overflowing the card.
String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Human verb for a tool name (claude-code style summary), ported from the web
/// ToolGroupCard.toolVerb.
String toolVerb(String raw) {
  // strip mcp__server__ prefix to the bare tool
  final name = raw.contains('__') ? raw.split('__').last : raw;
  switch (name) {
    case 'Read':
    case 'read_file':
      return 'Read a file';
    case 'Write':
    case 'write_file':
      return 'Created a file';
    case 'Edit':
    case 'NotebookEdit':
    case 'edit_file':
      return 'Edited a file';
    case 'Bash':
    case 'bash':
      return 'Ran a command';
    case 'Glob':
      return 'Searched files';
    case 'Grep':
      return 'Searched content';
    case 'WebFetch':
      return 'Fetched a URL';
    case 'WebSearch':
      return 'Searched the web';
    case 'ToolSearch':
      return 'Discovered a tool';
    case 'Skill':
      return 'Invoked a skill';
    case 'Task':
      return 'Spawned a subagent';
  }
  if (raw.startsWith('mcp__browser')) return 'Browser action';
  if (raw.startsWith('mcp__memory') || raw.startsWith('mcp__senclaw-memory')) {
    return 'Memory lookup';
  }
  if (raw.startsWith('mcp__wiki') || raw.startsWith('mcp__senclaw-wiki')) {
    return 'Wiki action';
  }
  return 'Used a tool';
}

/// The one line that says what a step was *for*.
///
/// The daemon forwards the model's own `description` for the tools that take
/// one (`Bash`, `Task`) — "Survey existing skills and the wiki capability"
/// rather than "Ran a command". Every other tool, and every row persisted
/// before the field existed, falls back to the tool's verb: a truthful
/// summary beats an invented sentence.
String stepHeadline(BuildContext context, ChatMessage t) {
  final own = t.toolDescription;
  if (own.isNotEmpty) return own;
  // No description of its own, so build one line out of what the tool is and
  // what it acted on. `toolTitle` is the display title (a command, a path, a
  // query) and is safe to show; `toolSummary` is not — for an MCP tool it is
  // the raw JSON result, which is what made these rows unreadable.
  final target = _oneLine(t.toolTitle);
  final verb = context.tr(toolVerb(t.toolName));
  if (!_hasKnownVerb(t.toolName)) return target.isNotEmpty ? target : verb;
  // A title that is just the tool's own name ("ToolSearch") repeats the verb
  // in a second spelling and tells the reader nothing.
  final bare =
      t.toolName.contains('__') ? t.toolName.split('__').last : t.toolName;
  if (target.isEmpty ||
      target == verb ||
      target == bare ||
      target == t.toolName) {
    return verb;
  }
  return '$verb · $target';
}

/// True when [toolVerb] recognised the tool rather than falling back to
/// "Used a tool". An unrecognised MCP tool has no useful verb, so its own
/// display title ("Browser Search") is the better label.
bool _hasKnownVerb(String raw) => toolVerb(raw) != 'Used a tool';

/// The clauses a collapsed group counts by name. Every other tool folds into
/// one "Used n tools" so the line stays short enough to skim.
const _countedVerbs = {
  'Read a file': 'Read {n} files',
  'Edited a file': 'Edited {n} files',
  'Wrote a file': 'Wrote {n} files',
  'Ran a command': 'Ran {n} commands',
};

enum _FileKind { read, edit, write }

_FileKind? _fileKindOf(String raw) {
  final name = raw.contains('__') ? raw.split('__').last : raw;
  switch (name) {
    case 'Read':
    case 'read_file':
      return _FileKind.read;
    case 'Edit':
    case 'NotebookEdit':
    case 'edit_file':
      return _FileKind.edit;
    case 'Write':
    case 'write_file':
      return _FileKind.write;
  }
  return null;
}

/// A Write whose diff only adds lines made a new file; one that also keeps or
/// drops lines rewrote a file that was there. No diff says nothing either way.
bool _writeIsUpdate(ChatMessage t) {
  final diff = t.toolContentMap?['diff'];
  if (diff is! String || diff.isEmpty) return false;
  for (final l in diff.split('\n')) {
    if (l.startsWith('+++') || l.startsWith('---')) continue;
    if (l.startsWith('-') || l.startsWith(' ')) return true;
  }
  return false;
}

/// The clause of the collapsed line a step is counted under, or null for a tool
/// the line does not name.
String? _summaryKind(ChatMessage t) {
  switch (_fileKindOf(t.toolName)) {
    case _FileKind.read:
      return 'Read a file';
    case _FileKind.edit:
      return 'Edited a file';
    // Writing over a file that existed is an edit, as its row says "Updated".
    case _FileKind.write:
      return _writeIsUpdate(t) ? 'Edited a file' : 'Wrote a file';
    case null:
      return toolVerb(t.toolName) == 'Ran a command' ? 'Ran a command' : null;
  }
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// What a group of tool calls did, counted by kind — "Ran 4 commands (1
/// failed), read 2 files". It is the collapsed line of [ToolGroupCard]: the
/// rows hold what each step was *for*, this line only how much work there was.
String toolGroupSummary(BuildContext context, List<ChatMessage> tools) {
  // Insertion-ordered, so the line reads in the order the work happened.
  final counts = <String?, int>{};
  final failed = <String?, int>{};
  for (final t in tools) {
    final kind = _summaryKind(t);
    counts[kind] = (counts[kind] ?? 0) + 1;
    if (!t.toolOk) failed[kind] = (failed[kind] ?? 0) + 1;
  }
  // Tools without a name of their own are the least informative; last.
  final other = counts.remove(null);
  final parts = <String>[];
  void add(String? kind, String text) {
    final f = failed[kind] ?? 0;
    final full =
        f == 0 ? text : '$text ${context.trArgs('({n} failed)', {'n': f})}';
    parts.add(parts.isEmpty ? full : _lowerFirst(full));
  }

  counts.forEach((kind, n) => add(
      kind,
      n == 1
          ? context.tr(kind!)
          : context.trArgs(_countedVerbs[kind]!, {'n': n})));
  if (other != null) {
    add(
        null,
        other == 1
            ? context.tr('Used a tool')
            : context.trArgs('Used {n} tools', {'n': other}));
  }
  return parts.join(', ');
}

/// Lines added and removed across a group's successful writes and edits; null
/// when none of them carried a diff.
({int plus, int minus})? toolGroupStats(List<ChatMessage> tools) {
  var plus = 0, minus = 0, any = false;
  for (final t in tools) {
    if (!t.toolOk) continue;
    final s = _diffStatsOf(t);
    if (s == null) continue;
    any = true;
    plus += s.plus;
    minus += s.minus;
  }
  return any ? (plus: plus, minus: minus) : null;
}

/// +/− line counts of a Write/Edit result, or null when it carries no diff.
({int plus, int minus})? _diffStatsOf(ChatMessage t) {
  final w = _DiffView.forTool(t);
  if (w is! _DiffView || (w.plus == null && w.minus == null)) return null;
  return (plus: w.plus ?? 0, minus: w.minus ?? 0);
}

/// The `+N −M` after a file's name or a group's summary. Green and red, never
/// bold: it is a figure on a muted line, not a heading.
List<InlineSpan> _statSpans(({int plus, int minus}) s) => [
      TextSpan(
          text: '+${s.plus}', style: const TextStyle(color: AppTokens.success)),
      const TextSpan(text: ' '),
      TextSpan(
          text: '−${s.minus}', style: const TextStyle(color: AppTokens.danger)),
    ];

/// A Read / Write / Edit step taken apart, so its row can name the file the way
/// the other steps name what they were for: `Read  main.dart (10–40)  · lib`.
class _FileStep {
  const _FileStep({
    required this.verb,
    required this.name,
    required this.dir,
    this.range,
    this.stats,
  });
  final String verb;
  final String name;
  final String dir;

  /// "(10–40)" for a partial read; absent for the whole file.
  final String? range;
  final ({int plus, int minus})? stats;
}

_FileStep? _fileStepOf(BuildContext context, ChatMessage t) {
  final kind = _fileKindOf(t.toolName);
  if (kind == null) return null;
  final c = t.toolContentMap;
  var path =
      '${c?['path'] ?? c?['filePath'] ?? c?['file_path'] ?? c?['notebook_path'] ?? ''}';
  // A refused call has no payload, but the daemon still titles it "Edit
  // main.rs" — enough to name the file.
  if (path.isEmpty) {
    final m = RegExp(r'^(?:Read|Write|Edit|NotebookEdit) (.+)$')
        .firstMatch(t.toolTitle);
    if (m == null) return null;
    path = m.group(1)!;
  }
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  final name = path.substring(cut + 1);
  if (name.isEmpty) return null;

  String? range;
  if (kind == _FileKind.read && c != null) {
    final start = c['lineStart'], end = c['lineEnd'], total = c['totalLines'];
    if (start is num && end is num) {
      final whole = start == 1 && total is num && end >= total;
      if (!whole) range = '(${start.toInt()}–${end.toInt()})';
    }
  }
  return _FileStep(
    verb: switch (kind) {
      _FileKind.read => context.tr('Read'),
      _FileKind.edit => context.tr('Edited'),
      _FileKind.write =>
        context.tr(_writeIsUpdate(t) ? 'Updated' : 'Wrote'),
    },
    name: name,
    dir: cut > 0 ? path.substring(0, cut) : '',
    range: range,
    stats: t.toolOk && kind != _FileKind.read ? _diffStatsOf(t) : null,
  );
}

/// The tail of a long folder path: the end is what tells two copies of one file
/// apart.
String _shortDir(String dir, {int max = 28}) {
  if (dir.length <= max) return dir;
  final tail = dir.substring(dir.length - (max - 1));
  final slash = tail.indexOf('/');
  return '…${slash >= 0 ? tail.substring(slash) : tail}';
}

/// Collapsible card that groups CONSECUTIVE tool calls (web `ToolGroupCard`
/// parity).
///
/// Collapsed it is one muted line — what the group did, counted by kind — with
/// a small caret after it. Expanded, a rounded list holds one row per step,
/// headed by the model's own description of it, with the command (or diff, or
/// output) one more tap away — the detail views are unchanged, only what leads
/// to them is.
class ToolGroupCard extends StatefulWidget {
  const ToolGroupCard({super.key, required this.tools});
  final List<ChatMessage> tools;
  @override
  State<ToolGroupCard> createState() => _ToolGroupCardState();
}

class _ToolGroupCardState extends State<ToolGroupCard> {
  bool _open = false;

  /// A lone step of a kind the summary does not name ("Browser Search · query")
  /// keeps its own headline: "Used a tool" would say less than the row does.
  String _header(BuildContext context) {
    final tools = widget.tools;
    if (tools.length == 1 && _summaryKind(tools.first) == null) {
      return stepHeadline(context, tools.first);
    }
    return toolGroupSummary(context, tools);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stats = toolGroupStats(widget.tools);
    return _QuietFrame(
      children: [
        // No status icon: a failure is said in words ("1 failed") and marked
        // again on the step that failed.
        _QuietHeader(
          label: _header(context),
          open: _open,
          onTap: () => setState(() => _open = !_open),
          trailing: [
            if (stats != null) ...[
              const SizedBox(width: AppTokens.s8),
              Text.rich(
                TextSpan(children: _statSpans(stats)),
                maxLines: 1,
                style: TextStyle(color: c.textSecondary, fontSize: 13.5),
              ),
            ],
          ],
        ),
        if (_open)
          _QuietBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.tools.length; i++)
                  _StepRow(tool: widget.tools[i], first: i == 0),
              ],
            ),
          ),
      ],
    );
  }
}

/// Left-aligned and capped to the same max width as message bubbles, so what is
/// built from the quiet pieces below lines up with the chat instead of
/// spanning the full width.
class _QuietFrame extends StatelessWidget {
  const _QuietFrame({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s24, vertical: AppTokens.s4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}

/// The quiet line that opens something: muted words, anything quieter after
/// them, and a caret. A tool group and a model's reasoning are both this, so
/// they read as the same kind of thing.
class _QuietHeader extends StatelessWidget {
  const _QuietHeader({
    required this.label,
    required this.open,
    required this.onTap,
    this.trailing = const [],
  });
  final String label;
  final bool open;
  final VoidCallback onTap;

  /// Figures or counts that sit between the words and the caret.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 13.5)),
              ),
              ...trailing,
              _Caret(open: open),
            ],
          ),
        ),
      );
}

/// The rounded box a [_QuietHeader] opens into.
class _QuietBox extends StatelessWidget {
  const _QuietBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      // As wide as the frame, whatever it holds: a short reasoning must not
      // open into a narrower box than a tool group.
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppTokens.s4),
      clipBehavior: Clip.antiAlias,
      // Filled, not just outlined: the light theme's border is the page's own
      // colour, so an outline alone would vanish.
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rXl),
      ),
      child: child,
    );
  }
}

/// The small solid triangle after a line of text: down when open, right when
/// closed. The glyph carries its own side padding, so it sits a few pixels
/// clear of the words without a spacer.
class _Caret extends StatelessWidget {
  const _Caret({required this.open});
  final bool open;

  @override
  Widget build(BuildContext context) => Icon(
        open ? Icons.arrow_drop_down : Icons.arrow_right,
        size: 18,
        color: context.colors.textMuted,
      );
}

/// One step inside an expanded [ToolGroupCard]: a row whose headline says what
/// the step was for, and whose body (one tap away) is the command, diff or
/// output it produced.
class _StepRow extends StatefulWidget {
  const _StepRow({required this.tool, required this.first});
  final ChatMessage tool;

  /// The first row sits against the list's own border; the rest are divided
  /// from the row above.
  final bool first;
  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  // Closed even for an edit: the row already says which file and how many
  // lines moved, and the diff is one tap away.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.tool;
    final hasDetail = t.toolContent.isNotEmpty;
    final file = _fileStepOf(context, t);
    final style = TextStyle(color: c.textSecondary, fontSize: 13.5);
    return Container(
      decoration: BoxDecoration(
        border: widget.first ? null : Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasDetail ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: _kStepPadX, vertical: 11),
              child: Row(
                children: [
                  // One line, always. Everything else — the command's output,
                  // the diff, the raw MCP payload — lives behind the caret.
                  // A step that spills a JSON result into the list is the
                  // display this replaced. A short line leaves the caret right
                  // after it; a long one fades out and pushes it to the edge.
                  Flexible(
                    child: Text.rich(
                      file == null
                          ? TextSpan(text: stepHeadline(context, t))
                          : _fileLine(c, file),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: style,
                    ),
                  ),
                  if (!t.toolOk)
                    Padding(
                      padding: const EdgeInsets.only(left: AppTokens.s8),
                      child: Text(context.tr('Failed'),
                          style: style.copyWith(color: AppTokens.danger)),
                    ),
                  if (hasDetail) _Caret(open: _open),
                ],
              ),
            ),
          ),
          if (_open && hasDetail)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                  _kStepPadX, 0, _kStepPadX, AppTokens.s12),
              padding: const EdgeInsets.all(AppTokens.s8),
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: c.sidebar,
                borderRadius: BorderRadius.circular(AppTokens.rSm),
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                // Write/Edit tools carry a structured `{path, size, diff}`
                // payload: render it as a colored code diff (web EditDetail
                // parity) instead of a raw JSON dump. Falls back to the mono
                // dump for other tools.
                child: _DiffView.forTool(t) ??
                    SelectableText(
                      t.toolContent,
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          fontFamily: AppTokens.fontMono),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `Read  main.dart (10–40) · …/lib`: the verb quiet, the file's name plain,
/// the rest quieter still — so the name is what the eye lands on.
TextSpan _fileLine(AppColors c, _FileStep f) => TextSpan(children: [
      TextSpan(text: '${f.verb}  '),
      TextSpan(text: f.name, style: TextStyle(color: c.textPrimary)),
      if (f.range != null)
        TextSpan(text: ' ${f.range}', style: TextStyle(color: c.textMuted)),
      if (f.stats != null) ...[const TextSpan(text: '  '), ..._statSpans(f.stats!)],
      if (f.dir.isNotEmpty)
        TextSpan(
            text: '${f.range != null ? ' · ' : '  '}${_shortDir(f.dir)}',
            style: TextStyle(color: c.textMuted)),
    ]);

/// Side padding of a step row; the opened detail lines up with its text.
const double _kStepPadX = 14;

/// True for the file-mutation tools (native + MCP `*_file` variants) whose
/// `content` payload should render as a code diff.
bool _isFileMutationTool(String raw) {
  final name = raw.contains('__') ? raw.split('__').last : raw;
  return name == 'Write' ||
      name == 'Edit' ||
      name == 'NotebookEdit' ||
      name == 'write_file' ||
      name == 'edit_file';
}

/// Colored unified-diff view for Write/Edit tool results — the Flutter parity of
/// the web `EditDetail`/`DiffBlock`. Renders `content.diff` line-by-line, coloring
/// `+`/`-`/`@@`/header lines; falls back to `oldString`/`newString` when a
/// structured diff isn't present. Returns null (via [forTool]) when the tool
/// isn't a file mutation or carries nothing diffable, so the caller keeps the
/// raw dump.
class _DiffView extends StatelessWidget {
  const _DiffView({required this.lines, this.path, this.plus, this.minus, this.size, this.newFile = false});

  final List<String> lines;
  final String? path;
  final int? plus;
  final int? minus;
  final int? size;
  final bool newFile;

  static const int _maxLines = 400;

  /// Build a diff view for [t] or null when not applicable.
  static Widget? forTool(ChatMessage t) {
    if (!_isFileMutationTool(t.toolName)) return null;
    final c = t.toolContentMap;
    if (c == null) return null;

    final path = (c['path'] ?? c['filePath'])?.toString();
    final size = c['size'] is num ? (c['size'] as num).toInt() : null;

    // Path 1: native unified-diff string.
    final diff = c['diff'];
    if (diff is String && diff.isNotEmpty) {
      final all = diff.split('\n');
      var plus = 0, minus = 0;
      for (final l in all) {
        if (l.startsWith('+++') || l.startsWith('---')) continue;
        if (l.startsWith('+')) {
          plus++;
        } else if (l.startsWith('-')) {
          minus++;
        }
      }
      return _DiffView(
          lines: all, path: path, plus: plus, minus: minus, size: size);
    }

    // Path 2: oldString/newString (less-structured MCP edit payloads).
    final oldStr = c['oldString'];
    final newStr = c['newString'];
    if (oldStr is String || newStr is String) {
      if (oldStr is! String && newStr is String) {
        // Write-style: preview of new content, no diff prefixes.
        return _DiffView(
            lines: newStr.split('\n'), path: path, size: size, newFile: true);
      }
      final oldLines = (oldStr is String ? oldStr : '').split('\n');
      final newLines = (newStr is String ? newStr : '').split('\n');
      return _DiffView(
        lines: [
          ...oldLines.map((l) => '-$l'),
          ...newLines.map((l) => '+$l'),
        ],
        path: path,
        plus: newLines.length,
        minus: oldLines.length,
        size: size,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = lines.length > _maxLines ? lines.sublist(0, _maxLines) : lines;
    final extra = lines.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: path chip + +/- counts (or "New file").
        Wrap(
          spacing: AppTokens.s6,
          runSpacing: AppTokens.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (path != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(path!,
                    style: const TextStyle(
                        fontSize: 11, fontFamily: AppTokens.fontMono)),
              ),
            if (newFile)
              Text(context.tr('New file'),
                  style: TextStyle(fontSize: 11, color: c.textMuted)),
            if (plus != null)
              Text('+$plus',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTokens.success,
                      fontWeight: FontWeight.w600)),
            if (minus != null)
              Text('−$minus',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTokens.danger,
                      fontWeight: FontWeight.w600)),
            if (size != null)
              Text(context.trArgs('{size} bytes', {'size': size}),
                  style: TextStyle(fontSize: 11, color: c.textMuted)),
          ],
        ),
        const SizedBox(height: AppTokens.s6),
        // Diff body: one colored row per line.
        for (final l in shown) _diffLine(context, l),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.trArgs('… {n} more lines', {'n': extra}),
                style: TextStyle(fontSize: 11, color: c.textMuted)),
          ),
      ],
    );
  }

  Widget _diffLine(BuildContext context, String l) {
    final c = context.colors;
    Color? bg;
    Color fg = c.textSecondary;
    if (newFile) {
      // Plain new-file preview — no +/- coloring.
    } else if (l.startsWith('+++') || l.startsWith('---')) {
      fg = c.textMuted;
    } else if (l.startsWith('@@')) {
      fg = AppTokens.brand;
      bg = AppTokens.brand.withValues(alpha: 0.10);
    } else if (l.startsWith('+')) {
      fg = AppTokens.success;
      bg = AppTokens.success.withValues(alpha: 0.13);
    } else if (l.startsWith('-')) {
      fg = AppTokens.danger;
      bg = AppTokens.danger.withValues(alpha: 0.13);
    }
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SelectableText(
        l.isEmpty ? ' ' : l,
        style: TextStyle(
            fontSize: 11, height: 1.5, fontFamily: AppTokens.fontMono, color: fg),
      ),
    );
  }
}

/// Renders image attachments ({dataUrl, mimeType}) under a message bubble.
class _Attachments extends StatelessWidget {
  const _Attachments({required this.attachments});
  final List<Map<String, dynamic>> attachments;

  Uint8List? _decode(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Fullscreen zoomable preview (web ChatView image-preview modal).
  void _showFullImage(BuildContext context, ImageProvider provider) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(child: Image(image: provider, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s6),
      child: Wrap(
        spacing: AppTokens.s8,
        runSpacing: AppTokens.s8,
        children: [
          for (final a in attachments)
            Builder(builder: (ctx) {
              final url = '${a['dataUrl'] ?? ''}';
              // Documents have no thumbnail — a name chip is all that's
              // meaningful, and rendering one through the image decoder below
              // would only ever produce a broken-image icon.
              if (!'${a['mimeType'] ?? ''}'.startsWith('image/')) {
                return Chip(
                  avatar: const Icon(Icons.description_outlined, size: 14),
                  label: Text('${a['name'] ?? a['mimeType'] ?? 'file'}',
                      style: const TextStyle(fontSize: 12)),
                );
              }
              final box = const BoxConstraints(
                  maxWidth: 260, maxHeight: 260, minWidth: 40, minHeight: 40);
              ImageProvider? provider;
              if (url.startsWith('data:') || !url.startsWith('http')) {
                final bytes = _decode(url);
                if (bytes != null) provider = MemoryImage(bytes);
              } else {
                provider = NetworkImage(url);
              }
              if (provider == null) {
                return Icon(Icons.broken_image_outlined, color: c.textMuted);
              }
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showFullImage(ctx, provider!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.rMd),
                    child: ConstrainedBox(
                      constraints: box,
                      child: Image(image: provider, fit: BoxFit.cover),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// A DAG dispatch parent rendered inline in the chat stream (web
/// InlineDispatchCard): goal + status + each sub-task's status/agent.
class InlineDispatchCard extends ConsumerWidget {
  const InlineDispatchCard({super.key, required this.parent});
  final DispatchParent parent;

  Color _statusColor(String s) => switch (s) {
        'done' || 'completed' => AppTokens.success,
        'error' || 'timeout' || 'failed' => AppTokens.danger,
        'active' || 'processing' || 'running' => AppTokens.warning,
        _ => AppTokens.brandAlt,
      };

  static bool _failed(String s) => s == 'error' || s == 'timeout';

  /// Re-queue work and report the outcome.
  ///
  /// No local pending flag on purpose: the card is stateless and refreshes from
  /// the `dispatch:update` push. A double tap is harmless because the daemon
  /// refuses a task that is already queued or running — and says why, which is
  /// what lands in the snackbar.
  Future<void> _retry(
      BuildContext context, WidgetRef ref, String path, String okMsg) async {
    String message = okMsg;
    try {
      await ref.read(apiClientProvider).post(path);
    } on ApiException catch (e) {
      message = e.message;
    } catch (e) {
      message = e.toString();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Live per-sub-task activity (web SubAgentActivityCard) — count + latest.
    final activity = ref.watch(dispatchProvider).activity;
    final done = parent.tasks
        .where((t) => t.status == 'done' || t.status == 'completed')
        .length;
    final total = parent.tasks.length;
    final failed = parent.tasks.where((t) => _failed(t.status)).length;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: AppTokens.s16, vertical: AppTokens.s6),
          padding: const EdgeInsets.all(AppTokens.s12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppTokens.rMd),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_tree_outlined,
                      size: 16, color: c.accent),
                  const SizedBox(width: AppTokens.s8),
                  Expanded(
                    child: Text(
                      parent.goal.isEmpty ? context.tr('Dispatch') : parent.goal,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.textPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.s8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor(parent.status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTokens.rSm),
                    ),
                    child: Text(
                      total > 0 ? '${parent.status} · $done/$total' : parent.status,
                      style: TextStyle(
                          color: _statusColor(parent.status),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (failed > 0)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      color: AppTokens.danger,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.only(left: AppTokens.s8),
                      tooltip: context.tr('Retry failed tasks'),
                      onPressed: () => _retry(
                        context,
                        ref,
                        '/api/dispatch/parents/${parent.id}/retry',
                        context.tr('Failed tasks re-queued'),
                      ),
                    ),
                ],
              ),
              if (parent.tasks.isNotEmpty) const SizedBox(height: AppTokens.s8),
              for (final t in parent.tasks)
                Builder(builder: (_) {
                  final acts =
                      activity.where((a) => a.taskId == t.id).toList();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: _statusColor(t.status),
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: AppTokens.s8),
                            Expanded(
                              child: Text(t.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: c.textPrimary, fontSize: 13)),
                            ),
                            if (acts.isNotEmpty) ...[
                              Icon(Icons.bolt, size: 12, color: c.textMuted),
                              Text('${acts.length}',
                                  style: TextStyle(
                                      color: c.textMuted, fontSize: 11)),
                              const SizedBox(width: AppTokens.s6),
                            ],
                            if (t.agentId.isNotEmpty)
                              Text(t.agentId,
                                  style: TextStyle(
                                      color: c.textMuted, fontSize: 11)),
                            if (_failed(t.status))
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 14),
                                color: AppTokens.danger,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(),
                                padding:
                                    const EdgeInsets.only(left: AppTokens.s6),
                                tooltip: context.tr('Re-run this task'),
                                onPressed: () => _retry(
                                  context,
                                  ref,
                                  '/api/dispatch/tasks/${t.id}/retry',
                                  context.tr('Task re-queued'),
                                ),
                              ),
                          ],
                        ),
                        // Latest activity line for in-flight tasks.
                        if (acts.isNotEmpty &&
                            t.status != 'done' &&
                            t.status != 'completed')
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 16, top: 1),
                            child: Text(_oneLine(acts.last.text),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.textMuted,
                                    fontSize: 11,
                                    fontFamily: AppTokens.fontMono)),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
