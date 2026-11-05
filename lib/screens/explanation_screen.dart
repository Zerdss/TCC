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
    const rules = [
      (Icons.remove_red_eye_outlined, AppColors.blue, 'Piscada × sonolência',
          'Fechamentos de 0,08 a 0,4 s são piscadas normais: entram só na contagem de piscadas/min e não '
              'geram alerta nem PERCLOS. Olhos fechados de forma contínua por 1,2 s (ajustável) disparam o '
              'ALERTA; a partir de ~0,7 s aparece ATENÇÃO.'),
      (Icons.sentiment_very_satisfied_outlined, AppColors.yellow, 'Sorriso e fala',
          'Ao sorrir ou falar os olhos se fecham um pouco. Se a boca está na faixa de "sorriso" (MAR acima '
              'da tolerância calibrada), o olho semicerrado não conta como sonolência — checagem cruzada EAR × MAR.'),
      (Icons.record_voice_over_outlined, AppColors.blue, 'Bocejo sustentado',
          'Só é bocejo se o MAR ficar acima do limiar de forma contínua por 1,8 s. Falar e rir abrem a boca '
              'por pouco tempo e são ignorados (tolerância de 150 ms para falhas de detecção).'),
      (Icons.graphic_eq, AppColors.green, 'Suavização e histerese',
          'EAR e MAR passam por uma média móvel dos últimos quadros para evitar ruído. Depois de um alerta, '
              'o sistema só volta ao NORMAL após 1 s contínuo de olhos abertos e boca neutra.'),
      (Icons.center_focus_strong_outlined, AppColors.amber, 'Calibração pessoal',
          'Limiar EAR = fechado + 28% × (aberto − fechado). Limiar MAR = 72% do bocejo, refinado pelo '
              'sorriso. Tudo fica salvo no aparelho e pode ser ajustado em Configurações.'),
    ];
    return AppPage(
      children: [
        const PageTitle(
          kicker: 'ETAPA 04 / 04 • FUNDAMENTOS',
          title: 'Como o sistema funciona',
          subtitle: 'Uma leitura didática do pipeline de visão computacional usado no protótipo.',
        ),
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
                      Text(code, style: AppText.number.copyWith(color: AppColors.amber, fontSize: 22)),
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
        const Text('REGRAS DE DECISÃO', style: AppText.section),
        const SizedBox(height: 12),
        for (final (icon, color, title, body) in rules) ...[
          Panel(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppText.cardTitle),
                  const SizedBox(height: 4),
                  Text(body, style: AppText.body),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 14),
        PrimaryButton(
          label: 'Voltar',
          secondary: true,
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
