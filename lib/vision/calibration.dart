import 'dart:math' as math;

import 'fatigue_engine.dart';
import 'metrics.dart';

// ---------------------------------------------------------------------------
// Calibração rígida: cada quadro só conta se o rosto estiver bem enquadrado,
// parado e na mesma posição; cada etapa é analisada (estabilidade, olhos
// realmente fechados, boca realmente aberta...) e repetida se não passar. A
// calibração só é confirmada depois que todas as etapas passam.
// ---------------------------------------------------------------------------

/// Velocidade máxima da cabeça (graus/s) para a amostra contar.
const double calibMaxSpeedDegPerS = 35;

/// No sorriso/risada a cabeça mexe mais: limites mais folgados.
const double calibSmileMaxSpeedDegPerS = 90;

/// A cabeça precisa ficar na mesma posição da etapa "olhos abertos" (graus).
const double calibPoseToleranceDeg = 10;
const double calibSmilePoseToleranceDeg = 20;

/// Janela para medir a velocidade da cabeça (ms).
const int calibSpeedWindowMs = 250;

/// Tempo máximo de uma etapa (ms) antes de ser reprovada.
const int calibStepTimeoutMs = 20000;

/// Variação máxima (desvio robusto / mediana) aceita em cada medida.
const double calibMaxOpenEarCv = 0.12;
const double calibMaxClosedEarCv = 0.25;
const double calibMaxClosedEarSpread = 0.02; // aceito também se o desvio absoluto for pequeno
const double calibMaxMarCv = 0.18;

/// Olho fechado tem de ficar diferente do aberto: 12% no EAR ou 0,4 na probabilidade.
const double calibMinEarSeparation = 0.12;
const double calibMinProbSeparation = 0.4;

/// Bocejo: abertura mínima para o limiar (72% do bocejo) não ficar abaixo do mínimo.
const double calibMinYawnMar = marMin / 0.72;
const double calibYawnOverNeutral = 2.0;

/// Abaixo de 75% do EAR aberto = piscada (descartada na etapa "olhos abertos").
const double calibBlinkFactor = 0.75;
const double calibMaxBlinkShare = 0.35;

/// Diferença entre os olhos a partir da qual o app avisa (15%).
const double calibAsymmetryWarn = 0.15;

/// Tentativas antes de oferecer as opções manuais.
const int calibMaxAttempts = 3;

/// Por que um quadro não entrou na calibração.
enum FrameIssue { none, framing, moving, pose, blink, eyesStillOpen, mouthNotOpen }

/// Orientação mostrada ao vivo para cada problema.
String frameIssueText(FrameIssue issue) => switch (issue) {
      FrameIssue.none => 'Leitura boa — continue assim',
      FrameIssue.framing => 'Rosto fora do quadro ideal: centralize e ajuste a distância',
      FrameIssue.moving => 'Mantenha a cabeça parada',
      FrameIssue.pose => 'Volte a cabeça para a mesma posição da 1ª etapa',
      FrameIssue.blink => 'Piscada ignorada — mantenha os olhos abertos',
      FrameIssue.eyesStillOpen => 'Os olhos ainda parecem abertos: feche-os por completo',
      FrameIssue.mouthNotOpen => 'Abra mais a boca e segure',
    };

/// Valores da etapa "olhos abertos" usados como referência nas seguintes.
class CalibrationReference {
  const CalibrationReference({
    this.pitch,
    this.roll,
    this.yaw,
    this.openEar,
    this.openMar,
    this.openProb,
  });

  factory CalibrationReference.fromThresholds(Thresholds t) => CalibrationReference(
        pitch: t.headPitch,
        roll: t.headRoll,
        yaw: t.headYaw,
        openEar: t.openEar,
        openMar: t.openMar,
        openProb: t.openProb,
      );

  final double? pitch, roll, yaw, openEar, openMar, openProb;
}

/// Um quadro lido durante a calibração.
class CalibrationFrame {
  const CalibrationFrame({
    required this.ear,
    required this.mar,
    required this.now,
    this.leftEar,
    this.rightEar,
    this.pitch,
    this.roll,
    this.yaw,
    this.eyeProb,
    this.smile,
    this.framed = true,
  });

  final double ear, mar;
  final int now;
  final double? leftEar, rightEar, pitch, roll, yaw, eyeProb, smile;

  /// Rosto com tamanho e posição adequados no quadro.
  final bool framed;
}

