import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Janela flutuante (picture-in-picture, Android 8+): o detector continua
/// funcionando numa janela pequena por cima de outro app, como o GPS.
/// No iPhone não existe: o iOS não deixa outro app usar a câmera em segundo plano.
class FloatingWindow extends ChangeNotifier {
  FloatingWindow._();
  static final instance = FloatingWindow._();

  static const _channel = MethodChannel('fatigue_guard/pip');

  bool supported = false;
  bool active = false;

  /// Chamado pelo botão "Estou acordado" da janela flutuante.
  VoidCallback? onAcknowledge;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipChanged':
          active = call.arguments == true;
          notifyListeners();
        case 'ack':
          onAcknowledge?.call();
      }
    });
    try {
      supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
      active = await _channel.invokeMethod<bool>('isInPip') ?? false;
    } catch (_) {
      supported = false;
    }
    notifyListeners();
  }

  /// Abre a janela flutuante agora. Retorna `false` se o aparelho não suporta.
  Future<bool> enter() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Entra sozinho na janela flutuante ao sair do app (botão "início").
  Future<void> setAutoEnter(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('setAuto', {'enabled': enabled});
    } catch (_) {}
  }
}
