import 'models.dart';

String _num(double v, [int digits = 4]) => v.toStringAsFixed(digits);

/// CSV (separador `;`, padrão do Excel em português) com uma linha por sessão.
String sessionsToCsv(List<SessionRecord> sessions) {
  final b = StringBuffer(
      'id;inicio;fim;duracao_s;alertas_olhos;alertas_bocejo;alertas_cabeca;alertas_rosto_ausente;avisos_atencao;perclos_max;'
      'piscadas_por_min_media;limiar_ear;limiar_mar;calibrado\n');
  for (final s in sessions) {
    b.writeln([
      s.id ?? '',
      s.startedAt.toIso8601String(),
      s.endedAt.toIso8601String(),
      _num(s.duration.inMilliseconds / 1000, 1),
      s.alertsEyes,
      s.alertsYawn,
      s.alertsHead,
      s.alertsFace,
      s.attentionCount,
      _num(s.maxPerclos),
      _num(s.avgBlinkRate, 1),
      _num(s.earThreshold, 3),
      _num(s.marThreshold, 3),
      s.calibrated ? 1 : 0,
    ].join(';'));
  }
  return b.toString();
}

/// CSV com uma linha por evento (alerta/atenção).
String eventsToCsv(List<SessionEvent> events) {
  final b = StringBuffer('id;sessao_id;horario;tipo;ear;mar;perclos\n');
  for (final e in events) {
    b.writeln([e.id ?? '', e.sessionId ?? '', e.time.toIso8601String(), e.type.code, _num(e.ear),
        _num(e.mar), _num(e.perclos)].join(';'));
  }
  return b.toString();
}
