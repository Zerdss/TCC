import 'package:fatigue_guard/vision/fatigue_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula quadros a ~30 FPS e devolve a última métrica.
FatigueMetrics run(FatigueEngine e,
    {required int from,
    required int to,
    required double ear,
    double mar = 0.1,
    double? pitch,
    double? roll,
    double? yaw,
    double? smile,
    double? eyeProb}) {
  var m = FatigueMetrics.empty;
  for (var t = from; t <= to; t += 33) {
    m = e.process(ear, mar, t, pitch: pitch, roll: roll, yaw: yaw, smile: smile, eyeProb: eyeProb);
  }
  return m;
}

FatigueMetrics runNoFace(FatigueEngine e, {required int from, required int to}) {
  var m = FatigueMetrics.empty;
  for (var t = from; t <= to; t += 33) {
    m = e.noFace(t);
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

  group('cabeça caindo', () {
    // EAR 0,20 com limite 0,19: nem claramente fechado nem claramente aberto (indefinido).
    test('queda de 25° com olhos indefinidos → ATENÇÃO e ALERTA (cabeça) no dobro do tempo', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(5, 0);
      run(e, from: 1, to: 1000, ear: 0.30, pitch: 5, roll: 0);
      var m = run(e, from: 1033, to: 1900, ear: 0.20, pitch: -20, roll: 0); // ~0,9 s
      expect(m.alert, isFalse);
      expect(m.classify(e.settings).status, FatigueStatus.attention);
      expect(m.headPitch, closeTo(25, 1e-9));
      m = run(e, from: 1933, to: 2700, ear: 0.20, pitch: -20, roll: 0); // ~1,7 s: ainda não
      expect(m.alert, isFalse);
      m = run(e, from: 2733, to: 4200, ear: 0.20, pitch: -20, roll: 0); // > 3 s
      expect(m.alert, isTrue);
      expect(m.alertReason, AlertReason.head);
      expect(m.classify(e.settings).notice, contains('cabeça'));
    });

    test('inclinação lateral forte também conta', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0);
      final m = run(e, from: 1, to: 3500, ear: 0.20, pitch: 0, roll: 40);
      expect(m.alertReason, AlertReason.head);
    });

    test('pequenos movimentos não alertam e desligar a opção ignora a cabeça', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0);
      expect(run(e, from: 1, to: 3000, ear: 0.30, pitch: -10, roll: 8).alert, isFalse);
      final off = FatigueEngine(Thresholds(), DetectionSettings()..headEnabled = false)..setHeadBaseline(0, 0);
      expect(run(off, from: 1, to: 3000, ear: 0.30, pitch: -35, roll: 0).alert, isFalse);
    });

    test('sem calibração, a primeira posição vira a referência', () {
      final e = FatigueEngine(Thresholds());
      run(e, from: 1, to: 500, ear: 0.30, pitch: 12, roll: 0);
      expect(e.basePitch, closeTo(12, 0.5));
    });
  });

  group('rosto fora da câmera', () {
    test('sem rosto por 4 s → ALERTA; atenção na metade', () {
      final e = FatigueEngine(Thresholds());
      run(e, from: 1, to: 1000, ear: 0.30);
      var m = runNoFace(e, from: 1033, to: 3300); // ~2,3 s
      expect(m.faceVisible, isFalse);
      expect(m.classify(e.settings).status, FatigueStatus.attention);
      m = runNoFace(e, from: 3333, to: 5200);
      expect(m.alert, isTrue);
      expect(m.alertReason, AlertReason.faceLost);
    });

    test('antes do rosto aparecer pela primeira vez não alerta', () {
      final e = FatigueEngine(Thresholds());
      expect(runNoFace(e, from: 1, to: 9000).alert, isFalse);
    });

    test('rosto volta: sai do alerta após 1 s estável', () {
      final e = FatigueEngine(Thresholds());
      run(e, from: 1, to: 500, ear: 0.30);
      runNoFace(e, from: 533, to: 5000);
      var m = run(e, from: 5033, to: 5600, ear: 0.30);
      expect(m.alert, isTrue);
      m = run(e, from: 5633, to: 6800, ear: 0.30);
      expect(m.alert, isFalse);
    });
  });

  test('alertSinceMs cresce enquanto o alerta continua (alerta progressivo)', () {
    final e = FatigueEngine(Thresholds());
    run(e, from: 1, to: 500, ear: 0.30);
    final m = run(e, from: 533, to: 7000, ear: 0.10);
    expect(m.alert, isTrue);
    expect(m.alertSinceMs, greaterThanOrEqualTo(escalateAfterMs));
  });

  group('sorriso de boca fechada (detector de sorriso do ML Kit)', () {
    test('olhos semicerrados sorrindo com a boca fechada não geram alerta', () {
      final e = FatigueEngine(Thresholds());
      final m = run(e, from: 1, to: 3000, ear: 0.12, mar: 0.05, smile: 0.9);
      expect(m.expression, isTrue);
      expect(m.alert, isFalse);
      expect(m.closedMs, 0);
    });

    test('sem sorriso, os mesmos olhos fechados geram alerta', () {
      final e = FatigueEngine(Thresholds());
      final m = run(e, from: 1, to: 3000, ear: 0.12, mar: 0.05, smile: 0.1);
      expect(m.alert, isTrue);
      expect(m.alertReason, AlertReason.eyes);
    });

    test('com o filtro de sorriso desligado, o sorriso não é ignorado', () {
      final e = FatigueEngine(Thresholds(), DetectionSettings()..smileFilter = false);
      final m = run(e, from: 1, to: 3000, ear: 0.12, mar: 0.05, smile: 0.9);
      expect(m.alert, isTrue);
    });
  });

  group('modo de reforço (olhos pouco visíveis, ex.: celular muito baixo)', () {
    test('calibração de frente: olhos bem visíveis, sem reforço', () {
      final t = Thresholds()
        ..applyCalibration(0, 0.30, 0.05, medianProb: 0.9)
        ..applyCalibration(1, 0.10, 0.05, medianProb: 0.1);
      expect(t.lowEyeConfidence, isFalse);
      expect(t.eyeSeparation, closeTo(2 / 3, 1e-9));
      expect(t.eyeProbThreshold, closeTo(0.1 + 0.4 * 0.8, 1e-9));
    });

    test('calibração de baixo: aberto e fechado parecidos → reforço ligado', () {
      final t = Thresholds()
        ..applyCalibration(0, 0.20, 0.05, medianProb: 0.85)
        ..applyCalibration(1, 0.15, 0.05, medianProb: 0.15);
      expect(t.lowEyeConfidence, isTrue);
      expect(FatigueEngine(t).reinforced, isTrue);
    });

    test('probabilidade que não separa bem não é usada', () {
      final t = Thresholds()
        ..applyCalibration(0, 0.20, 0.05, medianProb: 0.6)
        ..applyCalibration(1, 0.15, 0.05, medianProb: 0.4);
      expect(t.eyeProbThreshold, isNull);
    });

    test('no reforço, olho fechado pela probabilidade gera alerta mesmo com EAR acima do limite', () {
      final t = Thresholds()
        ..applyCalibration(0, 0.20, 0.05, medianProb: 0.9)
        ..applyCalibration(1, 0.15, 0.05, medianProb: 0.1);
      final e = FatigueEngine(t);
      final ear = t.ear + 0.02; // o EAR sozinho diria "aberto"
      run(e, from: 1, to: 500, ear: ear, eyeProb: 0.95);
      final m = run(e, from: 533, to: 2000, ear: ear, eyeProb: 0.05);
      expect(m.reinforced, isTrue);
      expect(m.alertReason, AlertReason.eyes);
    });

    test('sem reforço, a probabilidade não muda a decisão', () {
      final t = Thresholds()
        ..applyCalibration(0, 0.30, 0.05, medianProb: 0.9)
        ..applyCalibration(1, 0.10, 0.05, medianProb: 0.1);
      final e = FatigueEngine(t);
      final m = run(e, from: 1, to: 2500, ear: t.ear + 0.05, eyeProb: 0.05);
      expect(m.alert, isFalse);
    });

    test('no reforço, a cabeça fica mais sensível (16° já conta como caída)', () {
      final normal = FatigueEngine(Thresholds())..setHeadBaseline(0, 0);
      final mNormal = run(normal, from: 1, to: 2600, ear: 0.20, pitch: -16, roll: 0);
      expect(mNormal.alert, isFalse);
      final forced = FatigueEngine(Thresholds(), DetectionSettings()..forceReinforced = true)..setHeadBaseline(0, 0);
      final mForced = run(forced, from: 1, to: 2600, ear: 0.20, pitch: -16, roll: 0);
      expect(mForced.alertReason, AlertReason.head);
    });
  });

  group('movimentos normais não geram alarme', () {
    test('olhar para baixo com os olhos abertos: sem alarme, só ATENÇÃO após 2,5 s', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      run(e, from: 1, to: 500, ear: 0.30, pitch: 0, roll: 0, yaw: 0, eyeProb: 0.9);
      var m = run(e, from: 533, to: 2000, ear: 0.30, pitch: -25, roll: 0, yaw: 0, eyeProb: 0.9);
      expect(m.lookingDown, isTrue);
      expect(m.alert, isFalse);
      expect(m.classify(e.settings).status, FatigueStatus.normal);
      m = run(e, from: 2033, to: 4500, ear: 0.30, pitch: -25, roll: 0, yaw: 0, eyeProb: 0.9);
      expect(m.alert, isFalse);
      expect(m.classify(e.settings).notice, contains('Olhando para baixo'));
    });

    test('olhar para baixo com as pálpebras baixas (EAR um pouco abaixo do limite) não alerta', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      // limite 0,19: 0,17 diria "fechado" de frente, mas com a cabeça baixa exige EAR < 0,16.
      final m = run(e, from: 1, to: 3000, ear: 0.17, pitch: -25, roll: 0, yaw: 0, eyeProb: 0.7);
      expect(m.alert, isFalse);
      expect(m.closedMs, 0);
    });

    test('cochilo de verdade (cabeça caindo + olhos fechados) alerta', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      run(e, from: 1, to: 500, ear: 0.30, pitch: 0, roll: 0, yaw: 0, eyeProb: 0.9);
      final m = run(e, from: 533, to: 2200, ear: 0.08, pitch: -25, roll: 0, yaw: 0, eyeProb: 0.05);
      expect(m.alert, isTrue);
    });

    test('olhar para o lado (olho distorcido na imagem): sem alarme, ATENÇÃO após 2,5 s', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      run(e, from: 1, to: 500, ear: 0.30, pitch: 0, roll: 0, yaw: 0);
      final m = run(e, from: 533, to: 4000, ear: 0.10, pitch: 0, roll: 0, yaw: 40);
      expect(m.lookingSide, isTrue);
      expect(m.alert, isFalse);
      expect(m.closedMs, 0);
      expect(m.classify(e.settings).notice, contains('Olhando para o lado'));
    });

    test('movimento brusco da cabeça pausa a medição dos olhos', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      var m = FatigueMetrics.empty;
      for (var t = 1, i = 0; t <= 2500; t += 33, i++) {
        // cabeça balançando ~300°/s, olhos "fechados" na imagem pelo borrão
        m = e.process(0.10, 0.1, t, pitch: 0, roll: 0, yaw: i.isEven ? 0 : 10);
      }
      expect(m.moving, isTrue);
      expect(m.alert, isFalse);
    });

    test('voltar a olhar a estrada encerra o aviso', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      run(e, from: 1, to: 3000, ear: 0.30, pitch: 0, roll: 0, yaw: 40);
      final m = run(e, from: 3033, to: 3600, ear: 0.30, pitch: 0, roll: 0, yaw: 0);
      expect(m.lookAwayMs, 0);
      expect(m.classify(e.settings).status, FatigueStatus.normal);
    });
  });
}
