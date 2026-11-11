import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:vibration/vibration.dart';

import '../data/calibration_store.dart';
import '../data/models.dart';
import '../data/session_database.dart';
import '../data/session_recorder.dart';
import '../data/settings_store.dart';
import 'fatigue_engine.dart';
import 'metrics.dart';

enum EngineState { idle, loading, running, error }

/// Pontos que o overlay desenha sobre a câmera (coordenadas da imagem já rotacionada).
class FaceOverlayData {
  const FaceOverlayData({
    required this.imageSize,
    required this.box,
    required this.allPoints,
    required this.rings,
  });

  final Size imageSize;
  final Rect box;
  final List<Pt> allPoints;
  final List<List<Pt>> rings;
}

class FramingGuide {
  const FramingGuide(this.text, this.good);
  final String text;
  final bool good;
}

/// Controla câmera frontal + ML Kit Face Detection (contornos) e alimenta o
/// [FatigueEngine]. Todo o processamento ocorre no aparelho; nenhum quadro é
/// salvo ou enviado pela rede.
class VisionController extends ChangeNotifier {
  VisionController({this.database, this.calibrationStore, this.settingsStore})
      : engine = FatigueEngine(Thresholds());

  /// Preferências do usuário (opcional).
  final SettingsStore? settingsStore;

  AudioPlayer? _player;

  /// Banco local do histórico (opcional: nulo nos testes de widget).
  final SessionDatabase? database;

  /// Armazena os limiares calibrados (opcional).
  final CalibrationStore? calibrationStore;

  /// Sessões menores que isso não são gravadas (evita registros vazios).
  static const minSessionDuration = Duration(seconds: 10);

  SessionRecorder? _recorder;

  /// Última sessão gravada (para exibir um aviso no app).
  SessionRecord? lastSavedSession;

  final FatigueEngine engine;
  Thresholds get thresholds => engine.thresholds;
  DetectionSettings get settings => engine.settings;

  final _sampler = CalibrationSampler();

  CameraController? camera;
  CameraDescription? _description;
  FaceDetector? _detector;
  bool _busy = false;
  bool _disposed = false;

  EngineState state = EngineState.idle;
  String error = '';
  FatigueMetrics metrics = FatigueMetrics.empty;
  FatigueStatus status = FatigueStatus.normal;
  String notice = '';
  FaceOverlayData? overlay;
  FramingGuide guide = const FramingGuide('Iniciando câmera local...', false);
  double fps = 0;
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  /// Histórico curto para os mini‑gráficos do painel.
  final List<double> earHistory = [];
  final List<double> marHistory = [];
  final List<double> perclosHistory = [];

  /// Etapa de calibração ativa (0..3) ou `null` quando está em monitoramento.
  int? calibrationStep;
  int calibrationProgress = 0;

  final Stopwatch _clock = Stopwatch()..start();
  int _fpsFrames = 0;
  int _fpsStart = 0;
  int _lastAlertFeedback = 0;
  int _lastHistory = 0;

  bool get isFrontCamera => _description?.lensDirection == CameraLensDirection.front;

  // ------------------------------------------------------------ diagnóstico
  /// Formato pedido à câmera no Android. Começa em NV21; se o aparelho não
  /// entregar quadros utilizáveis, troca para YUV_420 e converte aqui.
  ImageFormatGroup _androidFormat = ImageFormatGroup.nv21;
  int _framesReceived = 0;
  int _framesProcessed = 0;
  int _consecutiveFailures = 0;
  int _runningSince = 0;
  String _lastFrameError = '';
  Timer? _watchdog;
  bool _restarting = false;

  /// Texto de diagnóstico exibido quando a câmera liga mas o detector não
  /// processa nenhum quadro (para o usuário mandar um print).
  String diagnostic = '';

  void _resetDiagnostics() {
    _framesReceived = 0;
    _framesProcessed = 0;
    _consecutiveFailures = 0;
    _lastFrameError = '';
    diagnostic = '';
  }

