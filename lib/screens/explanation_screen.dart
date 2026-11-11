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
          'Ao sorrir ou falar os olhos se fecham um pouco. Se o detector de sorriso do ML Kit indica sorriso '
              '(inclusive de boca fechada) ou a boca está na faixa de "sorriso" (MAR acima da tolerância '
              'calibrada), o olho semicerrado não conta como sonolência.'),
      (Icons.record_voice_over_outlined, AppColors.blue, 'Bocejo sustentado',
          'Só é bocejo se o MAR ficar acima do limiar de forma contínua por 1,8 s. Falar e rir abrem a boca '
              'por pouco tempo e são ignorados (tolerância de 150 ms para falhas de detecção).'),
      (Icons.airline_seat_flat_angled_outlined, AppColors.red, 'Cabeça caindo',
          'O detector informa os ângulos da cabeça. Se ela baixa 20° (ajustável) em relação à posição '
              'normal medida na calibração — ou tomba mais de 30° para o lado — por 1,5 s com os olhos '
              'fechados, é ALERTA: é o "cochilo" típico. Se não dá para ver bem os olhos, o alerta espera o '
              'dobro do tempo (3 s).'),
      (Icons.visibility_outlined, AppColors.blue, 'Movimento normal não é sono',
          'Olhar o retrovisor, o rádio ou o celular não deve disparar o alarme. Com a cabeça virada mais de 25° '
              'para o lado, o olho aparece distorcido e não é medido. Com a cabeça baixa, se os olhos continuam '
              'abertos é "olhando para baixo", e não cochilo; e o olho só conta como fechado se estiver bem mais '
              'fechado que o normal (a pálpebra baixa ao olhar para baixo). Movimentos rápidos da cabeça (mais de '
              '120°/s) pausam a medição. Se o desvio do olhar passa de 2,5 s, o app mostra ATENÇÃO para voltar à estrada.'),
      (Icons.smartphone, AppColors.blue, 'Posição do celular',
          'Na calibração, com você olhando para a estrada, o app mede o ângulo do rosto na câmera e descobre '
              'onde o celular está: de frente (reto), abaixo, acima ou de lado do rosto (ou combinações, como '
              '"abaixo e de lado"). Todos os limites — olhos, boca e cabeça — são medidos nessa posição, então '
              'a cabeça "normal" é a sua posição real, não a de frente. Se o celular está bem abaixo/acima '
              '(25° ou mais) ou bem de lado (30° ou mais), o reforço liga sozinho. Mudou o celular de lugar? '
              'Calibre de novo.'),
      (Icons.shield_outlined, AppColors.yellow, 'Reforço com celular em ângulo ruim',
          'Visto muito de baixo, o olho parece achatado e o EAR fica pouco confiável. Se a calibração mostra '
              'olho aberto e fechado parecidos, o app liga um reforço: a inclinação da cabeça fica mais sensível '
              '(75% do ângulo e 80% do tempo) e o olho fechado passa a ser medido pela probabilidade do ML Kit, '
              'quando ela separa melhor. A boca segue igual. O app também avisa se o celular está muito abaixo, '
              'acima ou de lado.'),
      (Icons.picture_in_picture_alt_outlined, AppColors.blue, 'Junto com o GPS',
          'No Android, ao sair do app durante o monitoramento ele vira uma janela flutuante por cima do GPS e '
              'continua detectando: o status aparece em cores e o alarme toca normalmente. Toque na janela para '
              'ver o botão "Estou acordado" ou voltar ao app. No iPhone o sistema não permite.'),
      (Icons.no_accounts_outlined, AppColors.red, 'Rosto fora da câmera',
          'Se o rosto some por 2 s aparece ATENÇÃO; por 4 s, ALERTA. Cobre a cabeça caída para fora do '
              'quadro e o celular mal posicionado.'),
      (Icons.campaign_outlined, AppColors.accent, 'Alerta progressivo',
          'O alerta começa com bipe, vibração e tela cheia piscando. Se continuar por mais de 4 s, vira '
              'sirene rápida com vibração longa. O botão "Estou acordado" silencia por 10 s.'),
      (Icons.graphic_eq, AppColors.green, 'Suavização e histerese',
          'EAR e MAR passam por uma média móvel dos últimos quadros para evitar ruído. Depois de um alerta, '
              'o sistema só volta ao NORMAL após 1 s contínuo de olhos abertos, boca neutra e cabeça erguida.'),
      (Icons.center_focus_strong_outlined, AppColors.accent, 'Calibração pessoal',
          'Rígida e feita para o SEU rosto (olhos puxados, caídos, um mais fechado que o outro...). Cada quadro '
              'só conta se o rosto estiver enquadrado, parado e na mesma posição da 1ª etapa; piscadas são '
              'descartadas. São 80 quadros válidos por etapa, e cada etapa é analisada: leitura estável, olho '
              'fechado realmente diferente do aberto, bocejo realmente aberto, sorriso identificado. Se não '
              'passar, a etapa é repetida. No fim, o app mostra a análise do rosto e só salva quando você '
              'confirma. Limiar EAR = fechado + 28% × (aberto − fechado); MAR = 72% do bocejo, refinado pelo '
              'sorriso.'),
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
                      Text(code, style: AppText.number.copyWith(color: AppColors.accent, fontSize: 22)),
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
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Text(steps[i].$1,
                        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 11)),
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
                          Icon(steps[i].$4, size: 19, color: AppColors.accent),
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
