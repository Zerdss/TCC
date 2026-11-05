import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

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
  VisionController() : engine = FatigueEngine(Thresholds());

  final FatigueEngine engine;
  Thresholds get thresholds => engine.thresholds;

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

  Future<void> start() async {
    if (state == EngineState.loading || state == EngineState.running) return;
    state = EngineState.loading;
    error = '';
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
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      _detector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableClassification: false,
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
      _notify();
    } on CameraException catch (e) {
      _fail(e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
          ? 'Permissão da câmera negada. Libere o acesso nas configurações do aparelho.'
          : 'Erro ao acessar a câmera: ${e.description ?? e.code}');
    } catch (e) {
      _fail('Falha ao iniciar a detecção facial: $e');
    }
  }

  Future<void> stop() async {
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
  void beginCalibration(int step) {
    calibrationStep = step;
    calibrationProgress = 0;
    _sampler.reset();
    _notify();
  }

  void beginMonitoring() {
    calibrationStep = null;
    engine.reset();
    earHistory.clear();
    marHistory.clear();
    perclosHistory.clear();
    _notify();
  }

  void setSoundEnabled(bool value) {
    soundEnabled = value;
    _notify();
  }

  void setVibrationEnabled(bool value) {
    vibrationEnabled = value;
    _notify();
  }

  void resetCalibration() {
    thresholds.reset();
    engine.reset();
  }

  // ------------------------------------------------------------------ quadros
  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _detector == null || _description == null) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (_disposed) return;
      final now = _clock.elapsedMilliseconds + 1;
      _handleFaces(faces, input.metadata!, now);
      _fpsFrames++;
      if (now - _fpsStart >= 1000) {
        fps = _fpsFrames * 1000 / (now - _fpsStart);
        _fpsFrames = 0;
        _fpsStart = now;
      }
      _notify();
    } catch (e) {
      debugPrint('Erro no processamento do quadro: $e');
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
    guide = _framing(face.boundingBox, imageSize);

    final leftEar = eyeAspectRatio(leftEye);
    final rightEar = eyeAspectRatio(rightEye);
    final rawMar = mouthAspectRatio(
      upperLipTop: upperLipTop,
      upperLipBottom: upperLipBottom,
      lowerLipTop: lowerLipTop,
    );
    if (leftEar == null || rightEar == null || rawMar == null) return;

    final smooth = engine.smooth((leftEar + rightEar) / 2, rawMar);

    final step = calibrationStep;
    if (step != null) {
      final finished = _sampler.add(smooth.ear, smooth.mar);
      calibrationProgress = _sampler.progress;
      if (finished) thresholds.applyCalibration(step, _sampler.medianEar, _sampler.medianMar);
      metrics = FatigueMetrics(ear: smooth.ear, mar: smooth.mar);
      return;
    }

    metrics = engine.process(smooth.ear, smooth.mar, now);
    final result = metrics.classify();
    status = result.status;
    notice = result.notice;

    if (now - _lastHistory >= 250) {
      _lastHistory = now;
      _pushHistory(earHistory, smooth.ear);
      _pushHistory(marHistory, smooth.mar);
      _pushHistory(perclosHistory, metrics.perclos);
    }
    if (status == FatigueStatus.alert && now - _lastAlertFeedback >= 1200) {
      _lastAlertFeedback = now;
      if (soundEnabled) SystemSound.play(SystemSoundType.alert);
      if (vibrationEnabled) HapticFeedback.vibrate();
    }
  }

  void _pushHistory(List<double> list, double value) {
    list.add(value);
    if (list.length > 24) list.removeAt(0);
  }

  FramingGuide _framing(Rect box, Size image) {
    final faceWidth = box.width / image.width;
    final cx = box.center.dx / image.width;
    final cy = box.center.dy / image.height;
    final centered = (cx - 0.5).abs() <= 0.16 && (cy - 0.5).abs() <= 0.18;
    if (faceWidth < 0.25) return const FramingGuide('Aproxime-se da câmera', false);
    if (faceWidth > 0.85) return const FramingGuide('Afaste-se um pouco da câmera', false);
    if (!centered) return const FramingGuide('Centralize o rosto no quadro', false);
    return const FramingGuide('Posicionamento ideal', true);
  }

  // ------------------------------------------------------------------ conversão
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _toInputImage(CameraImage image) {
    final controller = camera;
    final description = _description;
    if (controller == null || description == null) return null;

    final sensor = description.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else {
      final device = _orientations[controller.value.deviceOrientation];
      if (device == null) return null;
      final compensated = description.lensDirection == CameraLensDirection.front
          ? (sensor + device) % 360
          : (sensor - device + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(compensated);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    // NV21 (Android) e BGRA8888 (iOS) chegam em um único plano contíguo.
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = camera;
    camera = null;
    controller?.dispose();
    _detector?.close();
    super.dispose();
  }
}
