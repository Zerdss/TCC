import 'dart:math' as math;

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

// ---------------------------------------------------------------------------
// Posição do celular em relação ao rosto
// ---------------------------------------------------------------------------

/// A partir deste ângulo (graus) o celular conta como abaixo/acima do rosto.
const double phoneTiltDeg = 12;

/// A partir deste giro (graus) o celular conta como de lado.
const double phoneSideDeg = 15;

/// Posição em que o reforço liga sozinho, mesmo que a calibração dos olhos
/// tenha dado boa separação (bem abaixo/acima ou bem de lado).
const double phoneReinforcePitchDeg = cameraPitchWarnDeg;
const double phoneReinforceYawDeg = cameraYawWarnDeg;

enum PhoneVertical { below, level, above }

/// Onde o celular está em relação ao rosto. Medido pelo ângulo do rosto na
/// etapa "olhos abertos" da calibração, com o motorista olhando para a estrada:
/// se o rosto aparece "olhando para cima" na câmera, o celular está abaixo.
class PhonePosition {
  const PhonePosition(this.pitch, this.yaw);

  /// Ângulos do rosto em relação à câmera (graus, ML Kit). Pitch > 0 = celular abaixo.
  final double pitch;
  final double yaw;

  static PhonePosition? fromAngles(double? pitch, double? yaw) =>
      pitch == null ? null : PhonePosition(pitch, yaw ?? 0);

  PhoneVertical get vertical => pitch >= phoneTiltDeg
      ? PhoneVertical.below
      : pitch <= -phoneTiltDeg
          ? PhoneVertical.above
          : PhoneVertical.level;

  bool get side => yaw.abs() >= phoneSideDeg;

  /// Muito abaixo/acima ou muito de lado: olhos pouco confiáveis → reforço.
  bool get needsReinforcement =>
      pitch.abs() >= phoneReinforcePitchDeg || yaw.abs() >= phoneReinforceYawDeg;

  bool get isFront => vertical == PhoneVertical.level && !side;

  /// Nome curto da posição ("De frente", "Abaixo do rosto", "Abaixo e de lado"...).
  String get label {
    final strong = pitch.abs() >= phoneReinforcePitchDeg;
    final v = switch (vertical) {
      PhoneVertical.below => strong ? 'Bem abaixo do rosto' : 'Abaixo do rosto',
      PhoneVertical.above => strong ? 'Bem acima do rosto' : 'Acima do rosto',
      PhoneVertical.level => null,
    };
    if (v == null) return side ? 'De lado' : 'De frente (reto)';
    return side ? '$v e de lado' : v;
  }

  /// O que muda na detecção nesta posição.
  String get detail {
    if (isFront) return 'Melhor posição: olhos, boca e cabeça medidos normalmente.';
    final parts = <String>[
      if (vertical == PhoneVertical.below) 'visto de baixo, o olho parece mais achatado',
      if (vertical == PhoneVertical.above) 'visto de cima, as pálpebras parecem mais baixas',
      if (side) 'de lado, um olho aparece menor que o outro',
    ];
    final what = parts.join('; ');
    return needsReinforcement
        ? '${what[0].toUpperCase()}${what.substring(1)}. Reforço ligado: a cabeça fica mais '
            'sensível e a boca segue igual. Os limites usam a sua calibração nesta posição.'
        : '${what[0].toUpperCase()}${what.substring(1)}. Os limites usam a sua calibração nesta '
            'posição, então a detecção funciona normalmente.';
  }
}

// ---------------------------------------------------------------------------
// Movimentos normais × sonolência (evita alarme falso ao olhar para baixo, para
// o lado ou ao se mexer). Valores iniciais: ajustar com testes reais.
// ---------------------------------------------------------------------------

/// Rosto virado para o lado (giro em relação à posição normal): os olhos ficam
/// distorcidos na imagem e não são avaliados.
const double lookAwayYawDeg = 25;

/// Cabeça abaixada a partir deste ângulo: as pálpebras descem ao olhar para
/// baixo, então o olho fechado passa a exigir mais certeza.
const double lookDownDeg = 12;

/// Olhar fora da estrada (para baixo ou para o lado) por mais que isto → ATENÇÃO
/// (aviso silencioso, nunca o alarme de sonolência).
const int lookAwayWarnMs = 2500;

/// Movimento brusco da cabeça (graus por segundo): a medição pausa um instante.
const double motionSpeedDegPerS = 120;

