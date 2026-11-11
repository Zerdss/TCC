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
  static const _lowEye = 'calibration.lowEyeConfidence';
  static const _eyeSep = 'calibration.eyeSeparation';
  static const _eyeProb = 'calibration.eyeProbThreshold';

  Future<void> save(Thresholds t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ear, t.ear);
    await prefs.setDouble(_mar, t.mar);
    await prefs.setDouble(_neutral, t.marNeutral);
    await prefs.setString(_date, DateTime.now().toIso8601String());
    await prefs.setBool(_lowEye, t.lowEyeConfidence);
    final sep = t.eyeSeparation, pt = t.eyeProbThreshold;
    if (sep != null) {
      await prefs.setDouble(_eyeSep, sep);
    } else {
      await prefs.remove(_eyeSep);
    }
    if (pt != null) {
      await prefs.setDouble(_eyeProb, pt);
    } else {
      await prefs.remove(_eyeProb);
    }
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
      lowEyeConfidence: prefs.getBool(_lowEye) ?? false,
      eyeSeparation: prefs.getDouble(_eyeSep),
      eyeProbThreshold: prefs.getDouble(_eyeProb),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_ear, _mar, _neutral, _date, _pitch, _roll, _lowEye, _eyeSep, _eyeProb]) {
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
    this.lowEyeConfidence = false,
    this.eyeSeparation,
    this.eyeProbThreshold,
  });
  final bool lowEyeConfidence;
  final double? eyeSeparation;
  final double? eyeProbThreshold;
  final double? headPitch;
  final double? headRoll;
  final double ear;
  final double mar;
  final double marNeutral;
  final DateTime savedAt;
}
