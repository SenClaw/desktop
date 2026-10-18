// An in-memory stand-in for the daemon's `/api/projects*` (and the kanban
// routes the board dialogs call), shared by the project tests. It keeps the
// rules the screens depend on: a root is refused with reasons, a context write
// carries the version it was edited from and is refused with the current text
// when that is stale, a fact that looks like a secret is refused.

import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';

typedef Call = ({String method, String path, Object? body});

class FakeProjectsApi implements ApiClient {
  FakeProjectsApi({List<Map<String, dynamic>>? projects})
      : projects = projects ?? [project('prj_aaaa0001', 'Alpha', '/work/alpha')];

  final log = <Call>[];
  List<Map<String, dynamic>> projects;
  final boards = <Map<String, dynamic>>[];
  final chats = <Map<String, dynamic>>[];
  final facts = <Map<String, dynamic>>[];

  /// `GET /api/memory/facts/banks` and the facts of each bank (Knowledge → Facts).
  final banks = <Map<String, dynamic>>[];
  final bankFacts = <String, List<Map<String, dynamic>>>{};

  String contextText = '';
  int contextVersion = 0;
  int factSeq = 0;

  /// Raised by the next write that is checked against a version, to play a
  /// second window saving in between.
  void saveElsewhere(String text) {
    contextText = text;
    contextVersion += 5;
  }

  static Map<String, dynamic> project(String id, String name, String root,
          {String description = '',
          String factsWrite = 'project',
          bool inheritCommon = true,
          int? archivedAt,
          int chatCount = 0,
          bool rootExists = true,
          bool hasClaudeMd = false}) =>
      {
        'id': id,
        'name': name,
        'root': root,
        'description': description,
        'factsWrite': factsWrite,
        'inheritCommon': inheritCommon,
        'createdAt': 1790000000000,
        'updatedAt': 1790000000000,
        'archivedAt': archivedAt,
        'chatCount': chatCount,
        'rootExists': rootExists,
        'hasClaudeMd': hasClaudeMd,
        'isGit': true,
      };

  static Map<String, dynamic> fact(String id, String text,
          {String source = 'reflection', String? supersededBy}) =>
      {
        'id': id,
        'kind': 'world',
        'text': text,
        'occurredStart': null,
        'occurredEnd': null,
        'mentionedAt': 1790000000,
        'entities': <String>[],
        'proofCount': 1,
        'supersededBy': supersededBy,
        'origin': '',
        'source': source,
      };

  /// Calls to `method` whose path starts with [prefix].
  List<Call> calls(String method, [String prefix = '']) => [
        for (final c in log)
          if (c.method == method && c.path.startsWith(prefix)) c,
      ];

  Map<String, dynamic>? byId(String id) =>
      projects.where((p) => p['id'] == id).firstOrNull;

  Map<String, dynamic> _wire(Map<String, dynamic> p) => Map.of(p);

  ApiException _notFound() => ApiException(404, 'project_not_found',
      body: {'error': 'project_not_found'});

