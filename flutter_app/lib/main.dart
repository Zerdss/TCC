import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'screens/home_screen.dart';
import 'theme.dart';
import 'vision/vision_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A pré‑visualização e o mapeamento dos landmarks assumem orientação retrato.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FatigueGuardApp());
}

class FatigueGuardApp extends StatefulWidget {
  const FatigueGuardApp({super.key});

  @override
  State<FatigueGuardApp> createState() => _FatigueGuardAppState();
}

class _FatigueGuardAppState extends State<FatigueGuardApp> with WidgetsBindingObserver {
  final vision = VisionController();
  bool _resumeCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vision.addListener(_syncWakelock);
  }

  // Mantém a tela ligada enquanto a câmera estiver monitorando.
  void _syncWakelock() {
    WakelockPlus.toggle(enable: vision.state == EngineState.running);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (vision.camera != null) {
        _resumeCamera = true;
        vision.stop();
      }
    } else if (state == AppLifecycleState.resumed && _resumeCamera) {
      _resumeCamera = false;
      vision.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vision.removeListener(_syncWakelock);
    vision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fatigue Guard — Detecção de Sonolência',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(vision: vision),
    );
  }
}
