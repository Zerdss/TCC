import 'package:shared_preferences/shared_preferences.dart';

import '../vision/fatigue_engine.dart';

/// Guarda os limiares calibrados (só 3 números + data) em SharedPreferences,
/// para não ser preciso recalibrar toda vez que o app abre.
class CalibrationStore {
  static const _ear = 'calibration.ear';
  static const _mar = 'calibration.mar';
  static const _neutral = 'calibration.marNeutral';
  static const _date = 'calibration.savedAt';
  static const _pitch = 'calibration.headPitch';
  static const _roll = 'calibration.headRoll';

  Future<void> save(Thresholds t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ear, t.ear);
    await prefs.setDouble(_mar, t.mar);
    await prefs.setDouble(_neutral, t.marNeutral);
    await prefs.setString(_date, DateTime.now().toIso8601String());
    final hp = t.headPitch, hr = t.headRoll;
    if (hp != null && hr != null) {
      await prefs.setDouble(_pitch, hp);
      await prefs.setDouble(_roll, hr);
    } else {
      await prefs.remove(_pitch);
      await prefs.remove(_roll);
    }
  }

  /// Retorna a calibração salva ou `null` se não houver.
  Future<SavedCalibration?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ear = prefs.getDouble(_ear);
    final mar = prefs.getDouble(_mar);
    final neutral = prefs.getDouble(_neutral);
    final date = prefs.getString(_date);
    if (ear == null || mar == null || neutral == null || date == null) return null;
    return SavedCalibration(
      ear: ear,
      mar: mar,
      marNeutral: neutral,
      savedAt: DateTime.parse(date),
      headPitch: prefs.getDouble(_pitch),
      headRoll: prefs.getDouble(_roll),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_ear, _mar, _neutral, _date, _pitch, _roll]) {
      await prefs.remove(k);
    }
  }
}

class SavedCalibration {
  const SavedCalibration({
    required this.ear,
    required this.mar,
    required this.marNeutral,
    required this.savedAt,
    this.headPitch,
    this.headRoll,
  });
  final double? headPitch;
  final double? headRoll;
  final double ear;
  final double mar;
  final double marNeutral;
  final DateTime savedAt;
}
