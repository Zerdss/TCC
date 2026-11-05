import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

class ExplanationScreen extends StatelessWidget {
  const ExplanationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const formulas = [
      ('EAR', '(|p2−p6| + |p3−p5|)\n÷ (2·|p1−p4|)'),
      ('MAR', 'abertura interna da boca\n÷ largura da boca'),
      ('PERCLOS', 'tempo de olhos fechados\n÷ janela de 60 s'),
    ];
    const steps = [
      ('01', 'Captura de imagem', 'A câmera frontal fornece quadros ao app. O vídeo nunca deixa este aparelho.',
          Icons.photo_camera_outlined),
      ('02', 'Detecção facial', 'O Google ML Kit localiza o rosto e devolve contornos de olhos, lábios e face '
          '(mais de 130 pontos) inteiramente no dispositivo.', Icons.face_retouching_natural),
      ('03', 'Métricas', 'EAR mede os olhos; MAR mede a boca; PERCLOS resume o tempo de olhos fechados. '
          'Os valores são suavizados por média móvel.', Icons.calculate_outlined),
      ('04', 'Classificação e alerta', 'Limiares calibrados, regras temporais (piscada × fechamento longo, '
          'bocejo sustentado) e histerese classificam o estado em NORMAL, ATENÇÃO ou ALERTA e acionam som '
          'e vibração.', Icons.notifications_active_outlined),
    ];
    return AppPage(
      children: [
        const Text('ETAPA 04 / 04 • FUNDAMENTOS', style: AppText.kicker),
        const SizedBox(height: 8),
        const Text('Como o sistema funciona', style: AppText.h2),
        const SizedBox(height: 9),
        const Text('Uma leitura didática do pipeline de visão computacional usado no protótipo.',
            style: AppText.body),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (code, text) in formulas)
              SizedBox(
                width: 160,
                child: Panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(code,
                          style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.panel2,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.amber),
                    ),
                    child: Text(steps[i].$1,
                        style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 11)),
                  ),
                  if (i < steps.length - 1) Expanded(child: Container(width: 1, color: AppColors.line)),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(steps[i].$4, size: 19, color: AppColors.amber),
                          const SizedBox(width: 8),
                          Expanded(child: Text(steps[i].$2, style: AppText.cardTitle)),
                        ]),
                        const SizedBox(height: 5),
                        Text(steps[i].$3, style: AppText.body),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'Voltar ao painel',
          secondary: true,
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
