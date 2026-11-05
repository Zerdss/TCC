import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/vision_controller.dart';
import '../widgets/common.dart';
import 'calibration_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.vision});

  final VisionController vision;

  void _start(BuildContext context) {
    vision.resetCalibration();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalibrationScreen(vision: vision)));
  }

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
