import 'metrics.dart';

// ---------------------------------------------------------------------------
// Parâmetros (herdados do primeiro protótipo, ajustados para a taxa de quadros típica
// do ML Kit em celulares, ~15–30 FPS). Todos os tempos são medidos em ms, logo
// a lógica é independente do FPS.
// ---------------------------------------------------------------------------
const double earDefault = 0.19;
const double marDefault = 0.60;
const double marNeutralDefault = 0.35;

const double earMargin = 0.28, earMin = 0.10, earMax = 0.28;
const double marMin = 0.45, marMax = 0.90;
const double marNeutralMin = 0.28, marNeutralMax = 0.50;

const int warnClosedMs = 700;
const int warnMouthMs = 1200;
const int warnBlinkRate = 26;

/// Bocejo real: boca acima do limiar de forma contínua por 1,8 s.
const int yawnMinMs = 1800;

/// Tolerância a perdas pontuais de tracking.
const int gapToleranceMs = 150;

/// Piscada saudável (0,08–0,40 s): conta como piscada, não como fadiga.
const int blinkMinMs = 80;
const int blinkMaxMs = 400;

/// Fechamento contínuo mínimo para alerta de sonolência.
const int closedFatigueMs = 1200;

/// Histerese: tempo de normalidade estável para sair do alerta.
const int recoveryMs = 1000;

/// Média móvel aplicada ao EAR/MAR (em quadros).
const int smoothWindow = 5;
const int blinkRateWindowMs = 60000;

/// Amostras coletadas em cada etapa da calibração.
const int samplesPerStep = 60;

enum AlertReason { none, eyes, yawn }

enum FatigueStatus { normal, attention, alert }

extension FatigueStatusLabel on FatigueStatus {
  String get label => switch (this) {
        FatigueStatus.normal => 'NORMAL',
        FatigueStatus.attention => 'ATENÇÃO',
        FatigueStatus.alert => 'ALERTA DE SONOLÊNCIA',
      };
}

class FatigueMetrics {
  const FatigueMetrics({
    this.ear = 0,
    this.mar = 0,
    this.perclos = 0,
    this.closedMs = 0,
    this.mouthOpenMs = 0,
    this.blinkRate = 0,
    this.expression = false,
    this.yawning = false,
    this.alert = false,
    this.alertReason = AlertReason.none,
  });

  final double ear;
  final double mar;
  final double perclos;
  final int closedMs;
  final int mouthOpenMs;
  final int blinkRate;
  final bool expression;
  final bool yawning;
  final bool alert;
  final AlertReason alertReason;

  static const empty = FatigueMetrics();

  /// Classificação em 3 níveis + mensagem para o usuário.
  ({FatigueStatus status, String notice}) classify() {
    if (alert) {
      return (
        status: FatigueStatus.alert,
        notice: alertReason == AlertReason.yawn
            ? 'ALERTA: bocejo sustentado detectado'
            : 'ALERTA: olhos fechados por mais de 1,2 segundo',
      );
    }
    final eyesWarn = closedMs >= warnClosedMs && !expression;
    final mouthWarn = mouthOpenMs >= warnMouthMs;
    final blinkWarn = blinkRate >= warnBlinkRate;
    if (eyesWarn || mouthWarn || blinkWarn) {
      return (
        status: FatigueStatus.attention,
        notice: eyesWarn
            ? 'Fechamento longo dos olhos • mantenha a atenção'
            : mouthWarn
                ? 'Boca aberta de forma sustentada • possível bocejo'
                : 'Piscadas muito frequentes • possível cansaço',
      );
    }
    return (status: FatigueStatus.normal, notice: '');
  }
}

/// Limiares ativos. Começam com valores padrão e são personalizados na calibração.
class Thresholds {
  double ear = earDefault;
  double mar = marDefault;
  double marNeutral = marNeutralDefault;

  /// `true` quando os limiares vieram de uma calibração (nova ou salva).
  bool calibrated = false;

  double? _openEar;
  double? _closedEar;
  double? _yawnMar;

  void reset() {
    ear = earDefault;
    mar = marDefault;
    marNeutral = marNeutralDefault;
    calibrated = false;
    _openEar = _closedEar = _yawnMar = null;
  }

  /// Restaura limiares salvos anteriormente.
  void restore({required double ear, required double mar, required double marNeutral}) {
    reset();
    this.ear = ear;
    this.mar = mar;
    this.marNeutral = marNeutral;
    calibrated = true;
  }

