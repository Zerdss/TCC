import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'data/calibration_store.dart';
import 'data/session_database.dart';
import 'data/settings_store.dart';
import 'platform/background_bubble.dart';
import 'platform/floating_window.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'vision/fatigue_engine.dart';
import 'vision/vision_controller.dart';
import 'widgets/common.dart';
import 'widgets/floating_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Começa em retrato; o modo deitado é liberado nas Configurações.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  SessionDatabase? database;
  try {
    database = await SessionDatabase.open();
  } catch (e) {
    debugPrint('Histórico indisponível: $e');
  }
  runApp(FatigueGuardApp(database: database));
}

class FatigueGuardApp extends StatefulWidget {
  const FatigueGuardApp({super.key, this.database});

  final SessionDatabase? database;

  @override
  State<FatigueGuardApp> createState() => _FatigueGuardAppState();
}

class _FatigueGuardAppState extends State<FatigueGuardApp> with WidgetsBindingObserver {
  late final vision = VisionController(
    database: widget.database,
    calibrationStore: CalibrationStore(),
    settingsStore: SettingsStore(),
  );
  bool _resumeCamera = false;
  bool? _landscape;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vision.addListener(_syncOrientation);
    vision.addListener(_syncFloating);
    vision.loadPreferences();
    _keepScreenOn();
    floating.onAcknowledge = vision.acknowledgeAlert;
    floating.addListener(_onFloating);
    floating.init();
    bubble.onFrame = vision.handleBackgroundFrame;
    bubble.onStarted = () => vision.startBackgroundFeed();
    bubble.addListener(_onBubble);
    bubble.init();
    vision.addListener(_syncBubble);
    _refreshCanDraw();
  }

  BackgroundBubble get bubble => BackgroundBubble.instance;
  bool _canDraw = false;
  Timer? _bubbleTimer;

  Future<void> _refreshCanDraw() async {
    final v = await bubble.canDraw();
    if (v == _canDraw) return;
    _canDraw = v;
    _autoFloating = null;
    _syncFloating();
  }

  /// Ponto da bolinha: 0 verde, 1 amarelo, 2 vermelho; câmera riscada se a
  /// detecção parou (sem quadros ou sem rosto).
  void _syncBubble() {
    if (!bubble.running) return;
    final s = switch (vision.status) {
      FatigueStatus.normal => 0,
      FatigueStatus.attention => 1,
      FatigueStatus.alert => 2,
    };
    bubble.update(s, vision.faceTracking);
  }

  void _onBubble() {
    _bubbleTimer?.cancel();
    // Mesmo sem quadros novos, atualiza a câmera riscada.
    if (bubble.running) _bubbleTimer = Timer.periodic(const Duration(seconds: 1), (_) => _syncBubble());
    _syncBubble();
  }

  FloatingWindow get floating => FloatingWindow.instance;
  bool? _autoFloating;

  /// Janela flutuante automática só enquanto o painel ao vivo está monitorando.
  void _syncFloating() {
    final want = vision.settings.floatingWindow &&
        vision.isMonitoring &&
        (vision.camera != null || vision.backgroundFeed);
    if (want == _autoFloating) return;
    _autoFloating = want;
    // Com a permissão "Exibir sobre outros apps": bolinha; sem ela, janela flutuante.
    bubble.setAuto(want && _canDraw);
    floating.setAutoEnter(want && !_canDraw);
  }

  void _onFloating() {
    // Na janela flutuante a tela não é do app: sem luz de apoio.
    vision.screenLightAllowed = !floating.active;
    if (mounted) setState(() {});
    _syncFloating();
    // Fechou a janela flutuante (X): o app saiu da tela, então a câmera para.
    final life = WidgetsBinding.instance.lifecycleState;
    if (!floating.active && (life == AppLifecycleState.paused || life == AppLifecycleState.hidden)) {
      didChangeAppLifecycleState(life!);
    }
  }

  // Aplica a opção "Permitir modo deitado" das Configurações.
  void _syncOrientation() {
    final landscape = vision.settings.allowLandscape;
    if (landscape != _landscape) {
      _landscape = landscape;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        if (landscape) ...[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      ]);
    }
  }

  /// Tela sempre ligada enquanto o app está aberto (em qualquer tela, não só com
  /// a câmera). Pedido de novo a cada volta ao app, porque o sistema pode soltar.
  void _keepScreenOn() {
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "inactive" acontece na janela flutuante e na tela dividida (o app continua
    // visível): a câmera segue ligada. Só para quando o app some da tela.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (floating.active) return;
      // Bolinha ligada: a câmera passa para o serviço e o monitoramento continua.
      if (bubble.running) {
        vision.startBackgroundFeed();
        return;
      }
      if (vision.camera != null) {
        _resumeCamera = true;
        vision.stop();
      }
    } else if (state == AppLifecycleState.resumed) {
      _keepScreenOn();
      _refreshCanDraw();
      if (bubble.running || vision.backgroundFeed) {
        _returnFromBubble();
      } else if (_resumeCamera) {
        _resumeCamera = false;
        vision.start();
      }
    }
  }

  /// Voltou ao app: desliga a bolinha, solta a câmera do serviço e religa a do app.
  Future<void> _returnFromBubble() async {
    await bubble.stop();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await vision.stopBackgroundFeed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vision.removeListener(_syncOrientation);
    vision.removeListener(_syncFloating);
    floating.removeListener(_onFloating);
    bubble.removeListener(_onBubble);
    vision.removeListener(_syncBubble);
    _bubbleTimer?.cancel();
    vision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fatigue Guard — Detecção de Sonolência',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Na janela flutuante, mostra só o status (o resto do app fica guardado, sem perder o estado).
      builder: (context, child) => AppScope(
        vision: vision,
        child: Stack(children: [
          Offstage(offstage: floating.active, child: child!),
          if (floating.active) Positioned.fill(child: FloatingView(vision: vision)),
        ]),
      ),
      home: HomeScreen(vision: vision),
    );
  }
}
