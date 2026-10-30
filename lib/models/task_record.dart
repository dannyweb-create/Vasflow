class TaskRecord {
  final String id;
  final String title;
  final bool done;
  final DateTime? dueDate;
  final DateTime createdAt;

  const TaskRecord({
    required this.id,
    required this.title,
    this.done = false,
    this.dueDate,
    required this.createdAt,
  });

  TaskRecord copyWith({String? title, bool? done, DateTime? dueDate}) =>
      TaskRecord(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
        dueDate: dueDate ?? this.dueDate,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'done': done,
    'due_date': dueDate?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory TaskRecord.fromJson(Map<String, dynamic> j) => TaskRecord(
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    done: j['done'] == true,
    dueDate:
        j['due_date'] == null ? null : DateTime.tryParse('${j['due_date']}'),
    createdAt: DateTime.tryParse('${j['created_at'] ?? ''}') ?? DateTime.now(),
  );
}
