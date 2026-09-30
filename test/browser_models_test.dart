// JSON parsing for `/api/browser-agent/settings` and `/api/browser-agent/extension`,
// and the partial-update diff Save actually sends.

import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/features/settings/browser_models.dart';

Map<String, dynamic> _settingsJson({
  String engine = 'v2',
  bool runtimeInstalled = true,
}) =>
    {
      'settings': {
        'engine': 'auto',
        'defaultDriver': 'extension',
        'decisionBackend': 'hosted',
        'localModel': 'laya-browser',
        'hostedModel': 'jev-1.13.0',
        'hostedDomains': ['example.com', 'docs.example.com'],
        'sensitiveDomains': ['bank.example.com'],
        'domainDrivers': {'mail.google.com': 'extension'},
        'textModel': 'gpt-4o',
        'fallbackModel': null,
        'bandsLocal': {'act': 0.6, 'fallback': 0.2},
        'bandsHosted': {'act': 0.5, 'fallback': 0.25},
        'maxSteps': 40,
        'headless': true,
        'profile': 'default',
        'startUrl': 'https://duckduckgo.com/',
      },
      'engine': engine,
      'runtimeInstalled': runtimeInstalled,
    };

Map<String, dynamic> _extensionJson() => {
      'connected': {'ext_id': 'abcdefgh12345678abcdefgh12345678', 'version': '0.3.0', 'chrome': '128.0', 'piped': true},
      'pending': [
        {'code': 'ABCD1234', 'ext_id': 'ijklmnopijklmnopijklmnopijklmnop', 'age_secs': 12},
      ],
      'paired': [
        {'ext_id': 'abcdefgh12345678abcdefgh12345678', 'paired_at': '2026-09-29T00:00:00Z'},
      ],
    };

