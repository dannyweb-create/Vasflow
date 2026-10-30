import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'auth_service.dart';
import 'backup_models.dart';
import 'backup_repository.dart';
import 'backup_service.dart';
import 'local_store.dart';

/// How often an automatic backup should be attempted. "Automatic" means
/// app-open scheduling: the check runs when the app is opened (and when the
/// main workspace screen returns from older sessions), never while the app is
/// closed. This is NOT a server-side scheduler; see the phase D docs for the
/// exact infrastructure a cron-based (server-side) backup would need.
enum BackupCadence { off, daily, weekly }

/// App-open automatic backups with restart-safe duplicate prevention.
///
/// Duplicate prevention is based entirely on the backup HISTORY table, never
/// on device state, so it survives app restarts and even uninstalls: an auto
/// backup only runs when the current period has no completed or recent
/// automatic backup yet. Failed attempts ARE retried on the next open, and a
/// crash mid-run leaves a `running` row that stops blocking after a grace
/// period so the next open can repair it (run() never marks an incomplete run
/// as completed; it records failed with the real error).
class BackupScheduler {
  static const prefKey = 'backup_auto_cadence';

  /// A `running` auto row younger than this is considered in progress; older
  /// rows (app killed mid-run) no longer block a retry.
  static const runningGrace = Duration(hours: 6);

  static final schedulerInstance = BackupScheduler();

  bool _busy = false;

  Future<BackupCadence> readCadence([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    final value = prefs.getString(prefKey) ?? 'off';
    return switch (value) {
      'daily' => BackupCadence.daily,
      'weekly' => BackupCadence.weekly,
      _ => BackupCadence.off,
    };
  }

  Future<void> setCadence(BackupCadence cadence) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, cadence.name);
  }

  /// Pure period rule: daily = the current UTC day, weekly = the current
  /// ISO week starting Monday 00:00 UTC. Off has no meaningful period.
  static DateTime periodStartUtc(BackupCadence cadence, DateTime now) {
    final utc = now.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    if (cadence == BackupCadence.daily) return day;
    if (cadence == BackupCadence.weekly) {
      final weekday = utc.weekday; // 1 = Monday ... 7 = Sunday
      return day.subtract(Duration(days: weekday - 1));
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Whether an automatic backup is due right now.
  ///
  /// Returns false when: cadence is off, an auto backup in the current period
  /// already completed or is actively running (within [runningGrace]). A
  /// failed auto attempt in the period does NOT block - the next open retries,
  /// which is the only recovery path in app-open scheduling.
  static bool shouldRun({
    required BackupCadence cadence,
    required List<BackupEntry> history,
    required DateTime now,
    Duration? runningGraceOverride,
  }) {
    if (cadence == BackupCadence.off) return false;
    final start = periodStartUtc(cadence, now);
    final grace = runningGraceOverride ?? runningGrace;
    for (final entry in history) {
      if (entry.kind != 'auto') continue;
      final when = entry.startedAt ?? entry.createdAt;
      if (when == null) continue;
      if (!when.isAfter(start) && !when.isAtSameMomentAs(start)) continue;
      if (entry.completed) return false;
      if (entry.running && now.difference(when) < grace) return false;
    }
    return true;
  }

  /// Called when the app opens. Returns true if a backup actually ran and
  /// completed. Failures are recorded on the history row by the service; this
  /// method stays quiet by design (the history screen is the report).
  Future<bool> runIfDue(
    AuthService auth, {
    BackupRepository? repoOverride,
    BackupService? serviceOverride,
  }) async {
    if (_busy) return false;
    try {
      if (!AppConfig.supabaseReady) return false;
      if (!auth.isAdmin) return false;
      final wsId = auth.workspaceId;
      if (wsId == null || wsId.isEmpty) return false;
      final cadence = await readCadence();
      if (cadence == BackupCadence.off) return false;
      final repo = repoOverride ?? BackupRepository();
      final service =
          serviceOverride ??
          BackupService(auth: auth, repo: repo, local: LocalStore());
      final history = await repo.list(wsId);
      if (!shouldRun(
        cadence: cadence,
        history: history,
        now: DateTime.now().toUtc(),
      )) {
        return false;
      }
      _busy = true;
      try {
        await service.run(automatic: true);
        return true;
      } catch (e, st) {
        // Never fake success: the run already rows-marked itself failed.
        debugPrint('Automatic backup failed: $e');
        debugPrintStack(stackTrace: st, maxFrames: 4);
        return false;
      } finally {
        _busy = false;
      }
    } catch (_) {
      return false;
    }
  }
}
