import 'package:fatigue_guard/vision/fatigue_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula quadros a ~30 FPS e devolve a última métrica.
FatigueMetrics run(FatigueEngine e, {required int from, required int to, required double ear, double mar = 0.1}) {
  var m = FatigueMetrics.empty;
  for (var t = from; t <= to; t += 33) {
    m = e.process(ear, mar, t);
  }
  return m;
}

void main() {
  late FatigueEngine engine;
  setUp(() => engine = FatigueEngine(Thresholds()));

  test('olhos abertos → NORMAL', () {
    final m = run(engine, from: 1, to: 3000, ear: 0.30);
    expect(m.classify().status, FatigueStatus.normal);
    expect(m.perclos, 0);
  });

  test('piscada curta é contada e não gera alerta nem PERCLOS', () {
    run(engine, from: 1, to: 1000, ear: 0.30);
    run(engine, from: 1033, to: 1233, ear: 0.10); // ~200 ms fechado
    final m = run(engine, from: 1266, to: 2000, ear: 0.30);
    expect(m.blinkRate, 1);
    expect(m.alert, isFalse);
    expect(m.perclos, 0);
  });

  test('olhos fechados por mais de 1,2 s → ALERTA (motivo: olhos)', () {
    run(engine, from: 1, to: 1000, ear: 0.30);
    final m = run(engine, from: 1033, to: 2400, ear: 0.10);
    expect(m.alert, isTrue);
    expect(m.alertReason, AlertReason.eyes);
    expect(m.classify().status, FatigueStatus.alert);
    expect(m.perclos, greaterThan(0));
  });

  test('fechamento de ~0,8 s → ATENÇÃO', () {
    run(engine, from: 1, to: 1000, ear: 0.30);
    final m = run(engine, from: 1033, to: 1850, ear: 0.10);
    expect(m.classify().status, FatigueStatus.attention);
  });

  test('sorriso (MAR na faixa de expressão) não conta como olho fechado', () {
    final m = run(engine, from: 1, to: 3000, ear: 0.12, mar: 0.40);
    expect(m.expression, isTrue);
    expect(m.alert, isFalse);
  });

  test('bocejo sustentado por 1,8 s → ALERTA (motivo: bocejo)', () {
    final m = run(engine, from: 1, to: 2200, ear: 0.30, mar: 0.80);
    expect(m.yawning, isTrue);
    expect(m.alertReason, AlertReason.yawn);
  });

  test('histerese: só volta ao normal após 1 s estável', () {
    run(engine, from: 1, to: 1500, ear: 0.10);
    var m = run(engine, from: 1533, to: 2100, ear: 0.30);
    expect(m.alert, isTrue);
    m = run(engine, from: 2133, to: 3000, ear: 0.30);
    expect(m.alert, isFalse);
  });

  test('calibração ajusta limiares conforme as regras', () {
    final t = Thresholds();
    t.applyCalibration(0, 0.30, 0.05);
    t.applyCalibration(1, 0.10, 0.05);
    expect(t.ear, closeTo(0.10 + 0.28 * 0.20, 1e-9));
    t.applyCalibration(2, 0.28, 1.0);
    expect(t.mar, closeTo(0.72, 1e-9));
    t.applyCalibration(3, 0.20, 0.30);
    expect(t.mar, closeTo(0.30 + 0.6 * 0.70, 1e-9));
    expect(t.marNeutral, closeTo(0.285, 1e-9));
  });

  test('CalibrationSampler conclui após $samplesPerStep amostras', () {
    final s = CalibrationSampler();
    var finished = false;
    for (var i = 0; i < samplesPerStep; i++) {
      finished = s.add(0.3, 0.1);
    }
    expect(finished, isTrue);
    expect(s.progress, 100);
    expect(s.medianEar, 0.3);
  });

  test('tempo de alerta configurável', () {
    final e = FatigueEngine(Thresholds(), DetectionSettings()..eyesAlertMs = 2000);
    run(e, from: 1, to: 1000, ear: 0.30);
    var m = run(e, from: 1033, to: 2400, ear: 0.10); // ~1,4 s
    expect(m.alert, isFalse);
    expect(m.classify(e.settings).status, FatigueStatus.attention);
    m = run(e, from: 2433, to: 3200, ear: 0.10); // > 2 s
    expect(m.alert, isTrue);
    expect(m.classify(e.settings).notice, contains('2,0 s'));
  });

  test('filtro de sorriso desligado: olho semicerrado sorrindo conta como fechado', () {
    final e = FatigueEngine(Thresholds(), DetectionSettings()..smileFilter = false);
    final m = run(e, from: 1, to: 3000, ear: 0.12, mar: 0.40);
    expect(m.expression, isFalse);
    expect(m.alert, isTrue);
  });
}
