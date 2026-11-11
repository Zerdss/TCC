import 'dart:math' as math;

import 'package:fatigue_guard/vision/calibration.dart';
import 'package:fatigue_guard/vision/fatigue_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alimenta o sampler com quadros a ~30 FPS até concluir ou passar do tempo.
StepAnalysis feed(
  CalibrationSampler s, {
  required double Function(int i) ear,
  double Function(int i)? mar,
  double Function(int i)? pitch,
  double Function(int i)? yaw,
  double? Function(int i)? prob,
  double? smile,
  bool framed = true,
  double? left,
  double? right,
}) {
  var t = 0;
  for (var i = 0; !s.done && !s.timedOut(t); i++, t += 33) {
    s.add(CalibrationFrame(
      ear: ear(i),
      mar: mar?.call(i) ?? 0.08,
      now: t,
      pitch: pitch?.call(i) ?? 0,
      roll: 0,
      yaw: yaw?.call(i) ?? 0,
      eyeProb: prob?.call(i),
      smile: smile,
      framed: framed,
      leftEar: left,
      rightEar: right,
    ));
  }
  return s.analyze();
}

/// Pequeno tremor, como o do detector real.
double jitter(int i, double base, double amp) => base + amp * math.sin(i * 1.7);

void main() {
  group('quadros só contam com o rosto bem lido', () {
    test('rosto fora do quadro ideal não conta', () {
      final s = CalibrationSampler()..configure(0);
      final issue = s.add(const CalibrationFrame(ear: 0.3, mar: 0.1, now: 0, pitch: 0, roll: 0, framed: false));
      expect(issue, FrameIssue.framing);
      expect(s.accepted, 0);
    });

    test('cabeça em movimento não conta; tremor pequeno conta', () {
      final s = CalibrationSampler()..configure(0);
      var moving = 0;
      for (var i = 0, t = 0; i < 40; i++, t += 33) {
        // 2 graus por quadro = ~60°/s
        if (s.add(CalibrationFrame(ear: 0.3, mar: 0.1, now: t, pitch: i * 2.0, roll: 0)) == FrameIssue.moving) {
          moving++;
        }
      }
      expect(moving, greaterThan(25));

      final calm = CalibrationSampler()..configure(0);
      final a = feed(calm, ear: (i) => jitter(i, 0.3, 0.005), pitch: (i) => jitter(i, 5, 1.5));
      expect(a.ok, isTrue);
      expect(a.accepted, samplesPerStep);
    });

    test('nas etapas seguintes a cabeça precisa estar na posição da 1ª etapa', () {
      final s = CalibrationSampler()
        ..configure(1, ref: const CalibrationReference(pitch: 0, roll: 0, yaw: 0, openEar: 0.3));
      final issue = s.add(const CalibrationFrame(ear: 0.1, mar: 0.1, now: 0, pitch: -20, roll: 0, yaw: 0));
      expect(issue, FrameIssue.pose);
    });

    test('piscadas são descartadas na etapa de olhos abertos', () {
      final s = CalibrationSampler()..configure(0);
      final a = feed(s, ear: (i) => i % 15 == 14 ? 0.12 : jitter(i, 0.3, 0.004));
      expect(a.ok, isTrue);
      expect(s.issues[FrameIssue.blink], greaterThan(0));
      expect(a.ear, closeTo(0.3, 0.01));
    });
  });

  group('cada etapa é analisada antes de ser aprovada', () {
    test('olhos abertos instáveis reprovam', () {
      final s = CalibrationSampler()..configure(0);
      // varia entre 0,26 e 0,34 sem ser piscada
      final a = feed(s, ear: (i) => 0.30 + 0.04 * math.sin(i * 0.9));
      expect(a.ok, isFalse);
      expect(a.issue!.title, contains('instável'));
    });

    test('muitas piscadas reprovam', () {
      final s = CalibrationSampler()..configure(0);
      final a = feed(s, ear: (i) => i >= 10 && i % 2 == 0 ? 0.1 : 0.3);
      expect(a.ok, isFalse);
      expect(a.issue!.title, 'Muitas piscadas');
    });

    test('olhos fechados de verdade passam', () {
      final s = CalibrationSampler()
        ..configure(1, ref: const CalibrationReference(pitch: 0, roll: 0, yaw: 0, openEar: 0.3, openProb: 0.9));
      final a = feed(s, ear: (i) => jitter(i, 0.12, 0.005), prob: (_) => 0.1);
      expect(a.ok, isTrue);
    });

    test('olhos que não fecham não completam a etapa (pode continuar com reforço)', () {
      final s = CalibrationSampler()
        ..configure(1, ref: const CalibrationReference(pitch: 0, roll: 0, yaw: 0, openEar: 0.3));
      final a = feed(s, ear: (i) => jitter(i, 0.29, 0.003));
      expect(a.ok, isFalse);
      expect(a.issue!.canForce, isTrue);
      expect(s.issues[FrameIssue.eyesStillOpen], greaterThan(0));
    });

    test('olho pouco diferente (celular muito abaixo) reprova, mas permite reforço', () {
      final s = CalibrationSampler()
        ..configure(1, ref: const CalibrationReference(pitch: 0, roll: 0, yaw: 0, openEar: 0.20, openProb: 0.5));
      // 0,18 < 0,9 × 0,20: entra na amostra, mas a separação é só 10%
      final a = feed(s, ear: (i) => jitter(i, 0.178, 0.002), prob: (_) => 0.4);
      expect(a.ok, isFalse);
      expect(a.issue!.title, contains('parecido'));
      expect(a.issue!.canForce, isTrue);
    });

    test('bocejo pequeno reprova; bocejo grande passa', () {
      const ref = CalibrationReference(pitch: 0, roll: 0, yaw: 0, openEar: 0.3, openMar: 0.08);
      final small = CalibrationSampler()..configure(2, ref: ref);
      final a = feed(small, ear: (_) => 0.3, mar: (i) => jitter(i, 0.45, 0.01));
      expect(a.ok, isFalse);

      final big = CalibrationSampler()..configure(2, ref: ref);
      final b = feed(big, ear: (_) => 0.3, mar: (i) => jitter(i, 0.85, 0.02));
      expect(b.ok, isTrue);
      expect(b.mar, closeTo(0.85, 0.03));
    });

    test('sorriso não identificado reprova', () {
      const ref = CalibrationReference(pitch: 0, roll: 0, yaw: 0, openEar: 0.3, openMar: 0.08);
      final s = CalibrationSampler()..configure(3, ref: ref);
      final a = feed(s, ear: (_) => 0.3, mar: (_) => 0.08, smile: 0.1);
      expect(a.ok, isFalse);
      final ok = CalibrationSampler()..configure(3, ref: ref);
      expect(feed(ok, ear: (_) => 0.25, mar: (_) => 0.2, smile: 0.9).ok, isTrue);
    });

    test('rosto sumido o tempo todo: etapa reprovada pelo tempo', () {
      final s = CalibrationSampler()..configure(0);
      final a = feed(s, ear: (_) => 0.3, framed: false);
      expect(a.ok, isFalse);
      expect(a.issue!.hint, contains('Rosto fora'));
    });
  });

  group('análise do rosto', () {
    Thresholds calibrated({double open = 0.30, double closed = 0.10}) => Thresholds()
      ..applyCalibration(0, open, 0.08, medianProb: 0.9)
      ..applyCalibration(1, closed, 0.08, medianProb: 0.1)
      ..applyCalibration(2, open, 0.85)
      ..headPitch = 0
      ..headRoll = 0
      ..headYaw = 0;

    test('olhos estreitos: limite pessoal abaixo do padrão', () {
      final p = FaceProfile(calibrated(open: 0.20, closed: 0.07), {});
      final eyes = p.checks.firstWhere((c) => c.title == 'Formato dos olhos');
      expect(eyes.detail, contains('mais fechados/estreitos'));
    });

    test('um olho mais fechado que o outro é identificado', () {
      final p = FaceProfile(calibrated(), {
        0: const StepAnalysis(step: 0, ear: 0.3, mar: 0.08, leftEar: 0.32, rightEar: 0.25),
      });
      expect(p.asymmetry, closeTo(0.22, 0.01));
      expect(p.checks.map((c) => c.title), contains('Um olho mais fechado que o outro'));
    });

    test('confiança alta de frente; baixa se uma etapa foi forçada', () {
      expect(FaceProfile(calibrated(), {}).confidence, 'Alta');
      final forced = FaceProfile(calibrated(), {
        1: const StepAnalysis(step: 1, ear: 0.2, mar: 0.08).asForced(),
      });
      expect(forced.confidence, 'Baixa');
    });
  });
}