  void _frameFailed(String reason) {
    _lastFrameError = reason;
    _consecutiveFailures++;
    debugPrint('Quadro não processado: $reason');
    // Android: NV21 não funcionou neste aparelho → tenta YUV_420 convertido aqui.
    if (Platform.isAndroid && _androidFormat == ImageFormatGroup.nv21 && _consecutiveFailures >= 12) {
      _androidFormat = ImageFormatGroup.yuv420;
      _restartCamera();
    }
  }

  /// Verifica a cada segundo se o detector está respondendo.
  void _checkHealth() {
    if (state != EngineState.running || _restarting) return;
    final elapsed = _clock.elapsedMilliseconds - _runningSince;
    // Android: em alguns aparelhos (ex.: Xiaomi/Poco) a conversão para NV21 falha
    // dentro do plugin e nenhum quadro chega. Após 3 s sem quadros, troca para YUV_420.
    if (Platform.isAndroid &&
        _androidFormat == ImageFormatGroup.nv21 &&
        _framesProcessed == 0 &&
        _framesReceived == 0 &&
        elapsed > 3000) {
      _androidFormat = ImageFormatGroup.yuv420;
      _restartCamera();
      return;
    }
    String text = '';
    if (_framesProcessed == 0 && elapsed > 4000) {
      text = _framesReceived == 0
          ? 'A câmera ligou, mas não está enviando imagens para análise.'
          : 'O detector não conseguiu analisar as imagens ($_framesReceived recebidas'
              '${Platform.isAndroid ? ', formato ${_androidFormat.name}' : ''}). '
              '${_lastFrameError.isEmpty ? '' : 'Erro: $_lastFrameError'}';
    }
    if (text != diagnostic) {
      diagnostic = text;
      if (text.isNotEmpty) guide = const FramingGuide('Detector sem resposta — veja a mensagem abaixo', false);
      _notify();
    }
  }

  Future<void> _restartCamera() async {
    if (_restarting) return;
    _restarting = true;
    final controller = camera;
    camera = null;
    state = EngineState.idle;
    _notify();
    try {
      if (controller != null) {
        try {
          if (controller.value.isStreamingImages) await controller.stopImageStream();
        } catch (_) {}
        await controller.dispose();
      }
    } finally {
      _restarting = false;
    }
    if (!_disposed && _cameraUsers > 0) await start();
  }