/// Motivo de reprovação de uma etapa.
class CalibrationIssue {
  const CalibrationIssue(this.title, this.hint, {this.canForce = false});
  final String title;
  final String hint;

  /// Permite continuar mesmo assim (com o modo de reforço) após as tentativas.
  final bool canForce;
}

/// Resultado da análise de uma etapa.
class StepAnalysis {
  const StepAnalysis({
    required this.step,
    required this.ear,
    required this.mar,
    this.issue,
    this.eyeProb,
    this.pitch,
    this.roll,
    this.yaw,
    this.smile,
    this.leftEar,
    this.rightEar,
    this.variation = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.blinkShare = 0,
    this.forced = false,
  });

  final int step;
  final CalibrationIssue? issue;
  bool get ok => issue == null;
  final double ear, mar;
  final double? eyeProb, pitch, roll, yaw, smile, leftEar, rightEar;

  /// Variação da medida principal da etapa (0,05 = 5%).
  final double variation;
  final int accepted, rejected;
  final double blinkShare;

  /// Aceita manualmente apesar da reprovação ("continuar com reforço").
  final bool forced;

  StepAnalysis asForced() => StepAnalysis(
        step: step,
        ear: ear,
        mar: mar,
        eyeProb: eyeProb,
        pitch: pitch,
        roll: roll,
        yaw: yaw,
        smile: smile,
        leftEar: leftEar,
        rightEar: rightEar,
        variation: variation,
        accepted: accepted,
        rejected: rejected,
        blinkShare: blinkShare,
        forced: true,
      );
}

double? _medianOrNull(List<double> v) => v.isEmpty ? null : median(v);

/// Desvio absoluto mediano escalado (≈ desvio-padrão, mas resistente a picos).
double robustSpread(List<double> v) {
  if (v.length < 2) return 0;
  final m = median(v);
  return 1.4826 * median([for (final x in v) (x - m).abs()]);
}

/// Remove picos: mantém valores a até 3 desvios robustos da mediana.
List<double> withoutOutliers(List<double> v) {
  if (v.length < 5) return v;
  final m = median(v);
  final s = math.max(robustSpread(v), 0.005);
  return [for (final x in v) if ((x - m).abs() <= 3 * s) x];
}

/// Coleta e analisa as amostras de uma etapa de calibração.
class CalibrationSampler {
  int step = 0;
  CalibrationReference ref = const CalibrationReference();

  final List<double> _ears = [], _mars = [], _probs = [], _smiles = [];
  final List<double> _lefts = [], _rights = [];
  final List<double> _pitches = [], _rolls = [], _yaws = [];

  /// Quadros com o rosto bem posicionado, mesmo que reprovados pela regra da
  /// etapa (usados em "continuar com reforço").
  final List<double> _poseOkEars = [], _poseOkMars = [], _poseOkProbs = [];

  final Map<FrameIssue, int> issues = {};
  int _blinks = 0;
  int? _startTime;
  final List<(int, double, double, double)> _poseHistory = [];

  FrameIssue lastIssue = FrameIssue.none;

  void configure(int step, {CalibrationReference? ref}) {
    this.step = step;
    this.ref = ref ?? const CalibrationReference();
    reset();
  }

  void reset() {
    for (final l in [_ears, _mars, _probs, _smiles, _lefts, _rights, _pitches, _rolls, _yaws,
      _poseOkEars, _poseOkMars, _poseOkProbs]) {
      l.clear();
    }
    issues.clear();
    _blinks = 0;
    _startTime = null;
    _poseHistory.clear();
    lastIssue = FrameIssue.none;
  }

  int get accepted => _ears.length;
  int get rejected => issues.values.fold(0, (a, b) => a + b);
  bool get done => _ears.length >= samplesPerStep;
  int get progress => ((_ears.length / samplesPerStep) * 100).round().clamp(0, 100);
  double get medianEar => median(_ears);
  double get medianMar => median(_mars);
  double? get medianPitch => _medianOrNull(_pitches);
  double? get medianRoll => _medianOrNull(_rolls);
  double? get medianYaw => _medianOrNull(_yaws);
  double? get medianProb => _medianOrNull(_probs);

  /// A etapa passou do tempo máximo sem juntar amostras válidas suficientes.
  bool timedOut(int now) => !done && _startTime != null && now - _startTime! > calibStepTimeoutMs;

