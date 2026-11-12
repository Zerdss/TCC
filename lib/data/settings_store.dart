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
  static const _head = 'settings.headEnabled';
  static const _headDeg = 'settings.headDropDeg';
  static const _headMs = 'settings.headAlertMs';
  static const _face = 'settings.faceLostEnabled';
  static const _faceMs = 'settings.faceLostAlertMs';
  static const _full = 'settings.fullScreenAlert';
  static const _escalate = 'settings.escalatingAlert';
  static const _landscape = 'settings.allowLandscape';
  static const _autoCal = 'settings.autoAdvanceCalibration';
  static const _reinforce = 'settings.forceReinforced';
  static const _floating = 'settings.floatingWindow';
  static const _night = 'settings.nightMode';
  static const _nightPeriod = 'settings.nightPeriodMs';
  static const _nightMax = 'settings.nightMaxBrightness';

  Future<StoredSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return StoredSettings(
      sound: p.getBool(_sound) ?? true,
      vibration: p.getBool(_vibration) ?? true,
      smileFilter: p.getBool(_smile) ?? true,
      eyesAlertMs: p.getInt(_eyesMs) ?? closedFatigueMs,
      yawnAlertMs: p.getInt(_yawnMs) ?? yawnMinMs,
      blinkWarnRate: p.getInt(_blink) ?? warnBlinkRate,
      headEnabled: p.getBool(_head) ?? true,
      headDropDeg: p.getDouble(_headDeg) ?? headDropDefaultDeg,
      headAlertMs: p.getInt(_headMs) ?? headAlertDefaultMs,
      faceLostEnabled: p.getBool(_face) ?? true,
      faceLostAlertMs: p.getInt(_faceMs) ?? faceLostAlertDefaultMs,
      fullScreenAlert: p.getBool(_full) ?? true,
      escalatingAlert: p.getBool(_escalate) ?? true,
      allowLandscape: p.getBool(_landscape) ?? false,
      autoAdvanceCalibration: p.getBool(_autoCal) ?? true,
      forceReinforced: p.getBool(_reinforce) ?? false,
      floatingWindow: p.getBool(_floating) ?? true,
      nightMode: p.getBool(_night) ?? true,
      nightPeriodMs: p.getInt(_nightPeriod) ?? 20000,
      nightMaxBrightness: p.getDouble(_nightMax) ?? 0.6,
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
    await p.setBool(_head, detection.headEnabled);
    await p.setDouble(_headDeg, detection.headDropDeg);
    await p.setInt(_headMs, detection.headAlertMs);
    await p.setBool(_face, detection.faceLostEnabled);
    await p.setInt(_faceMs, detection.faceLostAlertMs);
    await p.setBool(_full, detection.fullScreenAlert);
    await p.setBool(_escalate, detection.escalatingAlert);
    await p.setBool(_landscape, detection.allowLandscape);
    await p.setBool(_autoCal, detection.autoAdvanceCalibration);
    await p.setBool(_reinforce, detection.forceReinforced);
    await p.setBool(_floating, detection.floatingWindow);
    await p.setBool(_night, detection.nightMode);
    await p.setInt(_nightPeriod, detection.nightPeriodMs);
    await p.setDouble(_nightMax, detection.nightMaxBrightness);
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
    required this.headEnabled,
    required this.headDropDeg,
    required this.headAlertMs,
    required this.faceLostEnabled,
    required this.faceLostAlertMs,
    required this.fullScreenAlert,
    required this.escalatingAlert,
    required this.allowLandscape,
    this.autoAdvanceCalibration = true,
    this.forceReinforced = false,
    this.floatingWindow = true,
    this.nightMode = true,
    this.nightPeriodMs = 20000,
    this.nightMaxBrightness = 0.6,
  });

  final bool sound;
  final bool vibration;
  final bool smileFilter;
  final int eyesAlertMs;
  final int yawnAlertMs;
  final int blinkWarnRate;
  final bool headEnabled;
  final double headDropDeg;
  final int headAlertMs;
  final bool faceLostEnabled;
  final int faceLostAlertMs;
  final bool fullScreenAlert;
  final bool escalatingAlert;
  final bool allowLandscape;
  final bool autoAdvanceCalibration;
  final bool forceReinforced;
  final bool floatingWindow;
  final bool nightMode;
  final int nightPeriodMs;
  final double nightMaxBrightness;

  void applyTo(DetectionSettings d) {
    d
      ..smileFilter = smileFilter
      ..eyesAlertMs = eyesAlertMs
      ..yawnAlertMs = yawnAlertMs
      ..blinkWarnRate = blinkWarnRate
      ..headEnabled = headEnabled
      ..headDropDeg = headDropDeg
      ..headAlertMs = headAlertMs
      ..faceLostEnabled = faceLostEnabled
      ..faceLostAlertMs = faceLostAlertMs
      ..fullScreenAlert = fullScreenAlert
      ..escalatingAlert = escalatingAlert
      ..allowLandscape = allowLandscape
      ..autoAdvanceCalibration = autoAdvanceCalibration
      ..forceReinforced = forceReinforced
      ..floatingWindow = floatingWindow
      ..nightMode = nightMode
      ..nightPeriodMs = nightPeriodMs
      ..nightMaxBrightness = nightMaxBrightness;
  }
}