  Future<void> start() async {
    if (state == EngineState.loading || state == EngineState.running) return;
    state = EngineState.loading;
    error = '';
    _resetDiagnostics();
    guide = const FramingGuide('Iniciando câmera local...', false);
    _notify();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'Nenhuma câmera encontrada neste dispositivo.');
      }
      _description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _description!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? _androidFormat : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      _detector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          // Probabilidade de sorriso: separa o olho semicerrado do sorriso do olho fechado.
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
        ),
      );
      if (_disposed) {
        await controller.dispose();
        return;
      }
      camera = controller;
      _fpsStart = _clock.elapsedMilliseconds;
      await controller.startImageStream(_onFrame);
      state = EngineState.running;
      _runningSince = _clock.elapsedMilliseconds;
      _watchdog?.cancel();
      _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _checkHealth());
      _notify();
    } on CameraException catch (e) {
      _fail(e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
          ? 'Permissão da câmera negada. Libere o acesso nas configurações do aparelho.'
          : 'Não foi possível abrir a câmera frontal. Verifique se outro app está usando a câmera '
              'e tente novamente.');
      debugPrint('CameraException: ${e.code} ${e.description}');
    } catch (e) {
      _fail('Falha ao iniciar a detecção facial: $e');
    }
  }

  int _cameraUsers = 0;

  /// Telas que usam a câmera chamam [acquireCamera] ao abrir e [releaseCamera]
  /// ao fechar; a câmera só desliga quando nenhuma tela precisa mais dela.
  void acquireCamera() {
    _cameraUsers++;
    if (state == EngineState.idle || state == EngineState.error) start();
  }

  void releaseCamera() {
    _cameraUsers = _cameraUsers > 0 ? _cameraUsers - 1 : 0;
    if (_cameraUsers == 0) stop();
  }

  bool get isMonitoring => calibrationStep == null && state == EngineState.running;

  Future<void> stop() async {
    await endSession();
    _watchdog?.cancel();
    _watchdog = null;
    final controller = camera;
    camera = null;
    state = EngineState.idle;
    overlay = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) await controller.stopImageStream();
      } catch (_) {}
      await controller.dispose();
    }
    _notify();
  }

  void _fail(String message) {
    state = EngineState.error;
    error = message;
    _notify();
  }

  // ------------------------------------------------------------------ calibração
  /// Inicia uma etapa de calibração. Com [paused], a câmera continua ativa mas
  /// as amostras só começam em [resumeCalibration] (ex.: após a contagem 3‑2‑1).
  void beginCalibration(int step, {bool paused = false}) {
    endSession();
    calibrationStep = step;
    calibrationProgress = 0;
    calibrationPaused = paused;
    _sampler.reset();
    _notify();
  }

  /// `true` enquanto a etapa espera a contagem regressiva terminar.
  bool calibrationPaused = false;

  void resumeCalibration() {
    calibrationPaused = false;
    _sampler.reset();
    calibrationProgress = 0;
    _notify();
  }

  AudioPlayer? _cuePlayer;

  /// Sons curtos da calibração: `tick` (contagem) e `ok` (etapa concluída).
  /// Tocam mesmo com o alerta sonoro desligado, porque guiam o usuário de olhos fechados.
  Future<void> playCue(String name, {bool vibrate = false}) async {
    try {
      _cuePlayer ??= await _createPlayer();
      await _cuePlayer!.stop();
      await _cuePlayer!.play(AssetSource('sounds/$name.wav'), volume: 1);
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
    if (vibrate) {
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(pattern: [0, 120, 80, 220]);
        } else {
          HapticFeedback.mediumImpact();
        }
      } catch (_) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  void beginMonitoring() {
    calibrationStep = null;
    engine.reset();
    final hp = thresholds.headPitch, hr = thresholds.headRoll;
    if (hp != null && hr != null) engine.setHeadBaseline(hp, hr, thresholds.headYaw);
    earHistory.clear();
    marHistory.clear();
    perclosHistory.clear();
    _notify();
  }

  void setSoundEnabled(bool value) {
    soundEnabled = value;
    saveSettings();
  }

  void setVibrationEnabled(bool value) {
    vibrationEnabled = value;
    saveSettings();
  }

  /// Carrega as preferências salvas (chamado ao abrir o app).
  Future<void> loadPreferences() async {
    final stored = await settingsStore?.load();
    if (stored != null) {
      soundEnabled = stored.sound;
      vibrationEnabled = stored.vibration;
      stored.applyTo(settings);
    }
    await loadSavedCalibration();
    _notify();
  }

  /// Só avisa a interface (ex.: enquanto um controle deslizante é arrastado).
  void refresh() => _notify();

  /// Salva as preferências e avisa a interface.
  Future<void> saveSettings() async {
    _notify();
    await settingsStore?.save(sound: soundEnabled, vibration: vibrationEnabled, detection: settings);
  }

  /// Restaura os ajustes de detecção, som e vibração para o padrão.
  Future<void> resetSettings() async {
    settings.reset();
    soundEnabled = true;
    vibrationEnabled = true;
    await saveSettings();
  }

  /// Ajuste manual dos limiares (tela de Configurações). Fica salvo como calibração.
  Future<void> updateThresholds({double? ear, double? mar, double? marNeutral}) async {
    if (ear != null) thresholds.ear = ear;
    if (mar != null) thresholds.mar = mar;
    if (marNeutral != null) thresholds.marNeutral = marNeutral;
    _notify();
    await saveCalibration();
  }

  /// Volta aos limiares padrão e apaga a calibração salva.
  Future<void> clearCalibration() async {
    resetCalibration();
    await calibrationStore?.clear();
    _notify();
  }

  /// Toca o som e a vibração de alerta (também usado nos botões de teste).
  /// [intense] = sirene + vibração longa (alerta progressivo).
  Future<void> playAlertFeedback({bool force = false, bool intense = false}) async {
    if (soundEnabled || force) {
      try {
        _player ??= await _createPlayer();
        await _player!.stop();
        await _player!.play(AssetSource(intense ? 'sounds/sirene.wav' : 'sounds/alerta.wav'), volume: 1);
      } catch (e) {
        SystemSound.play(SystemSoundType.alert);
      }
    }
    if (vibrationEnabled || force) {
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(
            pattern: intense ? [0, 600, 120, 600] : [0, 350],
            intensities: intense ? [0, 255, 0, 255] : [0, 200],
          );
        } else {
          HapticFeedback.heavyImpact();
        }
      } catch (_) {
        HapticFeedback.vibrate();
      }
    }
  }

  /// Toca no canal de ALARME (Android) e mesmo com o iPhone no silencioso,
  /// para o alerta ser ouvido com a música do carro tocando.
  Future<AudioPlayer> _createPlayer() async {
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    ));
    return player;
  }

  void resetCalibration() {
    thresholds.reset();
    engine.reset();
  }

  /// Salva os limiares atuais para as próximas aberturas do app.
  Future<void> saveCalibration() async => calibrationStore?.save(thresholds);

  /// Carrega a calibração salva. Retorna `true` se havia uma.
  Future<bool> loadSavedCalibration() async {
    final saved = await calibrationStore?.load();
    if (saved == null) return false;
    thresholds.restore(
      lowEyeConfidence: saved.lowEyeConfidence,
      eyeSeparation: saved.eyeSeparation,
      eyeProbThreshold: saved.eyeProbThreshold,
      ear: saved.ear,
      mar: saved.mar,
      marNeutral: saved.marNeutral,
      headPitch: saved.headPitch,
      headRoll: saved.headRoll,
      headYaw: saved.headYaw,
    );
    engine.reset();
    return true;
  }

  /// Encerra a sessão em andamento e grava no banco (se durou o suficiente).
  Future<void> endSession() async {
    final recorder = _recorder;
    _recorder = null;
    if (recorder == null || recorder.duration < minSessionDuration) return;
    final record = recorder.finish();
    try {
      await database?.insertSession(record);
      lastSavedSession = record;
      _notify();
    } catch (e) {
      debugPrint('Falha ao gravar sessão: $e');
    }
  }

  // ------------------------------------------------------------------ quadros
  Future<void> _onFrame(CameraImage image) async {
    _framesReceived++;
    if (_busy || _detector == null || _description == null || _restarting) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) {
        _frameFailed('formato ${image.format.group.name} (${image.format.raw}), '
            '${image.planes.length} plano(s), ${image.width}x${image.height}');
        return;
      }
      // Proteção: se o detector travar, libera para o próximo quadro.
      final faces = await _detector!.processImage(input).timeout(const Duration(seconds: 3));
      if (_disposed) return;
      _consecutiveFailures = 0;
      _framesProcessed++;
      if (diagnostic.isNotEmpty) diagnostic = '';
      final orientation = camera?.value.deviceOrientation;
      if (orientation != null) _trackRotationFix(faces.isNotEmpty, orientation);
      final now = _clock.elapsedMilliseconds + 1;
      _handleFaces(faces, input.metadata!, now);
      _fpsFrames++;
      if (now - _fpsStart >= 1000) {
        fps = _fpsFrames * 1000 / (now - _fpsStart);
        _fpsFrames = 0;
        _fpsStart = now;
      }
      _notify();
    } on TimeoutException {
      _frameFailed('o detector demorou mais de 3 s para responder');
    } catch (e) {
      _frameFailed(e.toString().split('\n').first);
    } finally {
      _busy = false;
    }
  }

  void _handleFaces(List<Face> faces, InputImageMetadata meta, int now) {
    final rotated = meta.rotation == InputImageRotation.rotation90deg ||
        meta.rotation == InputImageRotation.rotation270deg;
    final imageSize = rotated ? Size(meta.size.height, meta.size.width) : meta.size;

    if (faces.isEmpty) {
      overlay = null;
      guide = const FramingGuide('Rosto não detectado — enquadre-se na câmera', false);
      if (calibrationStep == null) _applyMonitoring(engine.noFace(now), now);
      return;
    }
    // Rosto mais próximo (maior caixa).
    final face = faces.reduce((a, b) =>
        a.boundingBox.width * a.boundingBox.height >= b.boundingBox.width * b.boundingBox.height ? a : b);

    List<Pt> contour(FaceContourType type) =>
        face.contours[type]?.points.map((p) => Pt(p.x.toDouble(), p.y.toDouble())).toList() ?? const [];

    final leftEye = contour(FaceContourType.leftEye);
    final rightEye = contour(FaceContourType.rightEye);
    final upperLipTop = contour(FaceContourType.upperLipTop);
    final upperLipBottom = contour(FaceContourType.upperLipBottom);
    final lowerLipTop = contour(FaceContourType.lowerLipTop);
    final lowerLipBottom = contour(FaceContourType.lowerLipBottom);

    final all = <Pt>[
      for (final c in face.contours.values)
        if (c != null) ...c.points.map((p) => Pt(p.x.toDouble(), p.y.toDouble())),
    ];
    overlay = FaceOverlayData(
      imageSize: imageSize,
      box: face.boundingBox,
      allPoints: all,
      rings: [leftEye, rightEye, [...upperLipTop, ...lowerLipBottom]],
    );
    guide = _framing(face.boundingBox, imageSize, face.headEulerAngleX, face.headEulerAngleY);

    final leftEar = eyeAspectRatio(leftEye);
    final rightEar = eyeAspectRatio(rightEye);
    final rawMar = mouthAspectRatio(
      upperLipTop: upperLipTop,
      upperLipBottom: upperLipBottom,
      lowerLipTop: lowerLipTop,
    );
    if (leftEar == null || rightEar == null || rawMar == null) return;

    final smooth = engine.smooth((leftEar + rightEar) / 2, rawMar);

    final pitch = face.headEulerAngleX;
    final roll = face.headEulerAngleZ;
    final yaw = face.headEulerAngleY;
    // Probabilidade de olho aberto (média dos dois olhos), do classificador do ML Kit.
    final probs = [face.leftEyeOpenProbability, face.rightEyeOpenProbability].whereType<double>().toList();
    final eyeProb = probs.isEmpty ? null : probs.reduce((a, b) => a + b) / probs.length;

    final step = calibrationStep;
    if (step != null) {
      if (calibrationPaused) {
        metrics = FatigueMetrics(ear: smooth.ear, mar: smooth.mar);
        return;
      }
      final finished = _sampler.add(smooth.ear, smooth.mar, pitch: pitch, roll: roll, yaw: yaw, eyeProb: eyeProb);
      calibrationProgress = _sampler.progress;
      if (finished) {
        thresholds.applyCalibration(step, _sampler.medianEar, _sampler.medianMar, medianProb: _sampler.medianProb);
        // Etapa "olhos abertos": guarda a posição normal da cabeça.
        final p = _sampler.medianPitch, r = _sampler.medianRoll;
        if (step == 0 && p != null && r != null) {
          final y = _sampler.medianYaw;
          engine.setHeadBaseline(p, r, y);
          thresholds.headPitch = p;
          thresholds.headRoll = r;
          thresholds.headYaw = y;
        }
      }
      metrics = FatigueMetrics(ear: smooth.ear, mar: smooth.mar);
      return;
    }

    _applyMonitoring(
      engine.process(smooth.ear, smooth.mar, now,
          pitch: pitch, roll: roll, yaw: yaw, smile: face.smilingProbability, eyeProb: eyeProb),
      now,
    );
  }

  /// Atualiza status, histórico da sessão, gráficos e alertas a partir das métricas.
  void _applyMonitoring(FatigueMetrics m, int now) {
    metrics = m;
    final result = metrics.classify(engine.settings);
    status = result.status;
    notice = result.notice;

    // Histórico: a sessão começa no primeiro quadro de monitoramento.
    final wallClock = DateTime.now();
    (_recorder ??= SessionRecorder(
      startedAt: wallClock,
      earThreshold: thresholds.ear,
      marThreshold: thresholds.mar,
      calibrated: thresholds.calibrated,
    ))
        .add(metrics, status, wallClock);

    if (now - _lastHistory >= 250) {
      _lastHistory = now;
      _pushHistory(earHistory, m.ear);
      _pushHistory(marHistory, m.mar);
      _pushHistory(perclosHistory, metrics.perclos);
    }

    if (status != FatigueStatus.alert) {
      _ackUntil = 0;
      alertLevel = 0;
      return;
    }
    // Alerta progressivo: depois de alguns segundos em alerta, fica mais intenso.
    alertLevel = settings.escalatingAlert && m.alertSinceMs >= escalateAfterMs ? 2 : 1;
    final interval = alertLevel == 2 ? 750 : 1500;
    if (!alertAcknowledged(now) && now - _lastAlertFeedback >= interval) {
      _lastAlertFeedback = now;
      playAlertFeedback(intense: alertLevel == 2);
    }
  }

  /// 1 = alerta normal; 2 = alerta intensificado (sirene + vibração longa).
  int alertLevel = 0;
  int _ackUntil = 0;

  /// O motorista tocou em "Estou acordado": silencia e esconde a tela cheia por 10 s.
  bool alertAcknowledged([int? now]) => (now ?? _clock.elapsedMilliseconds + 1) < _ackUntil;

  void acknowledgeAlert() {
    _ackUntil = _clock.elapsedMilliseconds + 10000;
    _player?.stop();
    Vibration.cancel();
    _notify();
  }

  /// Mostra o alerta em tela cheia no painel?
  bool get showFullScreenAlert =>
      status == FatigueStatus.alert && settings.fullScreenAlert && calibrationStep == null && !alertAcknowledged();

  void _pushHistory(List<double> list, double value) {
    list.add(value);
    if (list.length > 24) list.removeAt(0);
  }

  /// [pitch] e [yaw] = ângulos do rosto em relação à câmera (graus, ML Kit).
  FramingGuide _framing(Rect box, Size image, double? pitch, double? yaw) {
    final faceWidth = box.width / image.width;
    final cx = box.center.dx / image.width;
    final cy = box.center.dy / image.height;
    final centered = (cx - 0.5).abs() <= 0.16 && (cy - 0.5).abs() <= 0.18;
    if (faceWidth < 0.25) return const FramingGuide('Aproxime-se da câmera', false);
    if (faceWidth > 0.85) return const FramingGuide('Afaste-se um pouco da câmera', false);
    if (!centered) return const FramingGuide('Centralize o rosto no quadro', false);
    // Celular visto muito de baixo/cima ou de lado: os olhos aparecem achatados.
    if (pitch != null && pitch > cameraPitchWarnDeg) {
      return const FramingGuide('Celular muito abaixo do rosto: suba-o se puder', false);
    }
    if (pitch != null && pitch < -cameraPitchWarnDeg) {
      return const FramingGuide('Celular muito acima do rosto: baixe-o se puder', false);
    }
    if (yaw != null && yaw.abs() > cameraYawWarnDeg) {
      return const FramingGuide('Celular muito de lado: vire-o para o rosto', false);
    }
    return const FramingGuide('Posicionamento ideal', true);
  }

  // ------------------------------------------------------------------ conversão
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Correção extra de rotação (graus) usada só com o celular deitado. Cada
  /// aparelho entrega a imagem num ângulo diferente; se o rosto some por vários
  /// quadros em paisagem, testamos 0°, 90°, 180° e 270° até reencontrá-lo.
  int _rotationFix = 0;
  int _framesWithoutFace = 0;
  DeviceOrientation? _lastOrientation;

  void _trackRotationFix(bool found, DeviceOrientation orientation) {
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      _rotationFix = 0;
      _framesWithoutFace = 0;
    }
    if (found || orientation == DeviceOrientation.portraitUp) {
      _framesWithoutFace = 0;
      return;
    }
    if (++_framesWithoutFace >= 20) {
      _framesWithoutFace = 0;
      _rotationFix = (_rotationFix + 90) % 360;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final controller = camera;
    final description = _description;
    if (controller == null || description == null) return null;

    final sensor = description.sensorOrientation;
    final orientation = controller.value.deviceOrientation;
    final portrait = orientation == DeviceOrientation.portraitUp;
    int degrees;
    if (Platform.isIOS && portrait) {
      degrees = sensor;
    } else {
      final device = _orientations[orientation];
      if (device == null) return null;
      degrees = description.lensDirection == CameraLensDirection.front
          ? (sensor + device) % 360
          : (sensor - device + 360) % 360;
    }
    if (!portrait) degrees = (degrees + _rotationFix) % 360;
    final rotation = InputImageRotationValue.fromRawValue(degrees);
    if (rotation == null) return null;

    if (image.planes.isEmpty) return null;
    final size = Size(image.width.toDouble(), image.height.toDouble());

    if (Platform.isAndroid) {
      // YUV_420 em 3 planos (fallback, ou aparelhos que ignoram o pedido de NV21):
      // converte para NV21, o formato que o ML Kit aceita.
      if (image.planes.length >= 3) {
        return InputImage.fromBytes(
          bytes: yuv420ToNv21(image.width, image.height, [
            for (final p in image.planes.take(3)) YuvPlane(p.bytes, p.bytesPerRow, p.bytesPerPixel ?? 1),
          ]),
          metadata: InputImageMetadata(
              size: size, rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: image.width),
        );
      }
      final plane = image.planes.first;
      final needed = image.width * image.height * 3 ~/ 2;
      if (plane.bytes.length < needed) return null;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
            size: size, rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: image.width),
      );
    }

    // iOS: BGRA8888 em um único plano.
    final format = InputImageFormatValue.fromRawValue(image.format.raw is int ? image.format.raw as int : -1) ??
        InputImageFormat.bgra8888;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(size: size, rotation: rotation, format: format, bytesPerRow: plane.bytesPerRow),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    endSession();
    _disposed = true;
    final controller = camera;
    camera = null;
    controller?.dispose();
    _detector?.close();
    _player?.dispose();
    _cuePlayer?.dispose();
    super.dispose();
  }
}

