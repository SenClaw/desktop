import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/features/dock/right_dock.dart';

/// Stands in for the real terminal: unmounting it is what closes the socket and
/// kills the shell, so the disposals counted here are killed shells.
class _FakeTerminal extends StatefulWidget {
  const _FakeTerminal(this.counts);
  final _Counts counts;
  @override
  State<_FakeTerminal> createState() => _FakeTerminalState();
}

class _Counts {
  int mounted = 0;
  int disposed = 0;
}

class _FakeTerminalState extends State<_FakeTerminal> {
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    widget.counts.mounted++;
  }

  @override
  void dispose() {
    widget.counts.disposed++;
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: focus, autofocus: true, child: const Text('shell'));
}

Widget _dock(_Counts counts, {required bool terminal, String chat = 'a'}) =>
    MaterialApp(
      home: Scaffold(
        body: DockTabBody(
          key: ValueKey(chat),
          terminalActive: terminal,
          terminal: () => _FakeTerminal(counts),
          child: const Text('other tab'),
        ),
      ),
    );

void main() {
  testWidgets('the terminal does not start until its tab is opened', (t) async {
    final counts = _Counts();
    await t.pumpWidget(_dock(counts, terminal: false));
    expect(counts.mounted, 0);
    expect(find.text('other tab'), findsOneWidget);
  });

  testWidgets('leaving the tab keeps the shell alive, and it comes back',
      (t) async {
    final counts = _Counts();
    await t.pumpWidget(_dock(counts, terminal: true));
    expect(find.text('shell'), findsOneWidget);

    await t.pumpWidget(_dock(counts, terminal: false));
    await t.pump();
    expect(counts.disposed, 0);
    expect(find.text('shell'), findsNothing);
    expect(find.text('other tab'), findsOneWidget);

    await t.pumpWidget(_dock(counts, terminal: true));
    await t.pump();
    expect(counts.mounted, 1);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('other tab'), findsNothing);
  });

  testWidgets('a hidden terminal cannot take keystrokes', (t) async {
    final counts = _Counts();
    await t.pumpWidget(_dock(counts, terminal: true));
    await t.pump();
    final state = t.state<_FakeTerminalState>(find.byType(_FakeTerminal));
    expect(state.focus.hasFocus, isTrue);

    await t.pumpWidget(_dock(counts, terminal: false));
    await t.pump();
    expect(state.focus.hasFocus, isFalse);
  });

  testWidgets('moving to another chat ends that chat\'s shell', (t) async {
    final counts = _Counts();
    await t.pumpWidget(_dock(counts, terminal: true));
    await t.pumpWidget(_dock(counts, terminal: false, chat: 'b'));
    expect(counts.disposed, 1);
    expect(counts.mounted, 1);
  });
}