  bool get _smileStep => step == 3;

  /// Avalia um quadro. Retorna [FrameIssue.none] se ele entrou na calibração.
  FrameIssue add(CalibrationFrame f) {
    if (done) return FrameIssue.none;
    _startTime ??= f.now;
    final issue = _check(f);
    lastIssue = issue;
    if (issue == FrameIssue.none) {
      _ears.add(f.ear);
      _mars.add(f.mar);
      if (f.eyeProb != null) _probs.add(f.eyeProb!);
      if (f.smile != null) _smiles.add(f.smile!);
      if (f.leftEar != null && f.rightEar != null) {
        _lefts.add(f.leftEar!);
        _rights.add(f.rightEar!);
      }
      if (f.pitch != null && f.roll != null) {
        _pitches.add(f.pitch!);
        _rolls.add(f.roll!);
      }
      if (f.yaw != null) _yaws.add(f.yaw!);
    } else {
      issues[issue] = (issues[issue] ?? 0) + 1;
      if (issue == FrameIssue.blink) _blinks++;
    }
    return issue;
  }

  FrameIssue _check(CalibrationFrame f) {
    if (!f.framed) return FrameIssue.framing;

    // Velocidade da cabeça medida numa janela (o tremor entre quadros não conta).
    final p = f.pitch, r = f.roll, y = f.yaw ?? 0;
    if (p != null && r != null) {
      _poseHistory.add((f.now, p, r, y));
      while (_poseHistory.length > 2 && f.now - _poseHistory[1].$1 >= calibSpeedWindowMs) {
        _poseHistory.removeAt(0);
      }
      final old = _poseHistory.first;
      final dt = f.now - old.$1;
      if (dt >= calibSpeedWindowMs ~/ 2) {
        final delta = math.max((p - old.$2).abs(), math.max((r - old.$3).abs(), (y - old.$4).abs()));
        final speed = delta * 1000 / dt;
        if (speed > (_smileStep ? calibSmileMaxSpeedDegPerS : calibMaxSpeedDegPerS)) return FrameIssue.moving;
      }

      // Mesma posição da cabeça (na 1ª etapa, a mediana do que já foi aceito).
      final tol = _smileStep ? calibSmilePoseToleranceDeg : calibPoseToleranceDeg;
      final rp = ref.pitch ?? (_pitches.length >= 10 ? median(_pitches) : null);
      final rr = ref.roll ?? (_rolls.length >= 10 ? median(_rolls) : null);
      final ry = ref.yaw ?? (_yaws.length >= 10 ? median(_yaws) : null);
      if ((rp != null && (p - rp).abs() > tol) ||
          (rr != null && (r - rr).abs() > tol) ||
          (ry != null && f.yaw != null && (y - ry).abs() > tol)) {
        return FrameIssue.pose;
      }
    }

    _poseOkEars.add(f.ear);
    _poseOkMars.add(f.mar);
    if (f.eyeProb != null) _poseOkProbs.add(f.eyeProb!);

    switch (step) {
      case 0:
        if (_ears.length >= 10 && f.ear < calibBlinkFactor * median(_ears)) return FrameIssue.blink;
      case 1:
        // Os dois sinais dizem "olho como na etapa aberta": ainda não fechou.
        final oe = ref.openEar, op = ref.openProb;
        if (oe != null && f.ear >= 0.9 * oe && (f.eyeProb == null || op == null || f.eyeProb! >= op - 0.15)) {
          return FrameIssue.eyesStillOpen;
        }
      case 2:
        if (f.mar < 0.9 * calibMinYawnMar) return FrameIssue.mouthNotOpen;
    }
    return FrameIssue.none;
  }

