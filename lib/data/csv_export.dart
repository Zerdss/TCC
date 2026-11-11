import 'models.dart';

// ---------------------------------------------------------------------------
// Exportação em CSV pronta para abrir no Excel / Planilhas Google em português:
// separador `;`, vírgula decimal, datas dd/mm/aaaa, cabeçalhos legíveis e
// sessões em ordem cronológica, com uma linha de TOTAL no fim.
// ---------------------------------------------------------------------------

const _sep = ';';

String _two(int v) => v.toString().padLeft(2, '0');

/// 11/11/2026
String csvDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// 17:05:09
String csvTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// Duração como hh:mm:ss (ex.: 00:12:05).
String csvDuration(Duration d) {
  final s = d.inSeconds.abs();
  return '${_two(s ~/ 3600)}:${_two(s % 3600 ~/ 60)}:${_two(s % 60)}';
}

/// Número com vírgula decimal (padrão brasileiro).
String csvNum(double v, int digits) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// Escapa um campo que tenha `;`, aspas ou quebra de linha.
String csvField(Object? v) {
  final s = '${v ?? ''}';
  if (s.contains(_sep) || s.contains('"') || s.contains('\n')) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _row(List<Object?> cells) => cells.map(csvField).join(_sep);

/// Nome legível do tipo de evento para a planilha.
String eventTypeName(EventType t) => switch (t) {
      EventType.eyes => 'ALERTA - olhos fechados',
      EventType.yawn => 'ALERTA - bocejo',
      EventType.head => 'ALERTA - cabeça caindo',
      EventType.faceLost => 'ALERTA - rosto fora da câmera',
      EventType.attention => 'Atenção',
    };

const sessionsCsvHeader = [
  'Sessão',
  'Data',
  'Início',
  'Fim',
  'Duração',
  'Total de alertas',
  'Alertas: olhos fechados',
  'Alertas: bocejo',
  'Alertas: cabeça caindo',
  'Alertas: rosto fora da câmera',
  'Avisos de atenção',
  'PERCLOS máximo (%)',
  'Piscadas por minuto (média)',
  'Limiar EAR (olhos)',
  'Limiar MAR (boca)',
  'Calibração pessoal',
];

/// Sessões em ordem cronológica, numeradas de 1 em diante.
List<SessionRecord> _chronological(List<SessionRecord> sessions) =>
    [...sessions]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

/// CSV com uma linha por sessão e uma linha de TOTAL no fim.
String sessionsToCsv(List<SessionRecord> sessions) {
  final list = _chronological(sessions);
  final b = StringBuffer()..writeln(_row(sessionsCsvHeader));
  var n = 0;
  for (final s in list) {
    n++;
    b.writeln(_row([
      n,
      csvDate(s.startedAt),
      csvTime(s.startedAt),
      csvTime(s.endedAt),
      csvDuration(s.duration),
      s.totalAlerts,
      s.alertsEyes,
      s.alertsYawn,
      s.alertsHead,
      s.alertsFace,
      s.attentionCount,
      csvNum(s.maxPerclos * 100, 1),
      csvNum(s.avgBlinkRate, 1),
      csvNum(s.earThreshold, 3),
      csvNum(s.marThreshold, 3),
      s.calibrated ? 'Sim' : 'Não',
    ]));
  }
  if (list.isNotEmpty) {
    int sum(int Function(SessionRecord) f) => list.fold(0, (a, s) => a + f(s));
    final total = list.fold(Duration.zero, (a, s) => a + s.duration);
    final maxPerclos = list.map((s) => s.maxPerclos).reduce((a, b) => a > b ? a : b);
    final blink = list.fold(0.0, (a, s) => a + s.avgBlinkRate) / list.length;
    b.writeln(_row([
      'TOTAL',
      '${list.length} ${list.length == 1 ? 'sessão' : 'sessões'}',
      '',
      '',
      csvDuration(total),
      sum((s) => s.totalAlerts),
      sum((s) => s.alertsEyes),
      sum((s) => s.alertsYawn),
      sum((s) => s.alertsHead),
      sum((s) => s.alertsFace),
      sum((s) => s.attentionCount),
      csvNum(maxPerclos * 100, 1),
      csvNum(blink, 1),
      '',
      '',
      '',
    ]));
  }
  return b.toString();
}

const eventsCsvHeader = [
  'Sessão',
  'Data',
  'Horário',
  'Tempo na sessão',
  'Tipo',
  'EAR (olhos)',
  'MAR (boca)',
  'PERCLOS (%)',
];

/// CSV com uma linha por evento (alerta/atenção), na ordem em que aconteceram.
/// Com [sessions], mostra o número da sessão (o mesmo do outro arquivo) e o
/// tempo decorrido desde o início dela.
String eventsToCsv(List<SessionEvent> events, {List<SessionRecord> sessions = const []}) {
  final list = _chronological(sessions);
  final number = <int, int>{};
  final start = <int, DateTime>{};
  for (var i = 0; i < list.length; i++) {
    final id = list[i].id;
    if (id != null) {
      number[id] = i + 1;
      start[id] = list[i].startedAt;
    }
  }
  final sorted = [...events]..sort((a, b) => a.time.compareTo(b.time));
  final b = StringBuffer()..writeln(_row(eventsCsvHeader));
  for (final e in sorted) {
    final sid = e.sessionId;
    final began = sid == null ? null : start[sid];
    b.writeln(_row([
      sid == null ? '' : (number[sid] ?? sid),
      csvDate(e.time),
      csvTime(e.time),
      began == null ? '' : csvDuration(e.time.difference(began)),
      eventTypeName(e.type),
      csvNum(e.ear, 3),
      csvNum(e.mar, 3),
      csvNum(e.perclos * 100, 1),
    ]));
  }
  return b.toString();
}
