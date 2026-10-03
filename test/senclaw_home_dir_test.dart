import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/token_file_io.dart';

void main() {
  group('senclawHomeDir', () {
    test('defaults to ~/.senclaw', () {
      expect(senclawHomeDir({'HOME': '/Users/u'}, '/work'), '/Users/u/.senclaw');
    });

    test('follows SENCLAW_HOME like the daemon does', () {
      expect(senclawHomeDir({'HOME': '/Users/u', 'SENCLAW_HOME': '/apps/news/state'}, '/work'),
          '/apps/news/state');
      expect(senclawHomeDir({'HOME': '/Users/u', 'SENCLAW_HOME': '~/dev/.senclaw'}, '/work'),
          '/Users/u/dev/.senclaw');
      expect(senclawHomeDir({'HOME': '/Users/u', 'SENCLAW_HOME': '.senclaw-dev'}, '/work'),
          '/work/.senclaw-dev');
    });

    test('a blank SENCLAW_HOME is unset', () {
      expect(senclawHomeDir({'HOME': '/Users/u', 'SENCLAW_HOME': '  '}, '/work'), '/Users/u/.senclaw');
    });

    test('no home and no SENCLAW_HOME is no folder', () {
      expect(senclawHomeDir({}, '/work'), isNull);
    });
  });
}