  FrameIssue get _mainIssue {
    if (issues.isEmpty) return FrameIssue.framing;
    return issues.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Analisa a etapa (chamar quando [done] ou [timedOut]).
  StepAnalysis analyze() {
    if (!done) {
      final main = _mainIssue;
      final canForce = step == 1 && main == FrameIssue.eyesStillOpen && _poseOkEars.length >= samplesPerStep;
      return StepAnalysis(
        step: step,
        ear: _poseOkEars.isEmpty ? 0 : median(_poseOkEars),
        mar: _poseOkMars.isEmpty ? 0 : median(_poseOkMars),
        eyeProb: _medianOrNull(_poseOkProbs),
        pitch: ref.pitch,
        roll: ref.roll,
        yaw: ref.yaw,
        accepted: accepted,
        rejected: rejected,
        issue: CalibrationIssue(
          'Não foi possível completar a leitura',
          canForce
              ? 'Nesta posição do celular os olhos fechados ficaram muito parecidos com os abertos. '
                  'Feche bem os olhos, ou suba o celular para mais perto da altura do rosto.'
              : '${frameIssueText(main)}.',
          canForce: canForce,
        ),
      );
    }

    final ears = withoutOutliers(_ears);
    final mars = withoutOutliers(_mars);
    final ear = median(ears), mar = median(mars);
    final earVar = ear > 0 ? robustSpread(ears) / ear : 1.0;
    final marVar = mar > 0 ? robustSpread(mars) / mar : 1.0;
    final prob = _medianOrNull(_probs);
    final blinkShare = _blinks / (_ears.length + _blinks);

    StepAnalysis result(CalibrationIssue? issue, double variation) => StepAnalysis(
          step: step,
          issue: issue,
          ear: ear,
          mar: mar,
          eyeProb: prob,
          pitch: medianPitch,
          roll: medianRoll,
          yaw: medianYaw,
          smile: _medianOrNull(_smiles),
          leftEar: _medianOrNull(_lefts),
          rightEar: _medianOrNull(_rights),
          variation: variation,
          accepted: accepted,
          rejected: rejected,
          blinkShare: blinkShare,
        );

    switch (step) {
      case 0:
        if (blinkShare > calibMaxBlinkShare) {
          return result(
              const CalibrationIssue('Muitas piscadas', 'Mantenha os olhos abertos e relaxados, sem forçar.'),
              earVar);
        }
        if (earVar > calibMaxOpenEarCv) {
          return result(
              const CalibrationIssue('Leitura dos olhos instável',
                  'Mantenha o rosto parado, o olhar fixo e a iluminação constante.'),
              earVar);
        }
        return result(null, earVar);
      case 1:
        if (earVar > calibMaxClosedEarCv && robustSpread(ears) > calibMaxClosedEarSpread) {
          return result(
              const CalibrationIssue('Olhos não ficaram fechados de forma constante',
                  'Feche os olhos e mantenha fechados até o "plim".'),
              earVar);
        }
        final oe = ref.openEar, op = ref.openProb;
        final earSep = oe != null && oe > 0 ? (oe - ear) / oe : 1.0;
        final probSep = op != null && prob != null ? op - prob : null;
        if (earSep < calibMinEarSeparation && (probSep == null || probSep < calibMinProbSeparation)) {
          return result(
              const CalibrationIssue('Olho fechado parecido com o aberto',
                  'Feche bem os olhos. Se continuar, suba o celular para mais perto da altura do rosto.',
                  canForce: true),
              earVar);
        }
        return result(null, earVar);
      case 2:
        final neutral = ref.openMar;
        if (mar < calibMinYawnMar || (neutral != null && mar < calibYawnOverNeutral * neutral)) {
          return result(
              const CalibrationIssue('Boca pouco aberta', 'Abra a boca como num bocejo grande e segure.'),
              marVar);
        }
        if (marVar > calibMaxMarCv) {
          return result(
              const CalibrationIssue('Boca não ficou parada aberta',
                  'Segure a boca bem aberta, sem fechar, até o "plim".'),
              marVar);
        }
        return result(null, marVar);
      default:
        final smile = _medianOrNull(_smiles);
        final neutral = ref.openMar;
        final mouthMoved = neutral != null && mar >= 1.3 * neutral;
        if (smile != null && smile < 0.4 && !mouthMoved) {
          return result(
              const CalibrationIssue('Sorriso não identificado', 'Sorria mostrando os dentes ou dê uma risada.'),
              marVar);
        }
        return result(null, marVar);
    }
  }
}

// ---------------------------------------------------------------------------
// Análise do rosto (mostrada antes de confirmar a calibração)
// ---------------------------------------------------------------------------

enum CheckLevel { good, info, warn }

class FaceCheck {
  const FaceCheck(this.level, this.title, this.detail);
  final CheckLevel level;
  final String title;
  final String detail;
}

String _pct(double v) => '${(v * 100).round()}%';
String _n(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Resumo de como é o rosto da pessoa e como o app se ajustou a ele.
class FaceProfile {
  FaceProfile(this.t, this.steps);

  final Thresholds t;
  final Map<int, StepAnalysis> steps;

  /// Quão diferentes ficaram os dois olhos com os olhos abertos (0,1 = 10%).
  double? get asymmetry {
    final s = steps[0];
    final l = s?.leftEar, r = s?.rightEar;
    if (l == null || r == null || math.max(l, r) <= 0) return null;
    return (l - r).abs() / math.max(l, r);
  }

  bool get forced => steps.values.any((s) => s.forced);

  /// Confiança geral: alta, média (reforço) ou baixa (etapa forçada).
  String get confidence => forced
      ? 'Baixa'
      : (t.lowEyeConfidence || (t.phonePosition?.needsReinforcement ?? false))
          ? 'Média'
          : 'Alta';

  List<FaceCheck> get checks {
    final list = <FaceCheck>[];
    final pos = t.phonePosition;
    if (pos != null) {
      list.add(FaceCheck(pos.isFront ? CheckLevel.good : pos.needsReinforcement ? CheckLevel.warn : CheckLevel.info,
          'Celular: ${pos.label}', pos.detail));
    }

    final open = steps[0];
    if (open != null) {
      list.add(FaceCheck(CheckLevel.good, 'Leitura estável',
          '${open.accepted} quadros válidos por etapa; variação dos olhos abertos de ${_pct(open.variation)} '
              '(limite ${_pct(calibMaxOpenEarCv)}). Piscadas e movimentos foram descartados.'));
    }

    final oe = t.openEar;
    if (oe != null) {
      final ratio = t.ear / earDefault;
      final shape = ratio < 0.9
          ? 'Seus olhos aparecem mais fechados/estreitos que o padrão (olhos puxados ou pálpebra mais baixa)'
          : ratio > 1.1
              ? 'Seus olhos aparecem mais abertos que o padrão'
              : 'Abertura dos olhos dentro do padrão';
      list.add(FaceCheck(CheckLevel.info, 'Formato dos olhos',
          '$shape. EAR aberto ${_n(oe)}${t.closedEar != null ? ', fechado ${_n(t.closedEar!)}' : ''}: '
              'limite pessoal ${_n(t.ear)} (padrão ${_n(earDefault)}).'));
    }

    final asym = asymmetry;
    if (asym != null) {
      list.add(asym >= calibAsymmetryWarn
          ? FaceCheck(CheckLevel.info, 'Um olho mais fechado que o outro',
              'Diferença de ${_pct(asym)} entre os olhos. O app usa a média dos dois, medida em você, '
                  'então isso não gera alarme falso.')
          : FaceCheck(CheckLevel.good, 'Olhos simétricos', 'Diferença de ${_pct(asym)} entre os olhos.'));
    }

    final sep = t.eyeSeparation;
    if (sep != null) {
      final closed = steps[1];
      list.add(closed?.forced == true
          ? FaceCheck(CheckLevel.warn, 'Olho fechado pouco diferente do aberto',
              'Separação de ${_pct(sep)}. Você escolheu continuar: o reforço fica ligado '
                  '(cabeça mais sensível; boca normal).')
          : t.lowEyeConfidence
              ? FaceCheck(CheckLevel.warn, 'Olhos pouco visíveis nesta posição',
                  'Separação aberto × fechado de ${_pct(sep)}. Reforço ligado'
                      '${t.eyeProbThreshold != null ? ' e olho medido também pela probabilidade do ML Kit' : ''}.')
              : FaceCheck(CheckLevel.good, 'Olho aberto × fechado bem separados',
                  'Separação de ${_pct(sep)} (mínimo ${_pct(calibMinEarSeparation)}).'));
    }

    final y = t.yawnMar;
    if (y != null) {
      list.add(FaceCheck(CheckLevel.good, 'Bocejo registrado',
          'MAR do bocejo ${_n(y)}${t.openMar != null ? ' (boca fechada ${_n(t.openMar!)})' : ''}: '
              'limite de bocejo ${_n(t.mar)}.'));
    }

    final smile = steps[3];
    list.add(smile == null
        ? const FaceCheck(CheckLevel.info, 'Sorriso não calibrado',
            'Etapa opcional pulada. Dá para fazer depois em Configurações.')
        : FaceCheck(CheckLevel.good, 'Sorriso registrado',
            'Fala e risada não serão confundidas com olho fechado ou bocejo (limite de fala ${_n(t.marNeutral)}).'));
    return list;
  }
}
