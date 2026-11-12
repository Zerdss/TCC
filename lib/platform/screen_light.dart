import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Brilho da tela do app (Android: só a janela do app; iPhone: a tela).
/// Usado pelo modo noite como luz de apoio para a câmera frontal.
class ScreenLight {
  ScreenLight._();
  static final instance = ScreenLight._();
  static const _channel = MethodChannel('fatigue_guard/screen');

  bool get available => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS);

  double? _last;

  /// Brilho atual (0 a 1), ou `null` se não der para ler.
  Future<double?> current() async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<double>('getBrightness');
    } catch (_) {
      return null;
    }
  }

  /// Define o brilho (0 a 1). [value] negativo devolve o brilho do usuário.
  Future<void> set(double value) async {
    if (!available) return;
    if (_last != null && (value - _last!).abs() < 0.01) return;
    _last = value;
    try {
      await _channel.invokeMethod('setBrightness', value);
    } catch (_) {}
  }

  Future<void> restore() async {
    if (_last == null || _last! < 0) return;
    await set(-1);
  }
}