  /// What `validate-root` says about [path].
  Map<String, dynamic> validate(String path, {String? projectId}) {
    List<Map<String, String>> reasons = [];
    String? canonical;
    Map<String, dynamic>? owner;
    switch (path.trim()) {
      case '':
        reasons = [
          {'code': 'empty', 'message': 'The root folder is empty.'}
        ];
      case '/':
        reasons = [
          {'code': 'filesystem_root', 'message': 'The top of the filesystem…'}
        ];
      case '/Users/me':
        reasons = [
          {'code': 'home_dir', 'message': 'The home folder is too broad…'}
        ];
        canonical = '/Users/me';
      case '/nope':
        reasons = [
          {'code': 'not_found', 'message': '/nope does not exist.'}
        ];
      default:
        canonical = path.trim();
        owner = projects
            .where((p) => p['root'] == canonical && p['id'] != projectId)
            .firstOrNull;
        if (owner != null) {
          reasons = [
            {
              'code': 'root_in_use',
              'message': '$canonical is already the root of "${owner['name']}".'
            }
          ];
        }
    }
    return {
      'ok': reasons.isEmpty && canonical != null,
      'canonical': canonical,
      'reasons': reasons,
      'hasClaudeMd': false,
      'isGit': canonical != null,
      'inUseBy': owner == null ? null : {'id': owner['id'], 'name': owner['name']},
    };
  }

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Duration? timeout}) async {
    log.add((method: 'GET', path: path, body: query));
    if (path == '/api/projects') {
      return {'projects': [for (final p in projects) _wire(p)]};
    }
    if (path == '/api/memory/facts/banks') return {'banks': banks};
    if (path == '/api/memory/facts') {
      return {'facts': bankFacts['${query?['bank']}'] ?? []};
    }
    if (path == '/api/kanban/templates') {
      return [
        {'id': 'standard', 'name': 'Standard', 'description': '', 'builtin': true, 'columns': []}
      ];
    }
    if (path == '/api/kanban/boards') {
      return [for (final b in boards) b];
    }
    final m = RegExp(r'^/api/projects/([^/]+)(?:/(\w+))?$').firstMatch(path);
    if (m != null) {
      final p = byId(m.group(1)!);
      if (p == null) throw _notFound();
      switch (m.group(2)) {
        case null:
          return _wire(p);
        case 'context':
          return {
            'content': contextText,
            'updatedAt': contextVersion,
            'chars': contextText.trim().runes.length,
            'maxChars': 8000,
          };
        case 'chats':
          return {'chats': chats};
        case 'boards':
          return {
            'boards': [
              for (final b in boards)
                if (b['project_id'] == p['id']) b
            ]
          };
        case 'facts':
          final q = '${query?['q'] ?? ''}'.toLowerCase();
          final history = query?['history'] == 'true';
          final shown = [
            for (final f in facts)
              if ((history || f['supersededBy'] == null) &&
                  (q.isEmpty || '${f['text']}'.toLowerCase().contains(q)))
                f
          ];
          return {
            'bank': 'project:${p['id']}',
            'total': facts.where((f) => f['supersededBy'] == null).length,
            'count': shown.length,
            'facts': shown,
          };
      }
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    log.add((method: 'POST', path: path, body: body));
    final map = body is Map ? body.cast<String, dynamic>() : <String, dynamic>{};
    if (path == '/api/projects/validate-root') {
      return validate('${map['path']}', projectId: map['projectId'] as String?);
    }
    if (path == '/api/projects') {
      final check = validate('${map['root']}');
      if (check['ok'] != true) {
        final inUse = check['inUseBy'] as Map?;
        if (inUse != null) {
          throw ApiException(409, 'root_in_use',
              body: {'error': 'root_in_use', 'projectId': inUse['id'], 'projectName': inUse['name']});
        }
        throw ApiException(400, 'invalid_root',
            body: {'error': 'invalid_root', 'reasons': check['reasons']});
      }
      final p = project('prj_bbbb${projects.length + 1000}'.substring(0, 12),
          '${map['name']}', '${check['canonical']}',
          description: '${map['description'] ?? ''}',
          factsWrite: '${map['factsWrite'] ?? 'project'}',
          inheritCommon: map['inheritCommon'] != false);
      projects.add(p);
      return _wire(p);
    }
    final facts_ = RegExp(r'^/api/projects/([^/]+)/facts$').firstMatch(path);
    if (facts_ != null) {
      final text = '${map['text']}';
      if (text.contains('password')) {
        throw ApiException(400, 'secret_in_fact',
            body: {'error': 'secret_in_fact', 'kinds': ['password']});
      }
      final existing = facts.where((f) => f['text'] == text).firstOrNull;
      if (existing != null) {
        existing['source'] = 'manual';
        return {'fact': existing, 'existing': true};
      }
      final f = fact('fct_${++factSeq}', text, source: 'manual');
      facts.insert(0, f);
      return {'fact': f, 'existing': false};
    }
    if (path == '/api/kanban/boards') {
      final id = boards.length + 1;
      boards.add({
        'id': id,
        'title': map['title'],
        'description': '',
        'workspace_dir': map['workspace_dir'],
        'project_id': map['project_id'],
        'column_count': 5,
        'card_count': 0,
        'effective_workspace_dir': map['workspace_dir'] ??
            (map['project_id'] == null ? null : byId('${map['project_id']}')?['root']),
      });
      return {'id': id};
    }
    return {'ok': true};
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    log.add((method: 'PUT', path: path, body: body));
    final map = body is Map ? body.cast<String, dynamic>() : <String, dynamic>{};
    if (path.endsWith('/context')) {
      if ((map['updatedAt'] as num?)?.toInt() != contextVersion) {
        throw ApiException(409, 'context_changed', body: {
          'error': 'context_changed',
          'content': contextText,
          'updatedAt': contextVersion,
          'chars': contextText.trim().runes.length,
          'maxChars': 8000,
        });
      }
      contextText = '${map['content']}';
      contextVersion += 1;
      return {
        'content': contextText,
        'updatedAt': contextVersion,
        'chars': contextText.trim().runes.length,
        'maxChars': 8000,
      };
    }
    return {'ok': true};
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async {
    log.add((method: 'PATCH', path: path, body: body));
    final id = path.split('/').last;
    final p = byId(id);
    if (p == null) throw _notFound();
    final map = (body as Map).cast<String, dynamic>();
    for (final e in map.entries) {
      switch (e.key) {
        case 'archived':
          p['archivedAt'] = e.value == true ? 1790000001000 : null;
        default:
          p[e.key] = e.value;
      }
    }
    p['updatedAt'] = (p['updatedAt'] as int) + 1;
    return _wire(p);
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    log.add((method: 'DELETE', path: path, body: body));
    final fm = RegExp(r'^/api/projects/[^/]+/facts/([^/?]+)$').firstMatch(path);
    if (fm != null) {
      facts.removeWhere((f) => f['id'] == Uri.decodeComponent(fm.group(1)!));
      return {'deleted': fm.group(1)};
    }
    final m = RegExp(r'^/api/projects/([^/?]+)(\?purge=true)?$').firstMatch(path);
    if (m != null) {
      final p = byId(m.group(1)!);
      if (p == null) throw _notFound();
      if (m.group(2) == null) {
        p['archivedAt'] = 1790000001000;
        return _wire(p);
      }
      projects.remove(p);
      return {
        'deleted': p['id'],
        'deletedFacts': facts.length,
        'detachedChats': [for (final c in chats) c['jid']],
      };
    }
    return {'ok': true};
  }
}
