import '../vision/fatigue_engine.dart';
import 'models.dart';

/// Acumula, em memória, o resumo de uma sessão de monitoramento a partir das
/// métricas de cada quadro. Não depende de banco de dados (fácil de testar).
class SessionRecorder {
  SessionRecorder({
    required this.startedAt,
    required this.earThreshold,
    required this.marThreshold,
    required this.calibrated,
  }) : _lastTime = startedAt;

  final DateTime startedAt;
  final double earThreshold;
  final double marThreshold;
  final bool calibrated;

  final List<SessionEvent> events = [];
  FatigueStatus _lastStatus = FatigueStatus.normal;
  DateTime _lastTime;
  DateTime? _lastBlinkSample;
  double _maxPerclos = 0;
  double _blinkSum = 0;
  int _blinkSamples = 0;

  /// Registra um quadro já classificado.
  void add(FatigueMetrics m, FatigueStatus status, DateTime time) {
    _lastTime = time;
    if (m.perclos > _maxPerclos) _maxPerclos = m.perclos;

    // Amostra a taxa de piscadas 1x por segundo.
    if (_lastBlinkSample == null || time.difference(_lastBlinkSample!).inMilliseconds >= 1000) {
      _lastBlinkSample = time;
      _blinkSum += m.blinkRate;
      _blinkSamples++;
    }

    // Conta apenas transições (entrada no estado), não cada quadro.
    if (status != _lastStatus) {
      if (status == FatigueStatus.alert) {
        events.add(SessionEvent(
          time: time,
          type: m.alertReason == AlertReason.yawn ? EventType.yawn : EventType.eyes,
          ear: m.ear,
          mar: m.mar,
          perclos: m.perclos,
        ));
      } else if (status == FatigueStatus.attention && _lastStatus == FatigueStatus.normal) {
        events.add(SessionEvent(time: time, type: EventType.attention, ear: m.ear, mar: m.mar, perclos: m.perclos));
      }
      _lastStatus = status;
    }
  }

  Duration get duration => _lastTime.difference(startedAt);

  SessionRecord finish([DateTime? endedAt]) => SessionRecord(
        startedAt: startedAt,
        endedAt: endedAt ?? _lastTime,
        alertsEyes: events.where((e) => e.type == EventType.eyes).length,
        alertsYawn: events.where((e) => e.type == EventType.yawn).length,
        attentionCount: events.where((e) => e.type == EventType.attention).length,
        maxPerclos: _maxPerclos,
        avgBlinkRate: _blinkSamples == 0 ? 0 : _blinkSum / _blinkSamples,
        earThreshold: earThreshold,
        marThreshold: marThreshold,
        calibrated: calibrated,
        events: List.unmodifiable(events),
      );
}
