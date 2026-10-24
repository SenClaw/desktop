import 'package:flutter/material.dart';
import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';
import 'todos_provider.dart';

/// Where a todo stands, from the daemon's `status` (`completed` |
/// `in_progress` | anything else). Anything the daemon has not started — or a
/// status this client does not know — reads as waiting.
enum TodoPhase { done, running, waiting }

TodoPhase todoPhase(AgentTodo t) => switch (t.status) {
      'completed' => TodoPhase.done,
      'in_progress' => TodoPhase.running,
      _ => TodoPhase.waiting,
    };

/// One agent's todo list (web AgentTodoPanel item): a title, a count of what is
/// running / waiting / done, a progress bar, and one row per todo whose icon,
/// weight and trailing label all say which of the three it is.
class TodoGroup extends StatelessWidget {
  const TodoGroup(
      {super.key, required this.title, required this.todos, this.onRemove});
  final String title;
  final List<AgentTodo> todos;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final phases = todos.map(todoPhase).toList();
    int count(TodoPhase p) => phases.where((x) => x == p).length;
    final done = count(TodoPhase.done);
    final running = count(TodoPhase.running);
    final waiting = count(TodoPhase.waiting);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checklist, size: 14, color: c.accent),
            const SizedBox(width: AppTokens.s6),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            Text('$done/${todos.length}',
                style: TextStyle(color: c.textMuted, fontSize: 11)),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(AppTokens.rFull),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: c.textMuted),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.s6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.rSm),
          child: LinearProgressIndicator(
            value: todos.isEmpty ? 0 : done / todos.length,
            minHeight: 3,
            backgroundColor: c.surfaceAlt,
            color: running > 0 ? c.accent : AppTokens.success,
          ),
        ),
        const SizedBox(height: AppTokens.s8),
        Wrap(
          spacing: AppTokens.s12,
          runSpacing: AppTokens.s4,
          children: [
            _Count(TodoPhase.running, running),
            _Count(TodoPhase.waiting, waiting),
            _Count(TodoPhase.done, done),
          ],
        ),
        const SizedBox(height: AppTokens.s6),
        for (var i = 0; i < todos.length; i++)
          _TodoRow(todo: todos[i], phase: phases[i]),
      ],
    );
  }
}

String _label(BuildContext context, TodoPhase p) => switch (p) {
      TodoPhase.done => context.tr('Done'),
      TodoPhase.running => context.tr('Running'),
      TodoPhase.waiting => context.tr('Waiting'),
    };

Color _color(BuildContext context, TodoPhase p) => switch (p) {
      TodoPhase.done => AppTokens.success,
      TodoPhase.running => context.colors.accent,
      TodoPhase.waiting => context.colors.textMuted,
    };

/// "1 Running" — the colour of the phase, dimmed when there are none.
class _Count extends StatelessWidget {
  const _Count(this.phase, this.n);
  final TodoPhase phase;
  final int n;

  @override
  Widget build(BuildContext context) {
    final color = _color(context, phase);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: phase == TodoPhase.waiting ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      ),
      const SizedBox(width: AppTokens.s4),
      Text('$n ${_label(context, phase)}',
          style: TextStyle(
              color: n == 0 ? context.colors.textMuted : color,
              fontSize: 11,
              fontWeight: n == 0 ? FontWeight.w400 : FontWeight.w600)),
    ]);
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.todo, required this.phase});
  final AgentTodo todo;
  final TodoPhase phase;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _color(context, phase);
    final running = phase == TodoPhase.running;
    final done = phase == TodoPhase.done;
    // A running todo reads in its "-ing" form when the agent gave one.
    final text = running && todo.activeForm.isNotEmpty
        ? todo.activeForm
        : todo.content;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s8, vertical: AppTokens.s6),
      decoration: BoxDecoration(
        color: running ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        border: Border.all(
            color: running ? c.accent.withValues(alpha: 0.4) : Colors.transparent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Center(
              child: switch (phase) {
                TodoPhase.running => SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.accent)),
                TodoPhase.done =>
                  Icon(Icons.check_circle, size: 16, color: color),
                TodoPhase.waiting =>
                  Icon(Icons.radio_button_unchecked, size: 16, color: color),
              },
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                  color: done
                      ? c.textMuted
                      : (running ? c.textPrimary : c.textSecondary),
                  fontSize: 12,
                  fontWeight: running ? FontWeight.w600 : FontWeight.w400,
                  decoration: done ? TextDecoration.lineThrough : null,
                )),
          ),
          const SizedBox(width: AppTokens.s8),
          Text(_label(context, phase),
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