  /// Aplica o resultado (medianas) de uma etapa de calibração.
  /// 0 = olhos abertos, 1 = olhos fechados, 2 = bocejo, 3 = sorriso (opcional).
  void applyCalibration(int step, double medianEar, double medianMar) {
    calibrated = true;
    switch (step) {
      case 0:
        _openEar = medianEar;
      case 1:
        _closedEar = medianEar;
        // Limiar a 28% do caminho entre "fechado" e "aberto" (margem de segurança
        // para que semicerrar os olhos ao rir não gere alerta).
        final open = _openEar;
        if (open != null) {
          ear = clampD(medianEar + earMargin * (open - medianEar), earMin, earMax);
        }
      case 2:
        _yawnMar = medianMar;
        mar = clampD(medianMar * 0.72, marMin, marMax);
      case 3:
        final closed = _closedEar;
        final floor = closed != null ? closed + 0.04 : earMin;
        final candidate = medianEar - 0.02 < ear ? medianEar - 0.02 : ear;
        ear = clampD(candidate, floor, earMax);
        final yawn = _yawnMar;
        if (yawn != null && yawn > medianMar) {
          mar = clampD(medianMar + 0.6 * (yawn - medianMar), marMin, marMax);
        }
        marNeutral = clampD(medianMar * 0.95, marNeutralMin, marNeutralMax);
    }
  }
}

/// Coleta amostras para uma etapa de calibração.
class CalibrationSampler {
  final List<double> _ears = [];
  final List<double> _mars = [];

  void reset() {
    _ears.clear();
    _mars.clear();
  }

  bool get done => _ears.length >= samplesPerStep;
  int get progress => ((_ears.length / samplesPerStep) * 100).round().clamp(0, 100);
  double get medianEar => median(_ears);
  double get medianMar => median(_mars);

  /// Retorna `true` quando a etapa acabou de ser concluída neste quadro.
  bool add(double ear, double mar) {
    if (done) return false;
    _ears.add(ear);
    _mars.add(mar);
    return done;
  }
}

/// Máquina de estados temporal: piscadas × fechamento prolongado, bocejo
/// sustentado, PERCLOS, checagem cruzada EAR×MAR e histerese.
class FatigueEngine {
  FatigueEngine(this.thresholds);

  final Thresholds thresholds;
  final _earAvg = MovingAverage(smoothWindow);
  final _marAvg = MovingAverage(smoothWindow);
  final _perclos = PerclosWindow(60000);
  final List<int> _blinks = [];

  int _closedSince = 0, _closedLastSeen = 0;
  int _mouthSince = 0, _mouthLastSeen = 0;
  bool _alert = false;
  AlertReason _reason = AlertReason.none;
  int _normalSince = 0;

  void reset() {
    _earAvg.reset();
    _marAvg.reset();
    _perclos.reset();
    _blinks.clear();
    _closedSince = _closedLastSeen = _mouthSince = _mouthLastSeen = _normalSince = 0;
    _alert = false;
    _reason = AlertReason.none;
  }

  /// Suaviza os valores brutos. Retorna (ear, mar) suavizados.
  ({double ear, double mar}) smooth(double rawEar, double rawMar) =>
      (ear: _earAvg.push(rawEar), mar: _marAvg.push(rawMar));

  /// Processa um quadro já suavizado. [now] em ms (monotônico, > 0).
  FatigueMetrics process(double ear, double mar, int now) {
    final t = thresholds;

    // Checagem cruzada: MAR elevado indica sorriso/fala — não conta como olho fechado.
    final expression = mar >= t.marNeutral;
    final eyesClosed = ear < t.ear && !expression;
    if (eyesClosed) {
      if (_closedSince == 0) _closedSince = now;
      _closedLastSeen = now;
    } else if (now - _closedLastSeen > gapToleranceMs) {
      if (_closedSince != 0) {
        final duration = _closedLastSeen - _closedSince;
        if (duration >= blinkMinMs && duration <= blinkMaxMs) _blinks.add(_closedLastSeen);
      }
      _closedSince = 0;
    }
    final closedMs = _closedSince != 0 ? now - _closedSince : 0;
    _blinks.removeWhere((time) => now - time > blinkRateWindowMs);

    final mouthOpen = mar >= t.mar;
    if (mouthOpen) {
      if (_mouthSince == 0) _mouthSince = now;
      _mouthLastSeen = now;
    } else if (now - _mouthLastSeen > gapToleranceMs) {
      _mouthSince = 0;
    }
    final mouthOpenMs = _mouthSince != 0 ? now - _mouthSince : 0;
    final yawning = mouthOpenMs >= yawnMinMs;

    // PERCLOS ignora piscadas: só conta fechamentos acima de 0,4 s.
    final perclos = _perclos.add(now, closedMs > blinkMaxMs);

    final drowsy = closedMs >= closedFatigueMs;
    if (drowsy || yawning) {
      _alert = true;
      _reason = drowsy ? AlertReason.eyes : AlertReason.yawn;
      _normalSince = 0;
    } else if (_alert) {
      final stable = ear >= t.ear && mar < t.mar;
      if (!stable) {
        _normalSince = 0;
      } else {
        if (_normalSince == 0) _normalSince = now;
        if (now - _normalSince >= recoveryMs) {
          _alert = false;
          _reason = AlertReason.none;
          _normalSince = 0;
        }
      }
    }

    return FatigueMetrics(
      ear: ear,
      mar: mar,
      perclos: perclos,
      closedMs: closedMs,
      mouthOpenMs: mouthOpenMs,
      blinkRate: _blinks.length,
      expression: expression,
      yawning: yawning,
      alert: _alert,
      alertReason: _reason,
    );
  }
}
