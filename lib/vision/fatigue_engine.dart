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

/// Probabilidade de sorriso (classificador do ML Kit) a partir da qual o rosto
/// é tratado como sorriso — pega também o sorriso de boca fechada, em que o MAR
/// quase não muda mas os olhos ficam semicerrados.
const double smileProbabilityThreshold = 0.6;

/// Modo de reforço (olhos pouco visíveis, ex.: celular muito abaixo do rosto).
/// Os olhos são considerados pouco visíveis quando, na calibração, o EAR com os
/// olhos fechados fica a menos de 35% de distância do EAR com os olhos abertos
/// (de frente, a diferença costuma ser bem maior: ~0,3 aberto contra ~0,1 fechado).
const double eyeSeparationMin = 0.35;

/// A probabilidade de olho aberto do ML Kit só substitui o EAR se separar bem
/// aberto de fechado na calibração (diferença mínima entre as medianas).
const double eyeProbSeparationMin = 0.4;

/// Limiar da probabilidade: a 40% do caminho entre "fechado" e "aberto".
const double eyeProbMargin = 0.4;

/// No reforço, a cabeça fica mais sensível: 75% do ângulo e 80% do tempo.
const double reinforcedHeadAngleFactor = 0.75;
const double reinforcedHeadTimeFactor = 0.8;

/// Ângulo do rosto em relação à câmera a partir do qual o app avisa que o
/// celular está mal posicionado (muito abaixo/acima ou muito de lado).
const double cameraPitchWarnDeg = 25;
const double cameraYawWarnDeg = 30;

/// Cabeça caindo: queda (graus) em relação à posição normal e tempo para alertar.
const double headDropDefaultDeg = 20;
const double headTiltDeg = 30;
const int headAlertDefaultMs = 1500;

/// Rosto fora da câmera: tempo para alertar.
const int faceLostAlertDefaultMs = 4000;

/// Alerta progressivo: após este tempo em alerta, o aviso fica mais intenso.
const int escalateAfterMs = 4000;

/// Amostras coletadas em cada etapa da calibração.
const int samplesPerStep = 60;

/// Ajustes do usuário (tela de Configurações). Os valores padrão são os
/// validados no protótipo.
class DetectionSettings {
  /// Tempo contínuo de olhos fechados para o ALERTA.
  int eyesAlertMs = closedFatigueMs;

  /// Tempo contínuo de boca aberta para considerar bocejo (ALERTA).
  int yawnAlertMs = yawnMinMs;

  /// Checagem cruzada EAR × MAR: ignora olhos semicerrados ao sorrir/falar.
  bool smileFilter = true;

  /// Piscadas por minuto a partir das quais aparece ATENÇÃO.
  int blinkWarnRate = warnBlinkRate;

  /// Detecta a cabeça caindo (cochilo) pela inclinação do rosto.
  bool headEnabled = true;

  /// Quantos graus a cabeça precisa baixar em relação à posição normal.
  double headDropDeg = headDropDefaultDeg;

  /// Tempo com a cabeça caída para o ALERTA.
  int headAlertMs = headAlertDefaultMs;

  /// Avisa quando o rosto sai da câmera.
  bool faceLostEnabled = true;

  /// Tempo sem rosto na câmera para o ALERTA.
  int faceLostAlertMs = faceLostAlertDefaultMs;

  /// Alerta em tela cheia (piscando) no painel ao vivo.
  bool fullScreenAlert = true;

  /// Alerta progressivo: som e vibração ficam mais intensos se o alerta continuar.
  bool escalatingAlert = true;

  /// Permite usar o celular deitado (paisagem), ex.: no suporte do carro.
  bool allowLandscape = false;

  /// Calibração avança sozinha (com "plim" e vibração) ao concluir cada etapa.
  bool autoAdvanceCalibration = true;

  /// Usa sempre o modo de reforço (cabeça mais sensível e probabilidade de olho
  /// aberto), mesmo quando a calibração não indicou olhos pouco visíveis.
  bool forceReinforced = false;

