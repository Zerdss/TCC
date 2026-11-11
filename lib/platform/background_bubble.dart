import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Indicador flutuante (Android): uma bolinha por cima de outros apps (ex.: GPS)
/// com o ponto colorido do status e o ícone da câmera. A câmera e o ML Kit
/// rodam num serviço nativo e mandam os pontos do rosto para o app, que aplica
/// a mesma lógica de sonolência. Precisa da permissão "Exibir sobre outros apps".
class BackgroundBubble extends ChangeNotifier {
  BackgroundBubble._();
  static final instance = BackgroundBubble._();

  static const _channel = MethodChannel('fatigue_guard/bubble');

  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// O serviço está rodando (app em segundo plano com a bolinha na tela).
  bool running = false;

  /// Cada quadro vindo do serviço nativo.
  void Function(Map<Object?, Object?> frame)? onFrame;

  /// O serviço foi iniciado pelo próprio Android (botão "início").
  VoidCallback? onStarted;

  bool _ready = false;
  int? _lastStatus;
  bool? _lastCameraOk;

  void init() {
    if (_ready || !available) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'frame':
          final f = call.arguments;
          if (f is Map) onFrame?.call(f);
        case 'started':
          _setRunning(true);
          onStarted?.call();
      }
    });
  }

  void _setRunning(bool v) {
    if (running == v) return;
    running = v;
    _lastStatus = null;
    _lastCameraOk = null;
    notifyListeners();
  }

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  /// O usuário já liberou "Exibir sobre outros apps"?
  Future<bool> canDraw() async => await _call<bool>('canDraw') ?? false;

  /// Abre a tela do Android para liberar a permissão.
  Future<void> requestPermission() => _call('requestPermission');

  /// Liga a bolinha. Com [toBack], o app vai para segundo plano (mostra o GPS/início).
  Future<bool> start({bool toBack = false}) async {
    final ok = await _call<bool>('start', {'toBack': toBack}) ?? false;
    if (ok) _setRunning(true);
    return ok;
  }

  /// Desliga a bolinha e solta a câmera.
  Future<void> stop() async {
    await _call('stop');
    _setRunning(false);
  }

  /// Ao apertar "início" durante o monitoramento, liga a bolinha sozinho.
  Future<void> setAuto(bool enabled) => _call('setAuto', {'enabled': enabled});

  /// 0 = normal (verde), 1 = atenção (amarelo), 2 = alerta (vermelho).
  void update(int status, bool cameraOk) {
    if (!running || (status == _lastStatus && cameraOk == _lastCameraOk)) return;
    _lastStatus = status;
    _lastCameraOk = cameraOk;
    _call('status', {'status': status, 'cameraOk': cameraOk});
  }
}