void main() {
  group('decision model state', () {
    test('is read when the daemon sends it, and missing means needed but not installed', () {
      final json = _settingsJson()..['decisionModel'] = {'id': 'laya-browser', 'needed': true, 'installed': false};
      final state = BrowserSettingsView.fromJson(json).decisionModel!;
      expect((state.id, state.needed, state.installed, state.missing), ('laya-browser', true, false, true));

      json['decisionModel'] = {'id': 'laya-browser', 'needed': true, 'installed': true};
      expect(BrowserSettingsView.fromJson(json).decisionModel!.missing, isFalse);
      // The LLM picks every step by choice: nothing is missing.
      json['decisionModel'] = {'id': 'laya-browser', 'needed': false, 'installed': false};
      expect(BrowserSettingsView.fromJson(json).decisionModel!.missing, isFalse);
    });

    test('is absent from an older daemon', () {
      expect(BrowserSettingsView.fromJson(_settingsJson()).decisionModel, isNull);
    });
  });

  group('BrowserSettings / BrowserSettingsView JSON', () {
    test('parses every camelCase field, including nested bands and domain map', () {
      final view = BrowserSettingsView.fromJson(_settingsJson());
      final s = view.settings;

      expect(s.engine, 'auto');
      expect(s.defaultDriver, 'extension');
      expect(s.decisionBackend, 'hosted');
      expect(s.localModel, 'laya-browser');
      expect(s.hostedModel, 'jev-1.13.0');
      expect(s.hostedDomains, ['example.com', 'docs.example.com']);
      expect(s.sensitiveDomains, ['bank.example.com']);
      expect(s.domainDrivers, {'mail.google.com': 'extension'});
      expect(s.textModel, 'gpt-4o');
      expect(s.fallbackModel, isNull);
      expect(s.bandsLocal, const BrowserBands(act: 0.6, fallback: 0.2));
      expect(s.bandsHosted, const BrowserBands(act: 0.5, fallback: 0.25));
      expect(s.maxSteps, 40);
      expect(s.headless, isTrue);
      expect(s.profile, 'default');
      expect(s.startUrl, 'https://duckduckgo.com/');

      expect(view.engine, 'v2');
      expect(view.runtimeInstalled, isTrue);
    });

    test('engine resolves to legacy for anything that is not v2, never left as auto', () {
      expect(BrowserSettingsView.fromJson(_settingsJson(engine: 'legacy')).engine, 'legacy');
      expect(BrowserSettingsView.fromJson(_settingsJson(engine: 'bogus')).engine, 'legacy');
    });

    test('missing settings fall back to the documented defaults', () {
      final s = BrowserSettings.fromJson(const {});
      expect(s.engine, 'auto');
      expect(s.defaultDriver, 'managed');
      expect(s.decisionBackend, 'auto');
      expect(s.localModel, 'laya-browser');
      expect(s.hostedModel, isNull);
      expect(s.hostedDomains, isEmpty);
      expect(s.domainDrivers, isEmpty);
      expect(s.bandsLocal, const BrowserBands(act: 0.6, fallback: 0.2));
      expect(s.bandsHosted, const BrowserBands(act: 0.5, fallback: 0.25));
      expect(s.maxSteps, 40);
      expect(s.headless, isTrue);
      expect(s.profile, 'default');
      expect(s.startUrl, 'https://duckduckgo.com/');
    });

    test('toJson round-trips into an equivalent settings object', () {
      final s = BrowserSettingsView.fromJson(_settingsJson()).settings;
      final again = BrowserSettings.fromJson(s.toJson());
      expect(browserSettingsDiff(s, again), isEmpty);
    });
  });

  group('BrowserExtensionState JSON (snake_case on the wire)', () {
    test('parses connected, a pending code and a paired browser', () {
      final state = BrowserExtensionState.fromJson(_extensionJson());

      expect(state.connected, isNotNull);
      expect(state.connected!.extId, 'abcdefgh12345678abcdefgh12345678');
      expect(state.connected!.version, '0.3.0');
      expect(state.connected!.chrome, '128.0');
      expect(state.connected!.piped, isTrue);

      expect(state.pending, hasLength(1));
      expect(state.pending.single.code, 'ABCD1234');
      expect(state.pending.single.extId, 'ijklmnopijklmnopijklmnopijklmnop');
      expect(state.pending.single.ageSecs, 12);

      expect(state.paired, hasLength(1));
      expect(state.paired.single.extId, 'abcdefgh12345678abcdefgh12345678');
      expect(state.paired.single.pairedAt, '2026-09-29T00:00:00Z');
    });

    test('not connected, nothing pending or paired parses to empty/null, not an error', () {
      final state = BrowserExtensionState.fromJson(const {'connected': null, 'pending': [], 'paired': []});
      expect(state.connected, isNull);
      expect(state.pending, isEmpty);
      expect(state.paired, isEmpty);
    });
  });

  group('BrowserTabsState JSON', () {
    test('parses sessions with their tabs, and the embedded extension state', () {
      final tabs = BrowserTabsState.fromJson({
        'sessions': [
          {
            'id': 's1',
            'driver': 'managed',
            'profile': 'default',
            'headless': true,
            'tabs': [
              {'id': 't1', 'owner': 'chat:123', 'driver': 'managed', 'url': 'https://example.com/', 'hold': 'none', 'closed': false},
            ],
          },
        ],
        'current': {'managed': 't1', 'extension': null},
        'extension': _extensionJson(),
      });
      expect(tabs.sessions, hasLength(1));
      expect(tabs.sessions.single.tabs, hasLength(1));
      expect(tabs.sessions.single.tabs.single.owner, 'chat:123');
      expect(tabs.sessions.single.tabs.single.hold, 'none');
      expect(tabs.extension.connected, isNotNull);
    });
  });

  group('browserSettingsDiff — the partial PUT body', () {
    test('nothing changed sends nothing', () {
      final s = BrowserSettingsView.fromJson(_settingsJson()).settings;
      expect(browserSettingsDiff(s, s), isEmpty);
    });

    test('only the touched scalar field is sent', () {
      final before = const BrowserSettings();
      final after = before.copyWith(maxSteps: 80);
      final diff = browserSettingsDiff(before, after);
      expect(diff, {'maxSteps': 80});
    });

    test('a list/map/band field is sent whole, never as a sub-diff, since the daemon merge is shallow', () {
      final before = const BrowserSettings();
      final afterList = before.copyWith(hostedDomains: ['a.com', 'b.com']);
      expect(browserSettingsDiff(before, afterList), {
        'hostedDomains': ['a.com', 'b.com']
      });

      final afterMap = before.copyWith(domainDrivers: {'a.com': 'extension'});
      expect(browserSettingsDiff(before, afterMap), {
        'domainDrivers': {'a.com': 'extension'}
      });

      final afterBand = before.copyWith(bandsLocal: const BrowserBands(act: 0.7, fallback: 0.3));
      expect(browserSettingsDiff(before, afterBand), {
        'bandsLocal': {'act': 0.7, 'fallback': 0.3}
      });
    });

    test('a nullable field going to null is still sent, not omitted', () {
      final before = const BrowserSettings(hostedModel: 'jev-1.13.0');
      final after = before.copyWith(hostedModel: () => null);
      expect(browserSettingsDiff(before, after), {'hostedModel': null});
    });

    test('a map with the same entries in a different insertion order is not treated as a change', () {
      // Unlike hostedDomains/sensitiveDomains (an ordered chip list the UI
      // only ever appends to or filters — so a real edit always changes
      // content, never just order), domainDrivers is a host → driver map
      // with no meaningful order at all.
      final before = const BrowserSettings(domainDrivers: {'a.com': 'managed', 'b.com': 'extension'});
      final after = const BrowserSettings(domainDrivers: {'b.com': 'extension', 'a.com': 'managed'});
      expect(browserSettingsDiff(before, after), isEmpty);
    });

    test('several edits at once each land as their own key, and untouched fields are absent', () {
      final before = BrowserSettingsView.fromJson(_settingsJson()).settings;
      final after = before.copyWith(
        profile: 'work',
        headless: false,
        decisionBackend: 'local',
      );
      final diff = browserSettingsDiff(before, after);
      expect(diff, {'profile': 'work', 'headless': false, 'decisionBackend': 'local'});
      expect(diff.containsKey('startUrl'), isFalse);
      expect(diff.containsKey('bandsLocal'), isFalse);
    });
  });

  group('PendingBrowserApproval JSON (snake_case on the wire)', () {
    test('parses every field of a paused CLICK action', () {
      final a = PendingBrowserApproval.fromJson(const {
        'approval_id': 'appr-1',
        'task_id': 'task-1',
        'chat': 'chat:123',
        'goal': 'Buy the blue mug in my cart',
        'action': 'Place order',
        'operation': 'CLICK',
        'text': null,
        'driver': 'managed',
        'url': 'https://example.com/checkout.html',
        'waiting_secs': 65,
      });
      expect(a.approvalId, 'appr-1');
      expect(a.taskId, 'task-1');
      expect(a.chat, 'chat:123');
      expect(a.goal, 'Buy the blue mug in my cart');
      expect(a.action, 'Place order');
      expect(a.operation, 'CLICK');
      expect(a.text, isNull);
      expect(a.driver, 'managed');
      expect(a.url, 'https://example.com/checkout.html');
      expect(a.waitingSecs, 65);
    });

    test('text, url and waiting_secs missing entirely parse to null, not a crash or a default', () {
      final a = PendingBrowserApproval.fromJson(const {
        'approval_id': 'appr-2',
        'task_id': 'task-2',
        'chat': 'chat:456',
        'goal': 'Fill the newsletter form',
        'action': 'Submit',
        'operation': 'KEY_ENTER',
        'driver': 'extension',
      });
      expect(a.text, isNull);
      expect(a.url, isNull);
      expect(a.waitingSecs, isNull);
    });

    test('a present text field (TYPE_TEXT) parses through', () {
      final a = PendingBrowserApproval.fromJson(const {
        'approval_id': 'appr-3',
        'task_id': 'task-3',
        'chat': 'chat:789',
        'goal': 'Sign up',
        'action': 'Type email',
        'operation': 'TYPE_TEXT',
        'text': 'me@example.com',
        'driver': 'managed',
        'url': 'https://example.com/signup',
        'waiting_secs': 3,
      });
      expect(a.text, 'me@example.com');
    });
  });

  group('formatBrowserWaitingTime', () {
    test('seconds under a minute show as seconds', () {
      expect(formatBrowserWaitingTime(0), '0s');
      expect(formatBrowserWaitingTime(45), '45s');
      expect(formatBrowserWaitingTime(59), '59s');
    });

    test('a minute or more, under an hour, shows whole minutes only', () {
      expect(formatBrowserWaitingTime(60), '1m');
      expect(formatBrowserWaitingTime(179), '2m'); // still short of 3m, not rounded up
      expect(formatBrowserWaitingTime(180), '3m');
      expect(formatBrowserWaitingTime(3599), '59m');
    });

    test('an hour or more shows hours, plus minutes only when there is a remainder', () {
      expect(formatBrowserWaitingTime(3600), '1h');
      expect(formatBrowserWaitingTime(3900), '1h 5m');
      expect(formatBrowserWaitingTime(7260), '2h 1m');
    });

    test('a negative value (defensive only — the daemon never sends one) clamps to 0s', () {
      expect(formatBrowserWaitingTime(-5), '0s');
    });
  });

  group('BrowserApprovalOutcome JSON', () {
    test('parses task_id, status and message', () {
      final o = BrowserApprovalOutcome.fromJson(const {
        'task_id': 'task-1',
        'status': 'needs_approval',
        'message': 'paused again on the next dialog',
      });
      expect(o.taskId, 'task-1');
      expect(o.status, 'needs_approval');
      expect(o.message, 'paused again on the next dialog');
    });

    test('missing fields fall back to empty strings, not a crash', () {
      final o = BrowserApprovalOutcome.fromJson(const {});
      expect(o.taskId, '');
      expect(o.status, '');
      expect(o.message, '');
    });
  });
}
