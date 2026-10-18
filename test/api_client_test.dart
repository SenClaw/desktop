// ApiClient: what a refused request carries back, and the one way a call may
// be given longer than the usual ceiling.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(AppConfig.fromEnvironment(), client: MockClient(handler));

void main() {
  group('a refusal', () {
    test('keeps the whole body, not only the error line', () async {
      final api = _client((_) async => http.Response(
          jsonEncode({
            'error': 'context_changed',
            'content': 'text now',
            'updatedAt': 9,
          }),
          409));
      try {
        await api.put('/api/projects/prj_x/context', body: {'content': 'a'});
        fail('expected a refusal');
      } on ApiException catch (e) {
        expect(e.status, 409);
        expect(e.message, 'context_changed');
        expect(e.body, {'error': 'context_changed', 'content': 'text now', 'updatedAt': 9});
      }
    });

    test('a body that is not JSON leaves body empty and the text as message',
        () async {
      final api = _client((_) async => http.Response('plain failure', 500));
      try {
        await api.get('/api/x');
        fail('expected a refusal');
      } on ApiException catch (e) {
        expect(e.message, 'plain failure');
        expect(e.body, isNull);
      }
    });

    test('the code and slot of a runtime-missing answer still arrive', () async {
      final api = _client((_) async => http.Response(
          jsonEncode({'error': 'no runtime', 'code': 'runtime_not_installed', 'slot': 'ocr'}),
          503));
      try {
        await api.get('/api/ocr/x');
        fail('expected a refusal');
      } on ApiException catch (e) {
        expect((e.code, e.slot), ('runtime_not_installed', 'ocr'));
        expect(e.body!['slot'], 'ocr');
      }
    });
  });

  group('withTimeout', () {
    Future<http.Response> slow(http.Request _) async {
      await Future<void>.delayed(const Duration(seconds: 45));
      return http.Response('{"deleted":"prj_x"}', 200);
    }

    // The test binding's clock stands in for the 30 s and the 45 s.
    testWidgets('an ordinary call that takes 45 s is cut off at the usual 30 s',
        (tester) async {
      final api = _client(slow);
      Object? error;
      api.delete('/api/projects/prj_x?purge=true').catchError((Object e) {
        error = e;
        return null;
      });
      await tester.pump(const Duration(seconds: 31));
      expect(error, isA<ApiTimeout>());
      await tester.pump(const Duration(seconds: 20));
    });

    testWidgets('inside withTimeout the same call is allowed to finish',
        (tester) async {
      final api = _client(slow);
      dynamic result;
      Object? error;
      ApiClient.withTimeout(const Duration(minutes: 5),
              () => api.delete('/api/projects/prj_x?purge=true'))
          .then((r) => result = r, onError: (Object e) => error = e);
      await tester.pump(const Duration(seconds: 60));
      expect(error, isNull);
      expect(result, {'deleted': 'prj_x'});
    });

    testWidgets('and is still cut off when it outlasts that longer limit',
        (tester) async {
      final api = _client(slow);
      Object? error;
      ApiClient.withTimeout(const Duration(seconds: 40),
              () => api.delete('/api/projects/prj_x?purge=true'))
          .catchError((Object e) {
        error = e;
        return null;
      });
      await tester.pump(const Duration(seconds: 41));
      expect(error, isA<ApiTimeout>());
      expect((error as ApiTimeout).limit, const Duration(seconds: 40));
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('an explicit timeout on a call wins over the zone',
        (tester) async {
      final api = _client(slow);
      Object? error;
      ApiClient.withTimeout(const Duration(minutes: 5),
              () => api.get('/api/x', timeout: const Duration(seconds: 5)))
          .catchError((Object e) {
        error = e;
        return null;
      });
      await tester.pump(const Duration(seconds: 6));
      expect(error, isA<ApiTimeout>());
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('calls made outside the zone are unaffected', (tester) async {
      final api = _client(slow);
      await ApiClient.withTimeout(const Duration(minutes: 5), () async => 1);
      Object? error;
      api.get('/api/x').catchError((Object e) {
        error = e;
        return null;
      });
      await tester.pump(const Duration(seconds: 31));
      expect(error, isA<ApiTimeout>());
      await tester.pump(const Duration(seconds: 20));
    });
  });
}
