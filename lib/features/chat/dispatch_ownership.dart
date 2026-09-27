import '../../models/chat_message.dart';
import '../dock/dispatch_provider.dart';

/// Does this DAG belong in this chat?
///
/// `adminFolder` is the **agent profile**, not the conversation. Every session
/// created under one profile shares it, so filtering cards by folder alone put
/// every DAG the profile had ever run into a brand-new chat — which is how a
/// fresh session came up showing another session's task graphs.
///
/// The daemon now stamps `chatJid` on each parent, and that is the answer
/// whenever it is present.
///
/// For parents written before that field existed there is still a per-chat
/// signal: the tool call that created the DAG lives in this chat's own
/// history, and its output names the parent ("Parent task created: p-7").
/// Matching that is how history keeps its cards without attributing them to
/// the wrong conversation. A legacy parent no chat claims is shown nowhere
/// rather than everywhere: a card in the wrong conversation is worse than a
/// missing one, and the dispatch view still lists it.
bool ownsDispatchParent(
  DispatchParent parent,
  String chatJid,
  List<ChatMessage> messages,
) {
  if (parent.chatJid.isNotEmpty) return parent.chatJid == chatJid;
  return _chatMentionsParent(messages, parent.id);
}

/// True when some tool result in this chat names [parentId].
bool _chatMentionsParent(List<ChatMessage> messages, String parentId) {
  if (parentId.isEmpty) return false;
  // Word-boundary match: `p-1` must not be found inside `p-12`.
  final needle = RegExp('(^|[^\\w-])${RegExp.escape(parentId)}([^\\w-]|\$)');
  for (final m in messages) {
    if (m.kind != MessageKind.tool) continue;
    final haystack = m.toolContent;
    if (haystack.isNotEmpty && needle.hasMatch(haystack)) return true;
  }
  return false;
}