/// Janela para medir a velocidade da cabeça (evita confundir tremor com movimento).
const int motionWindowMs = 150;
const int motionHoldMs = 300;

/// Olho "claramente aberto": probabilidade do ML Kit ≥ 0,6 ou EAR 15% acima do limite.
const double eyesOpenProb = 0.6;
const double eyesOpenEarFactor = 1.15;

/// Com a cabeça abaixada, o olho só conta como fechado com EAR 15% abaixo do
/// limite (e probabilidade < 0,5, quando houver).
const double lookDownEarFactor = 0.85;
const double lookDownClosedProb = 0.5;

/// Cabeça caída com olhos fechados em pelo menos 30% do tempo → alerta no tempo
/// normal; com olhos indefinidos → alerta só no dobro do tempo; com olhos abertos
/// na maior parte do tempo → é "olhando para baixo" e não alerta.
const double headClosedShare = 0.3;
const double headOpenShare = 0.5;

/// Cabeça caindo: queda (graus) em relação à posição normal e tempo para alertar.
const double headDropDefaultDeg = 20;
const double headTiltDeg = 30;
const int headAlertDefaultMs = 1500;

/// Rosto fora da câmera: tempo para alertar.
const int faceLostAlertDefaultMs = 4000;

/// Alerta progressivo: após este tempo em alerta, o aviso fica mais intenso.
const int escalateAfterMs = 4000;

