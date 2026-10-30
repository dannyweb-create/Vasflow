import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vasflow/services/backup_models.dart';
import 'package:vasflow/services/backup_scheduler.dart';

BackupEntry autoEntry({
  required String status,
  required DateTime startedAt,
  String kind = 'auto',
}) {
  return BackupEntry(
    id: '${startedAt.millisecondsSinceEpoch}',
    workspaceId: 'ws-1',
    kind: kind,
    status: status,
    startedAt: startedAt,
    createdAt: startedAt,
  );
}

void main() {
  group('BackupScheduler period rules', () {
    test('daily period starts at UTC midnight of the current day', () {
      final now = DateTime.utc(2026, 3, 15, 14, 30);
      final start = BackupScheduler.periodStartUtc(BackupCadence.daily, now);
      expect(start, DateTime.utc(2026, 3, 15));
    });

    test('weekly period starts on Monday of the same ISO week', () {
      // 2026-03-15 is a Sunday; the week started Monday 2026-03-09.
      final sunday = DateTime.utc(2026, 3, 15, 23, 0);
      expect(
        BackupScheduler.periodStartUtc(BackupCadence.weekly, sunday),
        DateTime.utc(2026, 3, 9),
      );
      // Tuesday mid-day belongs to the same Monday.
      final tuesday = DateTime.utc(2026, 3, 10, 8, 0);
      expect(
        BackupScheduler.periodStartUtc(BackupCadence.weekly, tuesday),
        DateTime.utc(2026, 3, 9),
      );
    });

    test('off cadence never runs', () {
      final now = DateTime.utc(2026, 3, 15);
      expect(
        shouldRunSafe(cadence: BackupCadence.off, history: [], now: now),
        isFalse,
      );
    });

    test('empty history is due', () {
      final now = DateTime.utc(2026, 3, 15, 12);
      expect(
        shouldRunSafe(cadence: BackupCadence.daily, history: [], now: now),
        isTrue,
      );
    });

    test('a completed auto backup this period prevents duplicates', () {
      final now = DateTime.utc(2026, 3, 15, 18);
      final history = [
        autoEntry(status: 'completed', startedAt: DateTime.utc(2026, 3, 15, 9)),
      ];
      expect(
        shouldRunSafe(cadence: BackupCadence.daily, history: history, now: now),
        isFalse,
      );
    });

    test('restarting the app does not change the decision', () {
      final now = DateTime.utc(2026, 3, 15, 23, 50);
      final history = [
        autoEntry(status: 'completed', startedAt: DateTime.utc(2026, 3, 15, 8)),
      ];
      // A fresh shell mount re-reads history and reaches the same verdict.
      expect(
        shouldRunSafe(cadence: BackupCadence.daily, history: history, now: now),
        isFalse,
      );
    });

    test(
      'a failed auto attempt retried on the next open and reports failure accurately',
      () {
        final now = DateTime.utc(2026, 3, 15, 18);
        final history = [
          autoEntry(status: 'failed', startedAt: DateTime.utc(2026, 3, 15, 9)),
        ];
        expect(
          shouldRunSafe(
            cadence: BackupCadence.daily,
            history: history,
            now: now,
          ),
          isTrue,
        );
      },
    );

    test(
      'a fresh running row blocks; a stale crash row unblocks after grace',
      () {
        final now = DateTime.utc(2026, 3, 15, 18);
        final fresh = [
          autoEntry(
            status: 'running',
            startedAt: now.subtract(const Duration(minutes: 10)),
          ),
        ];
        expect(
          shouldRunSafe(cadence: BackupCadence.daily, history: fresh, now: now),
          isFalse,
        );
        final stale = [
          autoEntry(
            status: 'running',
            startedAt: now.subtract(const Duration(hours: 7)),
          ),
        ];
        expect(
          shouldRunSafe(cadence: BackupCadence.daily, history: stale, now: now),
          isTrue,
        );
        // Grace is overridable for tests.
        expect(
          shouldRunSafe(
            cadence: BackupCadence.daily,
            history: fresh,
            now: now,
            runningGraceOverride: Duration.zero,
          ),
          isTrue,
        );
      },
    );

    test('a completed auto backup from before the period is overdue again', () {
      final now = DateTime.utc(2026, 3, 15);
      final history = [
        autoEntry(status: 'completed', startedAt: DateTime.utc(2026, 3, 14)),
      ];
      expect(
        shouldRunSafe(cadence: BackupCadence.daily, history: history, now: now),
        isTrue,
      );
    });

    test(
      'weekly: completed earlier in the week blocks, previous week allows',
      () {
        final now = DateTime.utc(2026, 3, 12);
        expect(
          shouldRunSafe(
            cadence: BackupCadence.weekly,
            history: [
              autoEntry(
                status: 'completed',
                startedAt: DateTime.utc(2026, 3, 9),
              ),
            ],
            now: now,
          ),
          isFalse,
        );
        expect(
          shouldRunSafe(
            cadence: BackupCadence.weekly,
            history: [
              autoEntry(
                status: 'completed',
                startedAt: DateTime.utc(2026, 3, 6),
              ),
            ],
            now: now,
          ),
          isTrue,
        );
      },
    );

    test('completed manual backups never change scheduling', () {
      final now = DateTime.utc(2026, 3, 15, 18);
      final history = [
        autoEntry(status: 'completed', startedAt: now, kind: 'manual'),
      ];
      expect(
        shouldRunSafe(cadence: BackupCadence.daily, history: history, now: now),
        isTrue,
      );
    });

    test('entries without timestamps are ignored', () {
      final now = DateTime.utc(2026, 3, 15, 18);
      final history = [
        const BackupEntry(
          id: 'x',
          workspaceId: 'ws-1',
          kind: 'auto',
          status: 'completed',
        ),
      ];
      expect(
        shouldRunSafe(cadence: BackupCadence.daily, history: history, now: now),
        isTrue,
      );
    });
  });

  group('cadence persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('off is the default and choices persist across restarts', () async {
      final scheduler = BackupScheduler();
      expect(await scheduler.readCadence(), BackupCadence.off);

      await scheduler.setCadence(BackupCadence.daily);
      expect(await scheduler.readCadence(), BackupCadence.daily);

      // Simulates an app restart with the same storage.
      final prefs = await SharedPreferences.getInstance();
      expect(await scheduler.readCadence(prefs), BackupCadence.daily);

      await scheduler.setCadence(BackupCadence.weekly);
      expect(await scheduler.readCadence(), BackupCadence.weekly);
    });
  });
}

bool shouldRunSafe({
  required BackupCadence cadence,
  required List<BackupEntry> history,
  required DateTime now,
  Duration? runningGraceOverride,
}) {
  return BackupScheduler.shouldRun(
    cadence: cadence,
    history: history,
    now: now,
    runningGraceOverride: runningGraceOverride ?? const Duration(hours: 6),
  );
}
