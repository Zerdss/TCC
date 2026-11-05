/// Tipos de evento registrados durante o monitoramento.
enum EventType { eyes, yawn, attention }

extension EventTypeLabel on EventType {
  String get code => name;

  String get label => switch (this) {
        EventType.eyes => 'Alerta: olhos fechados',
        EventType.yawn => 'Alerta: bocejo sustentado',
        EventType.attention => 'Atenção',
      };

  static EventType fromCode(String code) =>
      EventType.values.firstWhere((e) => e.name == code, orElse: () => EventType.attention);
}

/// Evento (alerta ou atenção) ocorrido numa sessão. Só números — nunca imagens.
class SessionEvent {
  const SessionEvent({
    this.id,
    this.sessionId,
    required this.time,
    required this.type,
    required this.ear,
    required this.mar,
    required this.perclos,
  });

  final int? id;
  final int? sessionId;
  final DateTime time;
  final EventType type;
  final double ear;
  final double mar;
  final double perclos;

  Map<String, Object?> toMap(int sessionId) => {
        'session_id': sessionId,
        'time': time.toIso8601String(),
        'type': type.code,
        'ear': ear,
        'mar': mar,
        'perclos': perclos,
      };

  factory SessionEvent.fromMap(Map<String, Object?> m) => SessionEvent(
        id: m['id'] as int?,
        sessionId: m['session_id'] as int?,
        time: DateTime.parse(m['time'] as String),
        type: EventTypeLabel.fromCode(m['type'] as String),
        ear: (m['ear'] as num).toDouble(),
        mar: (m['mar'] as num).toDouble(),
        perclos: (m['perclos'] as num).toDouble(),
      );
}

/// Resumo de uma sessão de monitoramento.
class SessionRecord {
  const SessionRecord({
    this.id,
    required this.startedAt,
    required this.endedAt,
    required this.alertsEyes,
    required this.alertsYawn,
    required this.attentionCount,
    required this.maxPerclos,
    required this.avgBlinkRate,
    required this.earThreshold,
    required this.marThreshold,
    required this.calibrated,
    this.events = const [],
  });

  final int? id;
  final DateTime startedAt;
  final DateTime endedAt;
  final int alertsEyes;
  final int alertsYawn;
  final int attentionCount;
  final double maxPerclos;
  final double avgBlinkRate;
  final double earThreshold;
  final double marThreshold;
  final bool calibrated;
  final List<SessionEvent> events;

  Duration get duration => endedAt.difference(startedAt);
  int get totalAlerts => alertsEyes + alertsYawn;

  Map<String, Object?> toMap() => {
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_s': duration.inMilliseconds / 1000,
        'alerts_eyes': alertsEyes,
        'alerts_yawn': alertsYawn,
        'attention_count': attentionCount,
        'max_perclos': maxPerclos,
        'avg_blink_rate': avgBlinkRate,
        'ear_threshold': earThreshold,
        'mar_threshold': marThreshold,
        'calibrated': calibrated ? 1 : 0,
      };

  factory SessionRecord.fromMap(Map<String, Object?> m, {List<SessionEvent> events = const []}) =>
      SessionRecord(
        id: m['id'] as int?,
        startedAt: DateTime.parse(m['started_at'] as String),
        endedAt: DateTime.parse(m['ended_at'] as String),
        alertsEyes: m['alerts_eyes'] as int,
        alertsYawn: m['alerts_yawn'] as int,
        attentionCount: m['attention_count'] as int,
        maxPerclos: (m['max_perclos'] as num).toDouble(),
        avgBlinkRate: (m['avg_blink_rate'] as num).toDouble(),
        earThreshold: (m['ear_threshold'] as num).toDouble(),
        marThreshold: (m['mar_threshold'] as num).toDouble(),
        calibrated: (m['calibrated'] as int) == 1,
        events: events,
      );
}
