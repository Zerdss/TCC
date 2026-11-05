import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Banco SQLite local (no próprio aparelho) com o histórico das sessões.
///
/// Tabelas:
/// * `sessions` — resumo de cada sessão de monitoramento;
/// * `events`   — alertas e avisos de atenção de cada sessão (FK → sessions);
///   `type` = eyes | yawn | head | faceLost | attention.
///
/// Apenas números e horários são gravados; nenhuma imagem ou vídeo.
class SessionDatabase {
  SessionDatabase._(this._db);

  final Database _db;

  /// v2: colunas alerts_head e alerts_face.
  static const _version = 2;

  /// Abre (ou cria) o banco. [factory] e [path] permitem usar um banco em
  /// memória nos testes.
  static Future<SessionDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'fatigue_guard.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              started_at TEXT NOT NULL,
              ended_at TEXT NOT NULL,
              duration_s REAL NOT NULL,
              alerts_eyes INTEGER NOT NULL,
              alerts_yawn INTEGER NOT NULL,
              alerts_head INTEGER NOT NULL DEFAULT 0,
              alerts_face INTEGER NOT NULL DEFAULT 0,
              attention_count INTEGER NOT NULL,
              max_perclos REAL NOT NULL,
              avg_blink_rate REAL NOT NULL,
              ear_threshold REAL NOT NULL,
              mar_threshold REAL NOT NULL,
              calibrated INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              time TEXT NOT NULL,
              type TEXT NOT NULL,
              ear REAL NOT NULL,
              mar REAL NOT NULL,
              perclos REAL NOT NULL
            )''');
          await db.execute('CREATE INDEX idx_events_session ON events(session_id)');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE sessions ADD COLUMN alerts_head INTEGER NOT NULL DEFAULT 0');
            await db.execute('ALTER TABLE sessions ADD COLUMN alerts_face INTEGER NOT NULL DEFAULT 0');
          }
        },
      ),
    );
    return SessionDatabase._(db);
  }

  /// Grava a sessão e seus eventos numa única transação. Retorna o id.
  Future<int> insertSession(SessionRecord session) {
    return _db.transaction((txn) async {
      final id = await txn.insert('sessions', session.toMap());
      final batch = txn.batch();
      for (final e in session.events) {
        batch.insert('events', e.toMap(id));
      }
      await batch.commit(noResult: true);
      return id;
    });
  }

  /// Sessões da mais recente para a mais antiga (sem eventos).
  Future<List<SessionRecord>> listSessions() async {
    final rows = await _db.query('sessions', orderBy: 'started_at DESC');
    return rows.map(SessionRecord.fromMap).toList();
  }

  Future<List<SessionEvent>> eventsFor(int sessionId) async {
    final rows = await _db.query('events', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'time');
    return rows.map(SessionEvent.fromMap).toList();
  }

  Future<List<SessionEvent>> allEvents() async {
    final rows = await _db.query('events', orderBy: 'time');
    return rows.map(SessionEvent.fromMap).toList();
  }

  Future<void> deleteSession(int id) => _db.delete('sessions', where: 'id = ?', whereArgs: [id]);

  Future<void> deleteAll() async {
    await _db.delete('events');
    await _db.delete('sessions');
  }

  Future<void> close() => _db.close();
}
