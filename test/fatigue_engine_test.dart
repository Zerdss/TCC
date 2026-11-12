import 'dart:math' as math;

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
      // modo inclinação: olho fechado sozinho precisa do dobro do tempo (2,4 s)
      var m = run(e, from: 533, to: 2000, ear: ear, eyeProb: 0.05);
      expect(m.reinforced, isTrue);
      expect(m.tiltMode, isTrue);
      expect(m.alert, isFalse);
      m = run(e, from: 2033, to: 3300, ear: ear, eyeProb: 0.05);
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
      var anyMoving = false;
      for (var t = 1; t <= 2500; t += 33) {
        // cabeça balançando de um lado a outro (±30°, 1,5 vez por segundo, até ~280°/s),
        // olhos "fechados" na imagem pelo borrão
        final yaw = 30 * math.sin(2 * math.pi * 1.5 * t / 1000);
        m = e.process(0.10, 0.1, t, pitch: 0, roll: 0, yaw: yaw);
        anyMoving |= m.moving;
        expect(m.alert, isFalse);
      }
      expect(anyMoving, isTrue);
    });

    test('tremor normal do detector não conta como movimento', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      var m = FatigueMetrics.empty;
      for (var t = 1, i = 0; t <= 2500; t += 33, i++) {
        m = e.process(0.30, 0.1, t, pitch: i.isEven ? 1.5 : -1.5, roll: 0, yaw: i.isEven ? -1.5 : 1.5);
        expect(m.moving, isFalse);
      }
    });

    test('voltar a olhar a estrada encerra o aviso', () {
      final e = FatigueEngine(Thresholds())..setHeadBaseline(0, 0, 0);
      run(e, from: 1, to: 3000, ear: 0.30, pitch: 0, roll: 0, yaw: 40);
      final m = run(e, from: 3033, to: 3600, ear: 0.30, pitch: 0, roll: 0, yaw: 0);
      expect(m.lookAwayMs, 0);
      expect(m.classify(e.settings).status, FatigueStatus.normal);
    });
  });

  group('posição do celular', () {
    test('rosto de frente na câmera → celular de frente (reto), sem reforço', () {
      const p = PhonePosition(3, -4);
      expect(p.label, 'De frente (reto)');
      expect(p.isFront, isTrue);
      expect(p.needsReinforcement, isFalse);
    });

    test('rosto "olhando para cima" na câmera → celular abaixo', () {
      expect(const PhonePosition(18, 0).label, 'Abaixo do rosto');
      expect(const PhonePosition(18, 0).needsReinforcement, isFalse);
      expect(const PhonePosition(32, 0).label, 'Bem abaixo do rosto');
      expect(const PhonePosition(32, 0).needsReinforcement, isTrue);
    });

    test('acima e de lado', () {
      expect(const PhonePosition(-20, 0).label, 'Acima do rosto');
      expect(const PhonePosition(0, 22).label, 'De lado');
      expect(const PhonePosition(20, -22).label, 'Abaixo do rosto e de lado');
      expect(const PhonePosition(0, 35).needsReinforcement, isTrue);
    });

    test('celular bem abaixo liga o reforço mesmo com olhos bem separados', () {
      final t = Thresholds()
        ..restore(ear: 0.2, mar: 0.5, marNeutral: 0.1, headPitch: 30, headRoll: 0, headYaw: 0);
      expect(t.phonePosition!.vertical, PhoneVertical.below);
      expect(FatigueEngine(t).reinforced, isTrue);
      final front = Thresholds()
        ..restore(ear: 0.2, mar: 0.5, marNeutral: 0.1, headPitch: 2, headRoll: 0, headYaw: 0);
      expect(FatigueEngine(front).reinforced, isFalse);
    });

    test('sem calibração a posição é desconhecida', () {
      expect(Thresholds().phonePosition, isNull);
    });
  });

  group('modo inclinação (celular abaixo do rosto)', () {
    // Calibrado com o celular abaixo do rosto (rosto "olhando para cima" 20° na câmera).
    FatigueEngine below() => FatigueEngine(Thresholds()
      ..restore(ear: 0.19, mar: 0.6, marNeutral: 0.35, headPitch: 20, headRoll: 0, headYaw: 0))
      ..setHeadBaseline(20, 0, 0);

    test('liga sozinho com o celular abaixo do rosto', () {
      expect(below().tiltMode, isTrue);
      final front = FatigueEngine(Thresholds()
        ..restore(ear: 0.19, mar: 0.6, marNeutral: 0.35, headPitch: 2, headRoll: 0, headYaw: 0));
      expect(front.tiltMode, isFalse);
    });

    test('olho achatado na imagem (EAR baixo) não gera alarme nem aviso', () {
      final e = below();
      final m = run(e, from: 1, to: 6000, ear: 0.12, pitch: 20, roll: 0, yaw: 0);
      expect(m.closedMs, greaterThan(5000)); // o EAR diria "fechado"...
      expect(m.alert, isFalse); // ...mas no modo inclinação os olhos não decidem
      expect(m.classify(e.settings).status, FatigueStatus.normal);
    });

    test('cabeça caída por 2 s é ALERTA, mesmo sem enxergar bem os olhos', () {
      final e = below();
      run(e, from: 1, to: 500, ear: 0.2, pitch: 20, roll: 0, yaw: 0);
      var m = run(e, from: 533, to: 1900, ear: 0.2, pitch: 4, roll: 0, yaw: 0); // 16° por ~1,4 s
      expect(m.alert, isFalse);
      m = run(e, from: 1933, to: 2700, ear: 0.2, pitch: 4, roll: 0, yaw: 0); // > 2 s
      expect(m.alertReason, AlertReason.head);
    });

    test('cabeça caindo com os olhos fechados alerta mais rápido (1,2 s)', () {
      final e = below();
      run(e, from: 1, to: 500, ear: 0.2, pitch: 20, roll: 0, yaw: 0);
      final m = run(e, from: 533, to: 1900, ear: 0.08, pitch: 4, roll: 0, yaw: 0);
      expect(m.alertReason, AlertReason.head);
    });

    FatigueMetrics nods(FatigueEngine e, int count, {required double ear, double? prob}) {
      var t = 1;
      for (var k = 0; k < count; k++) {
        run(e, from: t, to: t + 1000, ear: ear, pitch: 20, roll: 0, yaw: 0, eyeProb: prob);
        t += 1033;
        run(e, from: t, to: t + 900, ear: ear, pitch: 5, roll: 0, yaw: 0, eyeProb: prob); // cai 15°
        t += 933;
      }
      return run(e, from: t, to: t + 300, ear: ear, pitch: 20, roll: 0, yaw: 0, eyeProb: prob);
    }

    test('cabeceio: 2 no minuto = ATENÇÃO; 3 = ALERTA', () {
      final e = below();
      var m = nods(e, 2, ear: 0.14);
      expect(m.nods, 2);
      expect(m.alert, isFalse);
      expect(m.classify(e.settings).notice, contains('Cabeceio'));

      final e3 = below();
      m = nods(e3, 3, ear: 0.14);
      expect(m.alertReason, AlertReason.head);
      expect(m.nodAlert, isTrue);
      expect(m.classify(e3.settings).notice, contains('cabeceio repetido'));
    });

    test('olhadas rápidas para baixo com o olho aberto não contam como cabeceio', () {
      final e = below();
      final m = nods(e, 3, ear: 0.30, prob: 0.9);
      expect(m.nods, 0);
      expect(m.alert, isFalse);
    });

    test('o alerta termina quando a cabeça volta, mesmo com o olho achatado na imagem', () {
      final e = below();
      run(e, from: 1, to: 500, ear: 0.12, pitch: 20, roll: 0, yaw: 0);
      var m = run(e, from: 533, to: 3000, ear: 0.12, pitch: 4, roll: 0, yaw: 0);
      expect(m.alert, isTrue);
      m = run(e, from: 3033, to: 4500, ear: 0.12, pitch: 20, roll: 0, yaw: 0);
      expect(m.alert, isFalse);
    });
  });
}