/// Amostras VÁLIDAS (rosto enquadrado, parado e na posição certa) em cada
/// etapa da calibração. A ~20 FPS, cerca de 4 s de leitura boa.
const int samplesPerStep = 80;

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

  /// Ao sair do app durante o monitoramento, continua numa janela flutuante
  /// (Android), para usar junto com o GPS.
  bool floatingWindow = true;

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
    floatingWindow = true;
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
    this.lookingDown = false,
    this.lookingSide = false,
    this.moving = false,
    this.lookAwayMs = 0,
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

  /// Cabeça baixa com os olhos abertos: olhando para baixo (não é sonolência).
  final bool lookingDown;

  /// Rosto virado para o lado: olhando para o lado (não é sonolência).
  final bool lookingSide;

  /// Movimento brusco da cabeça: medição pausada por um instante.
  final bool moving;

  /// Há quanto tempo o motorista olha para baixo ou para o lado.
  final int lookAwayMs;

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
    final lookWarn = lookAwayMs >= lookAwayWarnMs;
    if (lookWarn && !headWarn && !eyesWarn) {
      return (
        status: FatigueStatus.attention,
        notice: lookingSide
            ? 'Olhando para o lado • volte a atenção à estrada'
            : 'Olhando para baixo • volte a atenção à estrada',
      );
    }
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
  double? headYaw;

  /// A calibração mostrou olhos pouco visíveis (EAR aberto e fechado parecidos),
  /// por exemplo com o celular muito abaixo do rosto. Liga o modo de reforço.
  bool lowEyeConfidence = false;

  /// Separação relativa entre EAR aberto e fechado medida na calibração (0 a 1).
  double? eyeSeparation;

  /// Limiar da probabilidade de olho aberto (ML Kit), usado no modo de reforço
  /// quando ela separa melhor aberto de fechado. `null` = usar só o EAR.
  double? eyeProbThreshold;

  /// Posição do celular medida na calibração (`null` = ainda não calibrado).
  PhonePosition? get phonePosition => PhonePosition.fromAngles(headPitch, headYaw);

  double? _openEar;
  double? _openMar;
  double? _closedEar;
  double? _yawnMar;
  double? _openProb;
  double? _closedProb;

  /// Medidas pessoais registradas na calibração (para a análise do rosto).
  double? get openEar => _openEar;
  double? get openMar => _openMar;
  double? get closedEar => _closedEar;
  double? get yawnMar => _yawnMar;
  double? get openProb => _openProb;
  double? get closedProb => _closedProb;

  /// Copia todos os valores (inclusive as medidas internas) de [o].
  void copyFrom(Thresholds o) {
    ear = o.ear;
    mar = o.mar;
    marNeutral = o.marNeutral;
    calibrated = o.calibrated;
    headPitch = o.headPitch;
    headRoll = o.headRoll;
    headYaw = o.headYaw;
    lowEyeConfidence = o.lowEyeConfidence;
    eyeSeparation = o.eyeSeparation;
    eyeProbThreshold = o.eyeProbThreshold;
    _openEar = o._openEar;
    _openMar = o._openMar;
    _closedEar = o._closedEar;
    _yawnMar = o._yawnMar;
    _openProb = o._openProb;
    _closedProb = o._closedProb;
  }

  void reset() {
    ear = earDefault;
    mar = marDefault;
    marNeutral = marNeutralDefault;
    calibrated = false;
    headPitch = headRoll = headYaw = null;
    lowEyeConfidence = false;
    eyeSeparation = null;
    eyeProbThreshold = null;
    _openEar = _openMar = _closedEar = _yawnMar = _openProb = _closedProb = null;
  }

  /// Restaura limiares salvos anteriormente.
  void restore({
    required double ear,
    required double mar,
    required double marNeutral,
    double? headPitch,
    double? headRoll,
    double? headYaw,
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
    this.headYaw = headYaw;
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
        _openMar = medianMar;
        _openProb = medianProb;
      case 1:
        _closedEar = medianEar;
        _closedProb = medianProb;
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
  double? baseYaw;

  // Movimento e olhar fora da estrada.
  int _lastPoseTime = 0;
  double? _lastPitchSample, _lastYawSample;
  int _motionUntil = 0;
  int _lookAwaySince = 0;
  int _lastFrameTime = 0;
  // Tempo, durante a cabeça caída atual, com olhos fechados / claramente abertos.
  int _hdClosedMs = 0, _hdOpenMs = 0, _hdTotalMs = 0;

  double _lastEar = 0, _lastMar = 0, _lastPerclos = 0;

  void reset() {
    _earAvg.reset();
    _marAvg.reset();
    _perclos.reset();
    _blinks.clear();
    _closedSince = _closedLastSeen = _mouthSince = _mouthLastSeen = _normalSince = 0;
    _headSince = _headLastSeen = _lastFaceSeen = _alertSince = 0;
    _lastPoseTime = _motionUntil = _lookAwaySince = _lastFrameTime = 0;
    _lastPitchSample = _lastYawSample = null;
    _hdClosedMs = _hdOpenMs = _hdTotalMs = 0;
    _alert = false;
    _reason = AlertReason.none;
  }

  /// Define a posição normal da cabeça (ex.: mediana da etapa "olhos abertos").
  void setHeadBaseline(double pitch, double roll, [double? yaw]) {
    basePitch = pitch;
    baseRoll = roll;
    if (yaw != null) baseYaw = yaw;
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
    _lookAwaySince = 0;
    _hdClosedMs = _hdOpenMs = _hdTotalMs = 0;
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

  /// Modo de reforço: calibração indicou olhos pouco visíveis, o celular está
  /// muito abaixo/acima/de lado, ou o usuário pediu.
  bool get reinforced =>
      thresholds.lowEyeConfidence ||
      settings.forceReinforced ||
      (thresholds.phonePosition?.needsReinforcement ?? false);

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
      {double? pitch, double? roll, double? yaw, double? smile, double? eyeProb}) {
    final t = thresholds;
    final boost = reinforced;
    final dt = _lastFrameTime == 0 ? 0 : math.min(now - _lastFrameTime, 200);
    _lastFrameTime = now;
    _lastFaceSeen = now;
    _lastEar = ear;
    _lastMar = mar;

    // ---- posição e movimento da cabeça
    var headDrop = 0.0, headTilt = 0.0, yawDelta = 0.0;
    if (pitch != null && roll != null) {
      basePitch ??= pitch;
      baseRoll ??= roll;
      headDrop = basePitch! - pitch;
      headTilt = roll - baseRoll!;
    }
    if (yaw != null) {
      baseYaw ??= yaw;
      yawDelta = yaw - baseYaw!;
    }
    // Movimento brusco: a imagem e os pontos do rosto ficam instáveis por um instante.
    if (pitch != null && yaw != null) {
      final lp = _lastPitchSample, ly = _lastYawSample;
      // Compara com uma amostra de pelo menos 150 ms atrás: entre quadros
      // seguidos o tremor normal do detector (1–2°) pareceria movimento rápido.
      final dt = now - _lastPoseTime;
      if (lp == null || ly == null || dt >= motionWindowMs) {
        if (lp != null && ly != null && dt <= 4 * motionWindowMs) {
          final speed = ((pitch - lp).abs() + (yaw - ly).abs()) * 1000 / dt;
          if (speed >= motionSpeedDegPerS) _motionUntil = now + motionHoldMs;
        }
        _lastPitchSample = pitch;
        _lastYawSample = yaw;
        _lastPoseTime = now;
      }
    }
    final moving = now < _motionUntil;
    final lookingSide = yawDelta.abs() >= lookAwayYawDeg;
    final headLowered = headDrop >= lookDownDeg;

    // ---- olhos
    // Checagem cruzada: MAR elevado indica sorriso/fala — não conta como olho fechado.
    final expression = settings.smileFilter &&
        (mar >= t.marNeutral || (smile ?? 0) >= smileProbabilityThreshold);
    // De lado ou em movimento, os olhos não são avaliados (contorno distorcido/instável).
    final measurable = !moving && !lookingSide;
    final probTh = t.eyeProbThreshold;
    final useProb = boost && probTh != null && eyeProb != null;
    bool eyesClosedRaw;
    if (!measurable) {
      eyesClosedRaw = false;
    } else if (useProb) {
      // Reforço: probabilidade do ML Kit (mais exigente com a cabeça abaixada).
      eyesClosedRaw = eyeProb < (headLowered ? probTh * 0.6 : probTh);
    } else if (headLowered) {
      // Olhando para baixo as pálpebras descem: exige EAR bem baixo e, se houver,
      // a confirmação da probabilidade do ML Kit.
      eyesClosedRaw = ear < t.ear * lookDownEarFactor && (eyeProb == null || eyeProb < lookDownClosedProb);
    } else {
      eyesClosedRaw = ear < t.ear;
    }
    final eyesOpenClear = measurable &&
        !eyesClosedRaw &&
        ((eyeProb != null && eyeProb >= eyesOpenProb) || ear >= t.ear * eyesOpenEarFactor);
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

    // ---- boca
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

    // ---- cabeça caindo: queda do pitch (ou inclinação lateral forte), conferida com os olhos
    var headDown = false;
    if (pitch != null && roll != null) {
      headDown = settings.headEnabled && (headDrop >= effectiveHeadDropDeg || headTilt.abs() >= headTiltDeg);
      if (headDown) {
        if (_headSince == 0) {
          _headSince = now;
          _hdClosedMs = _hdOpenMs = _hdTotalMs = 0;
        }
        _headLastSeen = now;
        _hdTotalMs += dt;
        if (eyesClosedRaw) _hdClosedMs += dt;
        if (eyesOpenClear) _hdOpenMs += dt;
      } else if (now - _headLastSeen > gapToleranceMs) {
        _headSince = 0;
        // Postura normal e olhos abertos: a referência acompanha devagar a posição do motorista.
        if (!_alert && closedMs == 0 && headDrop.abs() < effectiveHeadDropDeg / 2 && !lookingSide) {
          basePitch = basePitch! + 0.02 * (pitch - basePitch!);
          baseRoll = baseRoll! + 0.02 * (roll - baseRoll!);
          if (yaw != null && baseYaw != null) baseYaw = baseYaw! + 0.02 * (yaw - baseYaw!);
        }
      }
    }
    final headDownMs = _headSince != 0 ? now - _headSince : 0;
    final total = math.max(_hdTotalMs, 1);
    final closedShare = _hdClosedMs / total, openShare = _hdOpenMs / total;
    // Cabeça baixa com os olhos abertos a maior parte do tempo = olhando para baixo.
    final lookingDown = headDown && headDownMs > 0 && openShare >= headOpenShare;
    final headAlert = settings.headEnabled &&
        !lookingDown &&
        ((headDownMs >= effectiveHeadAlertMs && closedShare >= headClosedShare) ||
            headDownMs >= 2 * effectiveHeadAlertMs);

    // ---- olhar fora da estrada (só aviso, nunca o alarme de sonolência)
    final lookingAway = lookingSide || lookingDown;
    if (lookingAway) {
      if (_lookAwaySince == 0) _lookAwaySince = now;
    } else {
      _lookAwaySince = 0;
    }
    final lookAwayMs = _lookAwaySince != 0 ? now - _lookAwaySince : 0;

    final drowsy = closedMs >= settings.eyesAlertMs;
    if (drowsy || yawning || headAlert) {
      _raise(drowsy ? AlertReason.eyes : headAlert ? AlertReason.head : AlertReason.yawn, now);
    } else if (_alert) {
      final stable = !eyesClosedRaw && mar < t.mar && (!headDown || lookingDown);
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
      alertSinceMs: _alert ? now - _alertSince : 0,
      reinforced: boost,
      eyeProb: eyeProb,
      lookingDown: lookingDown,
      lookingSide: lookingSide,
      moving: moving,
      lookAwayMs: lookAwayMs,
      headDownMs: lookingDown ? 0 : headDownMs,
    );
  }
}
