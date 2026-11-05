import 'package:shared_preferences/shared_preferences.dart';

import '../vision/fatigue_engine.dart';

/// Preferências do usuário (tela de Configurações), salvas no aparelho.
class SettingsStore {
  static const _sound = 'settings.sound';
  static const _vibration = 'settings.vibration';
  static const _smile = 'settings.smileFilter';
  static const _eyesMs = 'settings.eyesAlertMs';
  static const _yawnMs = 'settings.yawnAlertMs';
  static const _blink = 'settings.blinkWarnRate';

  Future<StoredSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return StoredSettings(
      sound: p.getBool(_sound) ?? true,
      vibration: p.getBool(_vibration) ?? true,
      smileFilter: p.getBool(_smile) ?? true,
      eyesAlertMs: p.getInt(_eyesMs) ?? closedFatigueMs,
      yawnAlertMs: p.getInt(_yawnMs) ?? yawnMinMs,
      blinkWarnRate: p.getInt(_blink) ?? warnBlinkRate,
    );
  }

  Future<void> save({required bool sound, required bool vibration, required DetectionSettings detection}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_sound, sound);
    await p.setBool(_vibration, vibration);
    await p.setBool(_smile, detection.smileFilter);
    await p.setInt(_eyesMs, detection.eyesAlertMs);
    await p.setInt(_yawnMs, detection.yawnAlertMs);
    await p.setInt(_blink, detection.blinkWarnRate);
  }
}

class StoredSettings {
  const StoredSettings({
    required this.sound,
    required this.vibration,
    required this.smileFilter,
    required this.eyesAlertMs,
    required this.yawnAlertMs,
    required this.blinkWarnRate,
  });

  final bool sound;
  final bool vibration;
  final bool smileFilter;
  final int eyesAlertMs;
  final int yawnAlertMs;
  final int blinkWarnRate;

  void applyTo(DetectionSettings d) {
    d
      ..smileFilter = smileFilter
      ..eyesAlertMs = eyesAlertMs
      ..yawnAlertMs = yawnAlertMs
      ..blinkWarnRate = blinkWarnRate;
  }
}
