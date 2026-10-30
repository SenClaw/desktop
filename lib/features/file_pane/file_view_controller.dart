import 'package:flutter/foundation.dart';

import 'markdown_outline.dart';

/// What the pane's toolbar asks of whichever view is showing the file. The
/// rendered and source views count matches differently (one looks at the text
/// on screen, the other at the file), so each reports its own count back.
class FileViewController extends ChangeNotifier {
  String _query = '';
  int _index = 0;
  int _count = 0;

  String get query => _query;

  /// The match being looked at, zero-based.
  int get index => _index;
  int get count => _count;

  /// Set by the view on screen; the contents list calls it.
  ValueChanged<MdHeading>? onJump;

  void search(String query) {
    if (query == _query) return;
    _query = query;
    _index = 0;
    notifyListeners();
  }

  void step(int by) {
    if (_count == 0) return;
    _index = (_index + by) % _count;
    notifyListeners();
  }

  void report(int count) {
    final index = _index < count ? _index : 0;
    if (count == _count && index == _index) return;
    _count = count;
    _index = index;
    notifyListeners();
  }
}

/// [query] as a pattern over text: literal, whatever case.
RegExp matcherFor(String query) =>
    RegExp(RegExp.escape(query), caseSensitive: false);
