import 'package:fatigue_guard/data/calibration_store.dart';
import 'package:fatigue_guard/data/csv_export.dart';
import 'package:fatigue_guard/data/models.dart';
import 'package:fatigue_guard/data/session_database.dart';
import 'package:fatigue_guard/data/session_recorder.dart';
import 'package:fatigue_guard/vision/fatigue_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final t0 = DateTime(2026, 11, 5, 10);

SessionRecord sampleSession() {
  final r = SessionRecorder(startedAt: t0, earThreshold: 0.2, marThreshold: 0.6, calibrated: true);
  const normal = FatigueMetrics(ear: 0.3, mar: 0.1, blinkRate: 12);
  const attention = FatigueMetrics(ear: 0.15, mar: 0.1, closedMs: 800, blinkRate: 12, perclos: 0.02);
  const alertEyes = FatigueMetrics(
      ear: 0.1, mar: 0.1, closedMs: 1300, perclos: 0.05, alert: true, alertReason: AlertReason.eyes);
  const alertYawn = FatigueMetrics(ear: 0.3, mar: 0.8, alert: true, alertReason: AlertReason.yawn, perclos: 0.04);

  DateTime at(int s) => t0.add(Duration(seconds: s));
  r.add(normal, FatigueStatus.normal, at(1));
  r.add(attention, FatigueStatus.attention, at(5));
  r.add(alertEyes, FatigueStatus.alert, at(6));
  r.add(alertEyes, FatigueStatus.alert, at(7)); // mesmo alerta, não conta de novo
  r.add(normal, FatigueStatus.normal, at(10));
  r.add(alertYawn, FatigueStatus.alert, at(20));
  r.add(normal, FatigueStatus.normal, at(30));
  return r.finish();
}

void main() {
  test('SessionRecorder conta transições e calcula resumo', () {
    final s = sampleSession();
    expect(s.alertsEyes, 1);
    expect(s.alertsYawn, 1);
    expect(s.attentionCount, 1);
    expect(s.events.map((e) => e.type), [EventType.attention, EventType.eyes, EventType.yawn]);
    expect(s.maxPerclos, closeTo(0.05, 1e-9));
    expect(s.duration, const Duration(seconds: 30));
    expect(s.calibrated, isTrue);
  });

  group('SessionDatabase (SQLite)', () {
    late SessionDatabase db;
    setUp(() async {
      sqfliteFfiInit();
      db = await SessionDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    test('grava e lê sessões com eventos', () async {
      final id = await db.insertSession(sampleSession());
      final sessions = await db.listSessions();
      expect(sessions, hasLength(1));
      expect(sessions.first.id, id);
      expect(sessions.first.alertsEyes, 1);
      expect(sessions.first.duration, const Duration(seconds: 30));
      final events = await db.eventsFor(id);
      expect(events, hasLength(3));
      expect(events[1].type, EventType.eyes);
      expect(events[1].ear, closeTo(0.1, 1e-9));
    });

    test('lista da mais recente para a mais antiga e apaga em cascata', () async {
      final first = await db.insertSession(sampleSession());
      final later = SessionRecord.fromMap({
        ...sampleSession().toMap(),
        'started_at': t0.add(const Duration(days: 1)).toIso8601String(),
        'ended_at': t0.add(const Duration(days: 1, minutes: 1)).toIso8601String(),
      });
      final second = await db.insertSession(later);
      expect((await db.listSessions()).map((s) => s.id), [second, first]);

      await db.deleteSession(first);
      expect(await db.eventsFor(first), isEmpty);
      await db.deleteAll();
      expect(await db.listSessions(), isEmpty);
    });
  });

  test('CSV usa ; e uma linha por sessão/evento', () {
    final s = sampleSession();
    final csv = sessionsToCsv([s]).trim().split('\n');
    expect(csv, hasLength(2));
    expect(csv.first, startsWith('id;inicio;fim;duracao_s'));
    expect(csv[1].split(';'), hasLength(12));
    final ev = eventsToCsv(s.events).trim().split('\n');
    expect(ev, hasLength(4));
    expect(ev[2], contains(';eyes;'));
  });

  test('CalibrationStore salva e restaura limiares', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CalibrationStore();
    expect(await store.load(), isNull);
    final t = Thresholds()..restore(ear: 0.17, mar: 0.66, marNeutral: 0.33);
    await store.save(t);
    final saved = await store.load();
    expect(saved!.ear, 0.17);
    expect(saved.mar, 0.66);
    expect(saved.marNeutral, 0.33);
    await store.clear();
    expect(await store.load(), isNull);
  });
}
