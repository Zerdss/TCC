import 'dart:io';

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

  test('SessionRecorder registra alertas de cabeça e de rosto ausente', () {
    final r = SessionRecorder(startedAt: t0, earThreshold: 0.2, marThreshold: 0.6, calibrated: false);
    DateTime at(int s) => t0.add(Duration(seconds: s));
    r.add(const FatigueMetrics(ear: 0.3), FatigueStatus.normal, at(1));
    r.add(const FatigueMetrics(alert: true, alertReason: AlertReason.head), FatigueStatus.alert, at(2));
    r.add(const FatigueMetrics(ear: 0.3), FatigueStatus.normal, at(5));
    r.add(const FatigueMetrics(alert: true, alertReason: AlertReason.faceLost), FatigueStatus.alert, at(9));
    r.add(const FatigueMetrics(ear: 0.3), FatigueStatus.normal, at(12));
    final s = r.finish();
    expect(s.alertsHead, 1);
    expect(s.alertsFace, 1);
    expect(s.totalAlerts, 2);
  });

  test('banco antigo (v1) é atualizado para v2 sem perder sessões', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync().path}/v1.db';
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, started_at TEXT NOT NULL, '
                'ended_at TEXT NOT NULL, duration_s REAL NOT NULL, alerts_eyes INTEGER NOT NULL, '
                'alerts_yawn INTEGER NOT NULL, attention_count INTEGER NOT NULL, max_perclos REAL NOT NULL, '
                'avg_blink_rate REAL NOT NULL, ear_threshold REAL NOT NULL, mar_threshold REAL NOT NULL, '
                'calibrated INTEGER NOT NULL)');
            await db.execute('CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id INTEGER NOT NULL, '
                'time TEXT NOT NULL, type TEXT NOT NULL, ear REAL NOT NULL, mar REAL NOT NULL, perclos REAL NOT NULL)');
            final m = sampleSession().toMap()
              ..remove('alerts_head')
              ..remove('alerts_face');
            await db.insert('sessions', m);
          },
        ));
    await old.close();
    final db = await SessionDatabase.open(factory: databaseFactoryFfi, path: path);
    final sessions = await db.listSessions();
    expect(sessions, hasLength(1));
    expect(sessions.first.alertsHead, 0);
    await db.insertSession(sampleSession());
    expect(await db.listSessions(), hasLength(2));
    await db.close();
  });

  test('CSV usa ; e uma linha por sessão/evento', () {
    final s = sampleSession();
    final csv = sessionsToCsv([s]).trim().split('\n');
    expect(csv, hasLength(3)); // cabeçalho, sessão e TOTAL
    expect(csv.first, startsWith('Sessão;Data;Início;Fim;Duração;Total de alertas'));
    final row = csv[1].split(';');
    expect(row, hasLength(sessionsCsvHeader.length));
    expect(row[0], '1');
    expect(row[1], csvDate(s.startedAt));
    expect(row[4], '00:00:30');
    expect(row[5], '2');
    expect(row[11], '5,0'); // PERCLOS em %, vírgula decimal
    expect(row.last, 'Sim');
    expect(csv[2], startsWith('TOTAL;1 sessão'));
    final ev = eventsToCsv(s.events).trim().split('\n');
    expect(ev, hasLength(4));
    expect(ev.first, 'Sessão;Data;Horário;Tempo na sessão;Tipo;EAR (olhos);MAR (boca);PERCLOS (%)');
    expect(ev[2], contains(';ALERTA - olhos fechados;'));
  });

  test('CSV: sessões em ordem cronológica, numeradas, e eventos ligados à sessão', () {
    final a = sampleSession();
    final later = SessionRecord(
      id: 7,
      startedAt: a.startedAt.add(const Duration(hours: 2)),
      endedAt: a.startedAt.add(const Duration(hours: 3, minutes: 5)),
      alertsEyes: 0,
      alertsYawn: 0,
      attentionCount: 0,
      maxPerclos: 0.1,
      avgBlinkRate: 15,
      earThreshold: 0.2,
      marThreshold: 0.6,
      calibrated: false,
    );
    final first = SessionRecord.fromMap({...a.toMap(), 'id': 3});
    final csv = sessionsToCsv([later, first]).trim().split('\n');
    expect(csv[1].split(';')[2], csvTime(first.startedAt));
    expect(csv[2].split(';')[4], '01:05:00');
    expect(csv[2].split(';').last, 'Não');
    expect(csv[3], startsWith('TOTAL;2 sessões;;;01:05:30'));
    final ev = SessionEvent(
        sessionId: 7,
        time: later.startedAt.add(const Duration(minutes: 3, seconds: 4)),
        type: EventType.head,
        ear: 0.2,
        mar: 0.1,
        perclos: 0.03);
    final row = eventsToCsv([ev], sessions: [later, first]).trim().split('\n')[1].split(';');
    expect(row[0], '2');
    expect(row[3], '00:03:04');
    expect(row[4], 'ALERTA - cabeça caindo');
  });

  test('relatório único: resumo, sessões, alertas e legenda separados por linhas em branco', () {
    final s = sampleSession();
    final csv = reportToCsv([s], s.events, generatedAt: DateTime(2026, 11, 11, 18, 30));
    final lines = csv.split('\n');
    expect(lines.first, 'FATIGUE GUARD - RELATÓRIO DE MONITORAMENTO');
    expect(lines, contains('Gerado em;11/11/2026 18:30:00'));
    expect(lines, contains('Sessões;1'));
    expect(lines, contains('Total de alertas;2'));
    final i1 = lines.indexOf('1. RESUMO DAS SESSÕES');
    final i2 = lines.indexOf('2. ALERTAS E AVISOS');
    final i3 = lines.indexOf('3. COMO LER ESTE ARQUIVO');
    expect(i1, greaterThan(0));
    expect(i2, greaterThan(i1));
    expect(i3, greaterThan(i2));
    // cada seção começa depois de linhas em branco (não fica grudada)
    expect(lines[i1 - 1], isEmpty);
    expect(lines[i2 - 1], isEmpty);
    expect(lines[i3 - 1], isEmpty);
    expect(lines[i1 + 3], startsWith('Sessão;Data;Início'));
    expect(lines.sublist(i1, i2).any((l) => l.startsWith('TOTAL;')), isTrue);
    expect(lines.sublist(i2, i3).where((l) => l.contains('ALERTA - ')), hasLength(2));
    expect(lines.sublist(i3), contains(startsWith('PERCLOS (%);')));
  });

  test('relatório sem alertas avisa em vez de deixar a tabela vazia', () {
    final s = sampleSession();
    final csv = reportToCsv([s], const []);
    expect(csv, contains('Nenhum alerta ou aviso registrado.'));
  });

  test('CSV escapa campos com ponto e vírgula', () {
    expect(csvField('a;b'), '"a;b"');
    expect(csvField('diz "oi"'), '"diz ""oi"""');
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

  test('CalibrationStore guarda a qualidade dos olhos (modo de reforço)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CalibrationStore();
    final t = Thresholds()
      ..applyCalibration(0, 0.20, 0.05, medianProb: 0.9)
      ..applyCalibration(1, 0.15, 0.05, medianProb: 0.1);
    await store.save(t);
    final saved = (await store.load())!;
    expect(saved.lowEyeConfidence, isTrue);
    expect(saved.eyeSeparation, closeTo(0.25, 1e-9));
    expect(saved.eyeProbThreshold, closeTo(0.42, 1e-9));
  });
}