  /// ATENÇÃO aparece um pouco antes do alerta (mesma proporção do protótipo).
  int get eyesWarnMs => (eyesAlertMs * warnClosedMs / closedFatigueMs).round();
  int get mouthWarnMs => (yawnAlertMs * warnMouthMs / yawnMinMs).round();
  int get headWarnMs => (headAlertMs * 0.5).round();
  int get faceLostWarnMs => (faceLostAlertMs * 0.5).round();

  void reset() {
    eyesAlertMs = closedFatigueMs;
    yawnAlertMs = yawnMinMs;
    smileFilter = true;
    blinkWarnRate = warnBlinkRate;
    headEnabled = true;
    headDropDeg = headDropDefaultDeg;
    headAlertMs = headAlertDefaultMs;
    faceLostEnabled = true;
    faceLostAlertMs = faceLostAlertDefaultMs;
    fullScreenAlert = true;
    escalatingAlert = true;
    allowLandscape = false;
    autoAdvanceCalibration = true;
    forceReinforced = false;
  }
}

String formatSeconds(int ms) => (ms / 1000).toStringAsFixed(1).replaceAll('.', ',');

enum AlertReason { none, eyes, yawn, head, faceLost }

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
    this.headPitch = 0,
    this.headRoll = 0,
    this.headDownMs = 0,
    this.faceMissingMs = 0,
    this.alertSinceMs = 0,
    this.reinforced = false,
    this.eyeProb,
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

  /// Inclinação da cabeça (graus) em relação à posição normal: positivo = para baixo.
  final double headPitch;

  /// Inclinação lateral da cabeça (graus) em relação à posição normal.
  final double headRoll;

  /// Tempo contínuo com a cabeça caída.
  final int headDownMs;

  /// Tempo sem rosto na câmera.
  final int faceMissingMs;

  /// Há quanto tempo o alerta atual está ativo (para o alerta progressivo).
  final int alertSinceMs;

  /// Modo de reforço ativo (olhos pouco visíveis: cabeça mais sensível e
  /// probabilidade de olho aberto do ML Kit no lugar do EAR, quando confiável).
  final bool reinforced;

  /// Probabilidade de olho aberto informada pelo ML Kit (média dos dois olhos).
  final double? eyeProb;

  bool get faceVisible => faceMissingMs == 0;

  static const empty = FatigueMetrics();

  /// Classificação em 3 níveis + mensagem para o usuário.
  ({FatigueStatus status, String notice}) classify([DetectionSettings? settings]) {
    final cfg = settings ?? DetectionSettings();
    if (alert) {
      return (
        status: FatigueStatus.alert,
        notice: switch (alertReason) {
          AlertReason.yawn => 'ALERTA: bocejo sustentado detectado',
          AlertReason.head => 'ALERTA: cabeça caindo • possível cochilo',
          AlertReason.faceLost => 'ALERTA: rosto fora da câmera há mais de ${formatSeconds(cfg.faceLostAlertMs)} s',
          _ => 'ALERTA: olhos fechados por mais de ${formatSeconds(cfg.eyesAlertMs)} s',
        },
      );
    }
    final faceWarn = cfg.faceLostEnabled && faceMissingMs >= cfg.faceLostWarnMs;
    final headWarnMs = reinforced ? (cfg.headWarnMs * reinforcedHeadTimeFactor).round() : cfg.headWarnMs;
    final headWarn = cfg.headEnabled && headDownMs >= headWarnMs;
    final eyesWarn = closedMs >= cfg.eyesWarnMs && !expression;
    final mouthWarn = mouthOpenMs >= cfg.mouthWarnMs;
    final blinkWarn = blinkRate >= cfg.blinkWarnRate;
    if (faceWarn || headWarn || eyesWarn || mouthWarn || blinkWarn) {
      return (
        status: FatigueStatus.attention,
        notice: faceWarn
            ? 'Rosto não detectado • olhe para a frente'
            : headWarn
                ? 'Cabeça inclinada • mantenha a postura'
                : eyesWarn
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

  /// Posição normal da cabeça (graus) medida na etapa "olhos abertos".
  double? headPitch;
  double? headRoll;

  /// A calibração mostrou olhos pouco visíveis (EAR aberto e fechado parecidos),
  /// por exemplo com o celular muito abaixo do rosto. Liga o modo de reforço.
  bool lowEyeConfidence = false;

  /// Separação relativa entre EAR aberto e fechado medida na calibração (0 a 1).
  double? eyeSeparation;

  /// Limiar da probabilidade de olho aberto (ML Kit), usado no modo de reforço
  /// quando ela separa melhor aberto de fechado. `null` = usar só o EAR.
  double? eyeProbThreshold;

  double? _openEar;
  double? _closedEar;
  double? _yawnMar;
  double? _openProb;

  void reset() {
    ear = earDefault;
    mar = marDefault;
    marNeutral = marNeutralDefault;
    calibrated = false;
    headPitch = headRoll = null;
    lowEyeConfidence = false;
    eyeSeparation = null;
    eyeProbThreshold = null;
    _openEar = _closedEar = _yawnMar = _openProb = null;
  }

  /// Restaura limiares salvos anteriormente.
  void restore({
    required double ear,
    required double mar,
    required double marNeutral,
    double? headPitch,
    double? headRoll,
    bool lowEyeConfidence = false,
    double? eyeSeparation,
    double? eyeProbThreshold,
  }) {
    reset();
    this.ear = ear;
    this.mar = mar;
    this.marNeutral = marNeutral;
    this.headPitch = headPitch;
    this.headRoll = headRoll;
    this.lowEyeConfidence = lowEyeConfidence;
    this.eyeSeparation = eyeSeparation;
    this.eyeProbThreshold = eyeProbThreshold;
    calibrated = true;
  }

  /// Aplica o resultado (medianas) de uma etapa de calibração.
  /// 0 = olhos abertos, 1 = olhos fechados, 2 = bocejo, 3 = sorriso (opcional).
  /// [medianProb] = mediana da probabilidade de olho aberto do ML Kit (se houver).
  void applyCalibration(int step, double medianEar, double medianMar, {double? medianProb}) {
    calibrated = true;
    switch (step) {
      case 0:
        _openEar = medianEar;
        _openProb = medianProb;
      case 1:
        _closedEar = medianEar;
        // Limiar a 28% do caminho entre "fechado" e "aberto" (margem de segurança
        // para que semicerrar os olhos ao rir não gere alerta).
        final open = _openEar;
        if (open != null) {
          ear = clampD(medianEar + earMargin * (open - medianEar), earMin, earMax);
          // Qualidade dos olhos nesta posição: quão diferentes ficaram aberto e fechado.
          final sep = open > 0 ? (open - medianEar) / open : 0.0;
          eyeSeparation = clampD(sep, 0, 1);
          lowEyeConfidence = sep < eyeSeparationMin;
        }
        // Probabilidade do ML Kit: só é usada se separar bem aberto de fechado.
        final openP = _openProb;
        if (openP != null && medianProb != null && openP - medianProb >= eyeProbSeparationMin) {
          eyeProbThreshold = medianProb + eyeProbMargin * (openP - medianProb);
        } else {
          eyeProbThreshold = null;
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
  final List<double> _pitches = [];
  final List<double> _rolls = [];
  final List<double> _probs = [];

  void reset() {
    _ears.clear();
    _mars.clear();
    _pitches.clear();
    _rolls.clear();
    _probs.clear();
  }

  bool get done => _ears.length >= samplesPerStep;
  int get progress => ((_ears.length / samplesPerStep) * 100).round().clamp(0, 100);
  double get medianEar => median(_ears);
  double get medianMar => median(_mars);
  double? get medianPitch => _pitches.isEmpty ? null : median(_pitches);
  double? get medianRoll => _rolls.isEmpty ? null : median(_rolls);
  double? get medianProb => _probs.isEmpty ? null : median(_probs);

  /// Retorna `true` quando a etapa acabou de ser concluída neste quadro.
  bool add(double ear, double mar, {double? pitch, double? roll, double? eyeProb}) {
    if (done) return false;
    _ears.add(ear);
    _mars.add(mar);
    if (eyeProb != null) _probs.add(eyeProb);
    if (pitch != null && roll != null) {
      _pitches.add(pitch);
      _rolls.add(roll);
    }
    return done;
  }
}

/// Máquina de estados temporal: piscadas × fechamento prolongado, bocejo
/// sustentado, PERCLOS, checagem cruzada EAR×MAR e histerese.
class FatigueEngine {
  FatigueEngine(this.thresholds, [DetectionSettings? settings]) : settings = settings ?? DetectionSettings();

  final Thresholds thresholds;
  final DetectionSettings settings;
  final _earAvg = MovingAverage(smoothWindow);
  final _marAvg = MovingAverage(smoothWindow);
  final _perclos = PerclosWindow(60000);
  final List<int> _blinks = [];

  int _closedSince = 0, _closedLastSeen = 0;
  int _mouthSince = 0, _mouthLastSeen = 0;
  int _headSince = 0, _headLastSeen = 0;
  int _lastFaceSeen = 0;
  bool _alert = false;
  int _alertSince = 0;
  AlertReason _reason = AlertReason.none;
  int _normalSince = 0;

  /// Posição normal da cabeça (graus). Vem da calibração (olhos abertos) e se
  /// ajusta devagar enquanto o motorista está atento.
  double? basePitch;
  double? baseRoll;

  double _lastEar = 0, _lastMar = 0, _lastPerclos = 0;

  void reset() {
    _earAvg.reset();
    _marAvg.reset();
    _perclos.reset();
    _blinks.clear();
    _closedSince = _closedLastSeen = _mouthSince = _mouthLastSeen = _normalSince = 0;
    _headSince = _headLastSeen = _lastFaceSeen = _alertSince = 0;
    _alert = false;
    _reason = AlertReason.none;
  }

  /// Define a posição normal da cabeça (ex.: mediana da etapa "olhos abertos").
  void setHeadBaseline(double pitch, double roll) {
    basePitch = pitch;
    baseRoll = roll;
  }

  void _raise(AlertReason reason, int now) {
    if (!_alert) _alertSince = now;
    _alert = true;
    _reason = reason;
    _normalSince = 0;
  }

  /// Quadro sem rosto detectado. Mantém os últimos valores e conta o tempo
  /// fora da câmera (só depois de o rosto ter aparecido ao menos uma vez).
  FatigueMetrics noFace(int now) {
    // Sem rosto não há olhos/boca/cabeça para medir: zera os cronômetros.
    _closedSince = _mouthSince = _headSince = 0;
    _normalSince = 0;
    final missing = _lastFaceSeen == 0 ? 0 : now - _lastFaceSeen;
    if (settings.faceLostEnabled && missing >= settings.faceLostAlertMs) _raise(AlertReason.faceLost, now);
    return FatigueMetrics(
      ear: _lastEar,
      mar: _lastMar,
      perclos: _lastPerclos,
      blinkRate: _blinks.length,
      faceMissingMs: missing,
      alert: _alert,
      alertReason: _reason,
      alertSinceMs: _alert ? now - _alertSince : 0,
      reinforced: reinforced,
    );
  }

  /// Suaviza os valores brutos. Retorna (ear, mar) suavizados.
  ({double ear, double mar}) smooth(double rawEar, double rawMar) =>
      (ear: _earAvg.push(rawEar), mar: _marAvg.push(rawMar));

  /// Modo de reforço: calibração indicou olhos pouco visíveis, ou o usuário pediu.
  bool get reinforced => thresholds.lowEyeConfidence || settings.forceReinforced;

  /// Ângulo de queda da cabeça para alertar (menor no modo de reforço).
  double get effectiveHeadDropDeg =>
      reinforced ? settings.headDropDeg * reinforcedHeadAngleFactor : settings.headDropDeg;

  /// Tempo com a cabeça caída para alertar (menor no modo de reforço).
  int get effectiveHeadAlertMs =>
      reinforced ? (settings.headAlertMs * reinforcedHeadTimeFactor).round() : settings.headAlertMs;

  /// Processa um quadro já suavizado. [now] em ms (monotônico, > 0).
  /// [pitch] e [roll] são os ângulos da cabeça informados pelo detector
  /// (pitch positivo = olhando para cima); [smile] e [eyeProb] são as
  /// probabilidades de sorriso e de olho aberto do ML Kit.
  FatigueMetrics process(double ear, double mar, int now,
      {double? pitch, double? roll, double? smile, double? eyeProb}) {
    final t = thresholds;
    final boost = reinforced;
    _lastFaceSeen = now;
    _lastEar = ear;
    _lastMar = mar;

    // Checagem cruzada: MAR elevado indica sorriso/fala — não conta como olho fechado.
    final expression = settings.smileFilter &&
        (mar >= t.marNeutral || (smile ?? 0) >= smileProbabilityThreshold);
    // Olho fechado: pelo EAR; no reforço, pela probabilidade do ML Kit quando ela
    // separou bem aberto de fechado na calibração (depende menos do ângulo).
    final probTh = t.eyeProbThreshold;
    final useProb = boost && probTh != null && eyeProb != null;
    final eyesClosedRaw = useProb ? eyeProb < probTh : ear < t.ear;
    final eyesClosed = eyesClosedRaw && !expression;
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
    final yawning = mouthOpenMs >= settings.yawnAlertMs;

    // PERCLOS ignora piscadas: só conta fechamentos acima de 0,4 s.
    final perclos = _perclos.add(now, closedMs > blinkMaxMs);
    _lastPerclos = perclos;

    // Cabeça caindo: queda do pitch (ou inclinação lateral forte) em relação à posição normal.
    var headDrop = 0.0, headTilt = 0.0, headDown = false;
    if (pitch != null && roll != null) {
      basePitch ??= pitch;
      baseRoll ??= roll;
      headDrop = basePitch! - pitch;
      headTilt = roll - baseRoll!;
      headDown = settings.headEnabled && (headDrop >= effectiveHeadDropDeg || headTilt.abs() >= headTiltDeg);
      if (headDown) {
        if (_headSince == 0) _headSince = now;
        _headLastSeen = now;
      } else if (now - _headLastSeen > gapToleranceMs) {
        _headSince = 0;
        // Postura normal e olhos abertos: a referência acompanha devagar a posição do motorista.
        if (!_alert && closedMs == 0 && headDrop.abs() < effectiveHeadDropDeg / 2) {
          basePitch = basePitch! + 0.02 * (pitch - basePitch!);
          baseRoll = baseRoll! + 0.02 * (roll - baseRoll!);
        }
      }
    }
    final headDownMs = _headSince != 0 ? now - _headSince : 0;
    final headAlert = settings.headEnabled && headDownMs >= effectiveHeadAlertMs;

    final drowsy = closedMs >= settings.eyesAlertMs;
    if (drowsy || yawning || headAlert) {
      _raise(drowsy ? AlertReason.eyes : headAlert ? AlertReason.head : AlertReason.yawn, now);
    } else if (_alert) {
      final stable = !eyesClosedRaw && mar < t.mar && !headDown;
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
      headPitch: headDrop,
      headRoll: headTilt,
      headDownMs: headDownMs,
      alertSinceMs: _alert ? now - _alertSince : 0,
      reinforced: boost,
      eyeProb: eyeProb,
    );
  }
}
