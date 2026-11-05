import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/vision_controller.dart';
import '../widgets/common.dart';
import '../data/calibration_store.dart';
import 'calibration_screen.dart';
import 'demo_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.vision});

  final VisionController vision;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SavedCalibration? _saved;

  VisionController get vision => widget.vision;

  @override
  void initState() {
    super.initState();
    _refreshSaved();
  }

  Future<void> _refreshSaved() async {
    final saved = await vision.calibrationStore?.load();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _start(BuildContext context) async {
    vision.resetCalibration();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalibrationScreen(vision: vision)));
    _refreshSaved();
  }

  Future<void> _useSaved(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (!await vision.loadSavedCalibration()) return;
    vision.beginMonitoring();
    await navigator.push(MaterialPageRoute(builder: (_) => DemoScreen(vision: vision)));
    _refreshSaved();
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    const metricsInfo = [
      (Icons.remove_red_eye_outlined, 'EAR', 'Razão de abertura dos olhos'),
      (Icons.show_chart, 'PERCLOS', 'Percentual de tempo com olhos fechados nos últimos 60 segundos'),
      (Icons.sentiment_satisfied_alt_outlined, 'MAR', 'Razão de abertura da boca'),
    ];
    return AppPage(
      children: [
        const SizedBox(height: 12),
        const Row(children: [
          StatusDot(),
          SizedBox(width: 8),
          Text('PROTÓTIPO ACADÊMICO • TCC', style: AppText.section),
        ]),
        const SizedBox(height: 18),
        const Text('Detecção de\nSonolência ao Volante', style: AppText.h1),
        const SizedBox(height: 18),
        const Text(
          'Uma demonstração interativa de como a visão computacional pode reconhecer sinais de fadiga '
          'em tempo real — antes que o risco vire acidente.',
          style: AppText.lead,
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          key: const Key('button-iniciar'),
          label: 'Iniciar Demonstração',
          icon: Icons.photo_camera_outlined,
          onPressed: () => _start(context),
        ),
        if (_saved != null) ...[
          const SizedBox(height: 10),
          PrimaryButton(
            key: const Key('button-calibracao-salva'),
            label: 'Usar calibração salva (${_fmt(_saved!.savedAt)})',
            icon: Icons.bookmark_added_outlined,
            secondary: true,
            onPressed: () => _useSaved(context),
          ),
        ],
        if (vision.database != null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            key: const Key('button-historico'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => HistoryScreen(database: vision.database!))),
            icon: const Icon(Icons.history, color: AppColors.amber),
            label: const Text('Histórico de sessões',
                style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800)),
          ),
        ],
        const SizedBox(height: 36),
        const Panel(
          color: Color(0xFF0E211C),
          border: Color(0xFF19513F),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.green, size: 24),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Processamento 100% local', style: AppText.cardTitle),
                    SizedBox(height: 5),
                    Text(
                      'A câmera é usada apenas no próprio aparelho. Nenhuma imagem é armazenada ou enviada.',
                      style: AppText.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        const Text('MÉTRICAS MONITORADAS', style: AppText.section),
        const SizedBox(height: 12),
        for (final (icon, title, desc) in metricsInfo) ...[
          Panel(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(icon, color: AppColors.amber, size: 23),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.cardTitle),
                      const SizedBox(height: 4),
                      Text(desc, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 20),
        const Divider(color: AppColors.line),
        const SizedBox(height: 10),
        const Row(children: [
          Icon(Icons.science_outlined, color: AppColors.muted, size: 16),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'Demonstração conceitual • O protótipo embarcado roda separadamente em Raspberry Pi.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        ]),
      ],
    );
  }
}
