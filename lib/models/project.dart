/// A project: one folder root that chat sessions and kanban boards work in,
/// with a context and facts of its own (mirrors `/api/projects`).
class Project {
  final String id;
  final String name;
  final String root;
  final String description;

  /// Where facts picked out of the project's chats are kept: `project` (the
  /// project's own bank, shared by its chats), `chat` (as outside a project) or
  /// `off`.
  final String factsWrite;

  /// Whether the agent's common facts are also recalled inside the project.
  final bool inheritCommon;
  final int createdAt;
  final int updatedAt;
  final int? archivedAt;

  /// Sessions created in the project.
  final int chatCount;

  /// The folder can be renamed or deleted after the project was saved; the
  /// daemon looks on every read instead of waiting for a session to fail.
  final bool rootExists;
  final bool hasClaudeMd;
  final bool isGit;

  const Project({
    required this.id,
    required this.name,
    required this.root,
    this.description = '',
    this.factsWrite = 'project',
    this.inheritCommon = true,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.archivedAt,
    this.chatCount = 0,
    this.rootExists = true,
    this.hasClaudeMd = false,
    this.isGit = false,
  });

  bool get archived => archivedAt != null;

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        root: '${j['root'] ?? ''}',
        description: '${j['description'] ?? ''}',
        factsWrite: '${j['factsWrite'] ?? 'project'}',
        inheritCommon: j['inheritCommon'] != false,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        archivedAt: (j['archivedAt'] as num?)?.toInt(),
        chatCount: (j['chatCount'] as num?)?.toInt() ?? 0,
        rootExists: j['rootExists'] != false,
        hasClaudeMd: j['hasClaudeMd'] == true,
        isGit: j['isGit'] == true,
      );
}

/// `GET|PUT /api/projects/:id/context`. [updatedAt] is the version a write is
/// checked against: the daemon refuses a PUT whose copy is older.
class ProjectContext {
  final String content;
  final int updatedAt;
  final int chars;
  final int maxChars;
  const ProjectContext({
    required this.content,
    required this.updatedAt,
    required this.chars,
    required this.maxChars,
  });

  /// What the daemon puts in the system prompt before it cuts the text.
  static const defaultMaxChars = 8000;

  /// From here the counter warns that the context is getting long.
  static const warnChars = 5000;

  factory ProjectContext.fromJson(Map<String, dynamic> j) => ProjectContext(
        content: '${j['content'] ?? ''}',
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        chars: (j['chars'] as num?)?.toInt() ?? '${j['content'] ?? ''}'.trim().length,
        maxChars: (j['maxChars'] as num?)?.toInt() ?? defaultMaxChars,
      );
}

/// One reason the daemon refused a root. [code] is stable (the client
/// translates it); [message] is the daemon's English sentence, with the path.
class RootReason {
  final String code;
  final String message;
  const RootReason(this.code, this.message);

  factory RootReason.fromJson(Map<String, dynamic> j) =>
      RootReason('${j['code'] ?? ''}', '${j['message'] ?? ''}');
}

/// `POST /api/projects/validate-root`: the checks a create runs, without
/// creating anything.
class RootCheck {
  final bool ok;
  final String? canonical;
  final List<RootReason> reasons;
  final bool hasClaudeMd;
  final bool isGit;

  /// The project that already has this root, if that is why it was refused.
  final String? inUseByName;

  const RootCheck({
    required this.ok,
    this.canonical,
    this.reasons = const [],
    this.hasClaudeMd = false,
    this.isGit = false,
    this.inUseByName,
  });

  factory RootCheck.fromJson(Map<String, dynamic> j) {
    final owner = j['inUseBy'];
    return RootCheck(
      ok: j['ok'] == true,
      canonical: j['canonical'] as String?,
      reasons: [
        for (final r in (j['reasons'] as List? ?? const []))
          if (r is Map) RootReason.fromJson(r.cast<String, dynamic>()),
      ],
      hasClaudeMd: j['hasClaudeMd'] == true,
      isGit: j['isGit'] == true,
      inUseByName: owner is Map ? owner['name'] as String? : null,
    );
  }
}

/// A session created in a project (`GET /api/projects/:id/chats`).
class ProjectChat {
  final String jid;
  final String name;
  final String folder;
  final String groupType;
  final String? lastActive;
  const ProjectChat({
    required this.jid,
    required this.name,
    this.folder = '',
    this.groupType = 'chat',
    this.lastActive,
  });

  factory ProjectChat.fromJson(Map<String, dynamic> j) => ProjectChat(
        jid: '${j['jid'] ?? ''}',
        name: '${j['name'] ?? ''}',
        folder: '${j['folder'] ?? ''}',
        groupType: '${j['groupType'] ?? 'chat'}',
        lastActive: j['lastActive'] as String?,
      );
}

/// A kanban board of a project (`GET /api/projects/:id/boards`), with the
/// folder its workers run in.
class ProjectBoard {
  final int id;
  final String title;
  final int cardCount;

  /// The folder of its own, when the board names one inside the root.
  final String? workspaceDir;

  /// Where the board's workers really run: its own folder, else the root.
  final String? effectiveWorkspaceDir;
  const ProjectBoard({
    required this.id,
    required this.title,
    this.cardCount = 0,
    this.workspaceDir,
    this.effectiveWorkspaceDir,
  });

  factory ProjectBoard.fromJson(Map<String, dynamic> j) => ProjectBoard(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: '${j['title'] ?? ''}',
        cardCount: (j['card_count'] as num?)?.toInt() ?? 0,
        workspaceDir: j['workspace_dir'] as String?,
        effectiveWorkspaceDir: j['effective_workspace_dir'] as String?,
      );
}

/// What a purge reports once the daemon is done.
class ProjectPurge {
  final int deletedFacts;
  final int detachedChats;
  const ProjectPurge(this.deletedFacts, this.detachedChats);

  factory ProjectPurge.fromJson(Map<String, dynamic> j) => ProjectPurge(
        (j['deletedFacts'] as num?)?.toInt() ?? 0,
        (j['detachedChats'] as List?)?.length ?? 0,
      );
}

/// Bank name of a project's own facts in `GET /api/memory/facts/banks`.
const kProjectBankPrefix = 'project:';

/// The project id inside a fact bank name, or null for an agent's bank.
String? projectIdOfBank(String bank) =>
    bank.startsWith(kProjectBankPrefix)
        ? bank.substring(kProjectBankPrefix.length)
        : null;
