import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task_record.dart';
import '../services/local_store.dart';
import '../services/reminder_service.dart';
import '../utils/dates.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final store = LocalStore();
  List<TaskRecord> tasks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final t = await store.getTasks();
    if (mounted) {
      setState(() {
        tasks = t;
        loading = false;
      });
    }
    for (final task in t.where((task) => !task.done)) {
      await ReminderService.syncTask(task);
    }
  }

  Future<void> _save() => store.saveTasks(tasks);

  Future<void> add() async {
    final controller = TextEditingController();
    DateTime? due;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('New task'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Task or reminder',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: due ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 730)),
                          );
                          setDialogState(() => due = picked ?? due);
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          due == null
                              ? 'Set a deadline (optional)'
                              : 'Deadline: ${DateFormat('d MMM y').format(due!)}',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Add'),
                    ),
                  ],
                ),
          ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      final task = TaskRecord(
        id: store.newId(),
        title: controller.text.trim(),
        dueDate: due,
        createdAt: DateTime.now(),
      );
      setState(() {
        tasks.insert(0, task);
      });
      await _save();
      await ReminderService.syncTask(task);
    }
  }

  Future<void> _toggleDone(TaskRecord task, bool value) async {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) return;
    final updated = tasks[i].copyWith(done: value);
    setState(() {
      tasks[i] = updated;
    });
    await _save();
    await ReminderService.syncTask(updated);
  }

  Future<void> _delete(TaskRecord task) async {
    setState(() => tasks.removeWhere((t) => t.id == task.id));
    await _save();
    await ReminderService.cancel('task-${task.id}');
    await ReminderService.cancel('overdue-${task.id}');
  }

  List<TaskRecord> get openTasks =>
      tasks.where((t) => !t.done).toList()..sort((a, b) {
        final aDue = a.dueDate, bDue = b.dueDate;
        if (aDue == null && bDue == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        if (aDue == null) return 1;
        if (bDue == null) return -1;
        return aDue.compareTo(bDue);
      });

  List<TaskRecord> get doneTasks => tasks.where((t) => t.done).toList();

  String _dueSubtitle(TaskRecord task) {
    final due = task.dueDate;
    if (due == null) return '';
    final label = dayLabel(due, DateTime.now());
    return isOverdue(due, DateTime.now()) ? 'Overdue · $label' : 'Due $label';
  }

  Widget _tile(TaskRecord task) {
    final theme = Theme.of(context);
    final done = task.done;
    final subtitle = _dueSubtitle(task);
    final overdue =
        !done &&
        task.dueDate != null &&
        isOverdue(task.dueDate!, DateTime.now());
    return CheckboxListTile(
      value: done,
      onChanged: (v) => _toggleDone(task, v == true),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        task.title,
        style: TextStyle(
          decoration: done ? TextDecoration.lineThrough : null,
          color:
              done ? theme.colorScheme.onSurface.withValues(alpha: 0.55) : null,
        ),
      ),
      subtitle:
          subtitle.isEmpty
              ? null
              : Text(
                subtitle,
                style: TextStyle(
                  color:
                      overdue
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
      secondary: IconButton(
        tooltip: 'Delete task',
        icon: Icon(
          Icons.delete_outline,
          size: 22,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        onPressed: () => _delete(task),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tasks & reminders')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final open = openTasks;
    final done = doneTasks;
    final empty = tasks.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & reminders'),
        actions: [IconButton(onPressed: add, icon: const Icon(Icons.add))],
      ),
      body:
          empty
              ? const Center(
                child: Text('No tasks yet. Add a follow-up reminder.'),
              )
              : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (open.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        'Open (${open.length})',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    ...open.map(_tile),
                  ],
                  if (done.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        'Completed (${done.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                    ...done.map(_tile),
                  ],
                ],
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }
}