/// Converte YUV_420_888 (3 planos, com row/pixel stride) para NV21
/// (Y seguido de V e U intercalados), formato aceito pelo ML Kit no Android.
class YuvPlane {
  const YuvPlane(this.bytes, this.rowStride, this.pixelStride);
  final Uint8List bytes;
  final int rowStride;
  final int pixelStride;
}

Uint8List yuv420ToNv21(int width, int height, List<YuvPlane> planes) {
  final ySize = width * height;
  final out = Uint8List(ySize + 2 * ((width + 1) ~/ 2) * ((height + 1) ~/ 2));
  final y = planes[0];
  if (y.rowStride == width) {
    out.setRange(0, ySize, y.bytes);
  } else {
    for (var row = 0; row < height; row++) {
      out.setRange(row * width, row * width + width, y.bytes, row * y.rowStride);
    }
  }
  final u = planes[1], v = planes[2];
  final uPixel = u.pixelStride, vPixel = v.pixelStride;
  var i = ySize;
  for (var row = 0; row < height ~/ 2; row++) {
    final uRow = row * u.rowStride, vRow = row * v.rowStride;
    for (var col = 0; col < width ~/ 2; col++) {
      final vi = vRow + col * vPixel, ui = uRow + col * uPixel;
      out[i++] = vi < v.bytes.length ? v.bytes[vi] : 128;
      out[i++] = ui < u.bytes.length ? u.bytes[ui] : 128;
    }
  }
  return out;
}
