import 'package:fatigue_guard/vision/fatigue_engine.dart';
import 'package:fatigue_guard/vision/vision_controller.dart';
import 'package:fatigue_guard/vision/night_mode.dart';
import 'package:fatigue_guard/data/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Roda a luz de apoio de [from] a [to] (passos de 100 ms) e devolve o nível por instante.
Map<int, double> runLight(NightLight l, int from, int to, {bool dark = true, bool Function(int t)? suspicious}) {
  final out = <int, double>{};
  for (var t = from; t <= to; t += 100) {
    out[t] = l.update(t, dark: dark, suspicious: suspicious?.call(t) ?? false);
  }
  return out;
}

void main() {
  group('detecção de pouca luz', () {
    test('só troca para escuro depois de 3 s seguidos escuros', () {
      final d = DarkDetector();
      for (var t = 1; t <= 2500; t += 100) {
        d.update(20, t);
      }
      expect(d.dark, isFalse);
      for (var t = 2600; t <= 3400; t += 100) {
        d.update(20, t);
      }
      expect(d.dark, isTrue);
    });

    test('histerese: só volta a claro com brilho bem acima do limite', () {
      final d = DarkDetector();
      for (var t = 1; t <= 4000; t += 100) {
        d.update(20, t);
      }
      for (var t = 4100; t <= 9000; t += 100) {
        d.update(55, t); // entre 45 e 65: continua escuro
      }
      expect(d.dark, isTrue);
      for (var t = 9100; t <= 13000; t += 100) {
        d.update(90, t);
      }
      expect(d.dark, isFalse);
    });

    test('brilho médio da imagem', () {
      expect(sampleLuma(List.filled(10000, 30)), 30);
      // BGRA: lê só o canal verde
      final bgra = [for (var i = 0; i < 4000; i++) ...[0, 200, 0, 255]];
      expect(sampleLuma(bgra, offset: 1, stride: 4), 200);
      // NV21: ignora a parte de cor depois da luminância
      final nv21 = [...List.filled(6000, 10), ...List.filled(3000, 128)];
      expect(sampleLuma(nv21, length: 6000), 10);
    });
  });

  group('luz de apoio em rampa', () {
    test('sobe devagar, fica no máximo e desce devagar (sem clarão)', () {
      final l = NightLight(periodMs: 20000);
      final lv = runLight(l, 0, 8000);
      expect(lv[0], lessThan(0.1)); // começa baixo
      expect(lv[700], closeTo(700 / nightRampMs, 0.08)); // meio da subida
      expect(lv[2000], 1); // no máximo
      expect(lv[7000], 0); // já desceu
      // nunca pula mais que ~7% entre dois passos de 100 ms
      final values = lv.values.toList();
      for (var i = 1; i < values.length; i++) {
        expect((values[i] - values[i - 1]).abs(), lessThan(0.08));
      }
    });

    test('repete a cada 20 s enquanto estiver escuro', () {
      final l = NightLight(periodMs: 20000);
      final lv = runLight(l, 0, 45000);
      expect(lv[10000], 0); // apagada entre as rampas
      expect(lv[21500], 1); // segunda rampa
      expect(lv[41500], 1); // terceira
    });

    test('com sinal de sono a luz fica acesa até normalizar (máximo 15 s)', () {
      final l = NightLight(periodMs: 20000);
      final lv = runLight(l, 0, 25000, suspicious: (t) => t >= 2000 && t <= 9000);
      expect(lv[8000], 1); // sem a suspeita já teria apagado
      expect(lv[14000], 0); // normalizou: desceu (3 s depois da última suspeita + descida)
      final always = NightLight(periodMs: 20000);
      final lv2 = runLight(always, 0, 25000, suspicious: (_) => true);
      expect(lv2[15100], 0); // não fica acesa para sempre: no máximo 15 s
    });

    test('clareou: a luz desce e para', () {
      final l = NightLight(periodMs: 20000);
      runLight(l, 0, 2000);
      final lv = runLight(l, 2100, 6000, dark: false);
      expect(lv[6000], 0);
      expect(l.lit, isFalse);
    });
  });

  group('motor com pouca luz', () {
    test('liga o modo inclinação e não alarma por "rosto fora" no escuro', () {
      final e = FatigueEngine(Thresholds()..restore(ear: 0.19, mar: 0.6, marNeutral: 0.35, headPitch: 2, headRoll: 0));
      expect(e.tiltMode, isFalse);
      e.lowLight = true;
      expect(e.tiltMode, isTrue);
      e.process(0.3, 0.1, 100, pitch: 2, roll: 0, yaw: 0);
      var m = FatigueMetrics.empty;
      for (var t = 200; t <= 8000; t += 100) {
        m = e.noFace(t);
      }
      expect(m.alert, isFalse);
      expect(m.classify(e.settings).notice, contains('Pouca luz'));
    });
  });

  group('escolha Dia / Noite / Automático', () {
    test('padrão é Dia: o escuro não liga nada sozinho', () {
      final v = VisionController();
      expect(v.settings.lightMode, LightMode.day);
      for (var t = 1; t <= 5000; t += 100) {
        v.darkDetector.update(10, t);
      }
      expect(v.darkDetector.dark, isTrue);
      expect(v.nightActive, isFalse);
      v.dispose();
    });

    test('Noite escolhida pela pessoa vale mesmo sem medir o escuro', () {
      final v = VisionController();
      v.setLightMode(LightMode.night);
      expect(v.nightActive, isTrue);
      expect(v.engine.lowLight, isTrue);
      expect(v.engine.tiltMode, isTrue);
      v.setLightMode(LightMode.day);
      expect(v.nightActive, isFalse);
      expect(v.engine.lowLight, isFalse);
      v.dispose();
    });

    test('Automático só liga com a imagem escura', () {
      final v = VisionController();
      v.setLightMode(LightMode.auto);
      expect(v.nightActive, isFalse);
      for (var t = 1; t <= 5000; t += 100) {
        v.darkDetector.update(10, t);
      }
      expect(v.nightActive, isTrue);
      v.dispose();
    });
  });

  group('ajustes separados por modo', () {
    test('no modo Noite os ajustes valem só para a noite; o Dia não muda', () {
      final v = VisionController();
      v.settings.eyesAlertMs = 1500; // ajuste do dia
      v.setLightMode(LightMode.night);
      expect(v.nightProfile, isTrue);
      v.settings.eyesAlertMs = 2000; // ajuste da noite
      v.settings.headDropDeg = 15;
      v.setLightMode(LightMode.day);
      expect(v.nightProfile, isFalse);
      expect(v.settings.eyesAlertMs, 1500);
      expect(v.settings.headDropDeg, headDropDefaultDeg);
      v.setLightMode(LightMode.night);
      expect(v.settings.eyesAlertMs, 2000);
      expect(v.engine.settings.headDropDeg, 15); // o motor usa os ajustes da noite
      v.dispose();
    });

    test('a escolha do modo e a luz de apoio são as mesmas nos dois perfis', () {
      final v = VisionController();
      v.setLightMode(LightMode.night);
      v.settings.nightPeriodMs = 30000;
      v.setLightMode(LightMode.day);
      expect(v.settings.nightPeriodMs, 30000);
      expect(v.settings.lightMode, LightMode.day);
      v.dispose();
    });

    test('os dois perfis são salvos e carregados separadamente', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore();
      final v = VisionController(settingsStore: store);
      v.settings.eyesAlertMs = 1400;
      v.setLightMode(LightMode.night);
      v.settings.eyesAlertMs = 2200;
      await v.saveSettings();
      v.dispose();

      final v2 = VisionController(settingsStore: store);
      await v2.loadPreferences();
      expect(v2.settings.lightMode, LightMode.night);
      expect(v2.nightProfile, isTrue);
      expect(v2.settings.eyesAlertMs, 2200);
      expect(v2.daySettings.eyesAlertMs, 1400);
      v2.dispose();
    });

    test('restaurar o padrão no modo Noite não volta para o modo Dia', () async {
      final v = VisionController();
      v.setLightMode(LightMode.night);
      v.settings.eyesAlertMs = 2500;
      await v.resetSettings();
      expect(v.settings.lightMode, LightMode.night);
      expect(v.settings.eyesAlertMs, closedFatigueMs);
      v.dispose();
    });
  });
}
