import 'package:flutter/material.dart';

import '../platform/floating_window.dart';
import '../theme.dart';
import '../vision/fatigue_engine.dart';
import '../vision/vision_controller.dart';
import '../widgets/common.dart';
import '../widgets/light_mode_selector.dart';
import 'calibration_screen.dart';
import 'history_screen.dart';

/// Configurações: alertas, sorriso/expressões, sensibilidade, tempos e dados.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.vision});

  final VisionController vision;

  Future<void> _confirm(BuildContext context,
      {required String title, required String body, required String action, required Future<void> Function() onOk}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(title, style: AppText.h3),
        content: Text(body, style: AppText.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    if (ok == true) await onOk();
  }

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vision,
      builder: (context, _) {
        final s = vision.settings; // ajustes do modo que está valendo (Dia ou Noite)
        final t = vision.thresholds;
        final night = vision.nightProfile;
        return AppPage(
          showSettings: false,
          children: [
            const PageTitle(
              kicker: 'AJUSTES',
              title: 'Configurações',
              subtitle: 'Personalize alertas, a tolerância ao sorriso e a sensibilidade da detecção. '
                  'Tudo fica salvo apenas neste aparelho.',
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('settings-profile'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (night ? AppColors.blue : AppColors.accent).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (night ? AppColors.blue : AppColors.accent).withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                Icon(night ? Icons.nightlight_outlined : Icons.wb_sunny_outlined,
                    color: night ? AppColors.blue : AppColors.accentDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    night
                        ? 'Você está ajustando o modo Noite. Estes ajustes valem só à noite; os do modo Dia '
                            'continuam como estavam.'
                        : 'Você está ajustando o modo Dia. Para ajustar a noite, escolha "Noite" em Dia e noite — '
                            'a noite tem os seus próprios ajustes.',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // ------------------------------------------------------------ alertas
            const _SectionLabel(icon: Icons.notifications_active_outlined, text: 'ALERTAS'),
            _Card(children: [
              _SwitchRow(
                icon: Icons.volume_up_outlined,
                title: 'Alerta sonoro',
                subtitle: 'Bipe repetido enquanto o alerta de sonolência estiver ativo.',
                value: vision.soundEnabled,
                onChanged: vision.setSoundEnabled,
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.vibration,
                title: 'Vibração',
                subtitle: 'O celular vibra junto com o alerta.',
                value: vision.vibrationEnabled,
                onChanged: vision.setVibrationEnabled,
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.fullscreen_rounded,
                title: 'Alerta em tela cheia',
                subtitle: 'A tela inteira pisca em vermelho com o botão "Estou acordado" '
                    '(silencia por 10 s).',
                value: s.fullScreenAlert,
                onChanged: (v) {
                  s.fullScreenAlert = v;
                  vision.saveSettings();
                },
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.trending_up_rounded,
                title: 'Alerta progressivo',
                subtitle: 'Se o alerta continuar por mais de ${formatSeconds(escalateAfterMs)} s, troca o bipe '
                    'por uma sirene mais rápida e a vibração fica longa e forte.',
                value: s.escalatingAlert,
                onChanged: (v) {
                  s.escalatingAlert = v;
                  vision.saveSettings();
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('button-testar-alerta'),
                      onPressed: () => vision.playAlertFeedback(force: true),
                      icon: const Icon(Icons.play_arrow_rounded, color: AppColors.accent),
                      label: const FittedBox(child: Text('Testar alerta')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => vision.playAlertFeedback(force: true, intense: true),
                      icon: const Icon(Icons.campaign_rounded, color: AppColors.red),
                      label: const FittedBox(child: Text('Testar sirene')),
                    ),
                  ),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Text(
                  'O som toca no canal de alarme do celular (e no iPhone mesmo no modo silencioso). '
                  'Ajuste o volume de alarme do aparelho.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
                ),
              ),
            ]),

            // ------------------------------------------------------------ sorriso
            const _SectionLabel(icon: Icons.sentiment_satisfied_alt_outlined, text: 'SORRISO E EXPRESSÕES'),
            _Card(children: [
              _SwitchRow(
                icon: Icons.emoji_emotions_outlined,
                title: 'Ignorar sorriso e fala',
                subtitle: 'Ao sorrir, rir ou falar os olhos ficam semicerrados. Com esta opção ligada, '
                    'esses momentos não contam como olhos fechados. Usa o detector de sorriso do ML Kit '
                    '(pega também o sorriso de boca fechada) e a abertura da boca (MAR).',
                value: s.smileFilter,
                onChanged: (v) {
                  s.smileFilter = v;
                  vision.saveSettings();
                },
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Tolerância ao sorriso',
                description: 'Abertura de boca (MAR) a partir da qual o rosto é tratado como sorriso/fala. '
                    'Menor = ignora sorrisos mais discretos.',
                valueLabel: t.marNeutral.toStringAsFixed(2),
                value: t.marNeutral,
                min: marNeutralMin,
                max: marNeutralMax,
                divisions: 22,
                enabled: s.smileFilter,
                onChanged: (v) {
                  t.marNeutral = v;
                  vision.refresh();
                },
                onChangeEnd: (v) => vision.updateThresholds(marNeutral: v),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.camera_front_outlined,
                title: 'Recalibrar só o sorriso',
                subtitle: 'Refaz a etapa 04 (sorriso/risada) com a câmera.',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CalibrationScreen(vision: vision, onlyStep: 3),
                )),
              ),
            ]),

            // ------------------------------------------------------------ cabeça e rosto
            const _SectionLabel(icon: Icons.face_retouching_natural, text: 'CABEÇA E ROSTO'),
            _Card(children: [
              _SwitchRow(
                icon: Icons.airline_seat_flat_angled_outlined,
                title: 'Detectar cabeça caindo',
                subtitle: 'Alerta quando a cabeça pende para frente ou para o lado (cochilo), mesmo '
                    'que os olhos não sejam bem vistos.',
                value: s.headEnabled,
                onChanged: (v) {
                  s.headEnabled = v;
                  vision.saveSettings();
                },
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Inclinação para alertar',
                description: 'Quantos graus a cabeça precisa baixar em relação à sua posição normal '
                    '(medida na calibração). Inclinação lateral acima de ${headTiltDeg.round()}° também conta.',
                valueLabel: '${s.headDropDeg.round()}°',
                value: s.headDropDeg,
                min: 10,
                max: 40,
                divisions: 30,
                enabled: s.headEnabled,
                onChanged: (v) {
                  s.headDropDeg = v.roundToDouble();
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Tempo com a cabeça caída',
                description: 'Tempo contínuo com a cabeça inclinada até o ALERTA. '
                    'ATENÇÃO aparece na metade do tempo.',
                valueLabel: '${formatSeconds(s.headAlertMs)} s',
                value: s.headAlertMs.toDouble(),
                min: 800,
                max: 4000,
                divisions: 32,
                enabled: s.headEnabled,
                onChanged: (v) {
                  s.headAlertMs = v.round();
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.no_accounts_outlined,
                title: 'Avisar rosto fora da câmera',
                subtitle: 'Se o rosto some da câmera (cabeça caída, olhando para baixo, celular '
                    'mal posicionado), o app avisa.',
                value: s.faceLostEnabled,
                onChanged: (v) {
                  s.faceLostEnabled = v;
                  vision.saveSettings();
                },
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Tempo sem rosto para alertar',
                description: 'ATENÇÃO aparece na metade do tempo; o ALERTA, ao completar.',
                valueLabel: '${formatSeconds(s.faceLostAlertMs)} s',
                value: s.faceLostAlertMs.toDouble(),
                min: 2000,
                max: 10000,
                divisions: 16,
                enabled: s.faceLostEnabled,
                onChanged: (v) {
                  s.faceLostAlertMs = v.round();
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.shield_outlined,
                title: 'Sempre reforçar cabeça e boca',
                subtitle: 'O reforço liga sozinho quando a calibração mostra os olhos pouco visíveis '
                    'ou o celular muito abaixo, acima ou de lado do rosto: a inclinação da cabeça fica mais '
                    'sensível e o olho fechado também é medido pela probabilidade do ML Kit. Ligue para usar sempre. '
                    'Calibração atual: ${t.eyeSeparation == null ? 'sem medição' : t.lowEyeConfidence ? 'olhos pouco visíveis (reforço automático)' : 'olhos bem visíveis'}'
                    '${t.phonePosition == null ? '' : '; celular ${t.phonePosition!.label.toLowerCase()}${t.phonePosition!.needsReinforcement ? ' (reforço automático)' : ''}'}.',
                value: s.forceReinforced,
                onChanged: (v) {
                  s.forceReinforced = v;
                  vision.saveSettings();
                },
              ),
            ]),

            // ------------------------------------------------------------ tela
            const _SectionLabel(icon: Icons.screen_rotation_outlined, text: 'TELA'),
            _Card(children: [
              _SwitchRow(
                icon: Icons.stay_current_landscape_outlined,
                title: 'Permitir modo deitado',
                subtitle: 'Para usar o celular na horizontal, no suporte do carro. O painel ao vivo '
                    'mostra a câmera e as métricas lado a lado.',
                value: s.allowLandscape,
                onChanged: (v) {
                  s.allowLandscape = v;
                  vision.saveSettings();
                },
              ),
              const Divider(height: 1),
              _SwitchRow(
                icon: Icons.picture_in_picture_alt_outlined,
                title: 'Continuar detectando fora do app',
                subtitle: FloatingWindow.instance.supported
                    ? 'Durante o monitoramento, ao apertar o botão "início" o detector continua funcionando por '
                        'cima de outro app (ex.: GPS): uma bolinha com o ponto verde/amarelo/vermelho e o ícone '
                        'da câmera (riscado com X se a detecção parar). Precisa da permissão "Exibir sobre '
                        'outros apps"; sem ela, usa uma janela flutuante maior. O alarme toca normalmente.'
                    : 'Este aparelho não oferece janela flutuante (no iPhone o sistema não permite a câmera '
                        'em segundo plano). Use a tela dividida, se o aparelho tiver.',
                value: s.floatingWindow,
                onChanged: (v) {
                  s.floatingWindow = v;
                  vision.saveSettings();
                },
              ),
            ]),

            // ------------------------------------------------------------ noite
            const _SectionLabel(icon: Icons.nightlight_outlined, text: 'DIA E NOITE'),
            _Card(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Modo de iluminação', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text(
                    'Dia: como sempre. Noite: a tela do app vira luz de apoio — o brilho sobe devagar, fica alto '
                    'por alguns segundos e desce devagar, sem clarão; com sinal de sono a luz fica acesa até '
                    'normalizar, e a decisão é pela cabeça. Automático: o app liga o modo noite sozinho quando a '
                    'imagem fica escura. Funciona com o app aberto na tela.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  LightModeSelector(vision: vision),
                ]),
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Intervalo da luz de apoio',
                description: 'Tempo entre uma subida de brilho e a próxima.',
                valueLabel: '${s.nightPeriodMs ~/ 1000} s',
                value: s.nightPeriodMs.toDouble(),
                min: 10000,
                max: 60000,
                divisions: 10,
                enabled: s.lightMode != LightMode.day,
                onChanged: (v) {
                  s.nightPeriodMs = v.round();
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Brilho máximo da luz',
                description: 'Mais brilho ilumina melhor o rosto, mas pode incomodar a vista à noite.',
                valueLabel: '${(s.nightMaxBrightness * 100).round()}%',
                value: s.nightMaxBrightness,
                min: 0.3,
                max: 1.0,
                divisions: 7,
                enabled: s.lightMode != LightMode.day,
                onChanged: (v) {
                  s.nightMaxBrightness = v;
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
            ]),

            // ------------------------------------------------------------ sensibilidade
            const _SectionLabel(icon: Icons.tune, text: 'SENSIBILIDADE'),
            _Card(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Row(children: [
                  Icon(t.calibrated ? Icons.verified_outlined : Icons.info_outline,
                      size: 16, color: t.calibrated ? AppColors.green : AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.calibrated ? 'Usando sua calibração pessoal' : 'Usando valores padrão (sem calibração)',
                      style: TextStyle(
                          color: t.calibrated ? AppColors.green : AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
              _SliderRow(
                title: 'Limiar dos olhos (EAR)',
                description: 'Abaixo deste valor o olho é considerado fechado. Maior = mais sensível.',
                valueLabel: t.ear.toStringAsFixed(3),
                value: t.ear,
                min: earMin,
                max: earMax,
                divisions: 36,
                onChanged: (v) {
                  t.ear = v;
                  vision.refresh();
                },
                onChangeEnd: (v) => vision.updateThresholds(ear: v),
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Limiar do bocejo (MAR)',
                description: 'Acima deste valor a boca é considerada aberta de bocejo. Menor = mais sensível.',
                valueLabel: t.mar.toStringAsFixed(2),
                value: t.mar,
                min: marMin,
                max: marMax,
                divisions: 45,
                onChanged: (v) {
                  t.mar = v;
                  vision.refresh();
                },
                onChangeEnd: (v) => vision.updateThresholds(mar: v),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.restart_alt,
                title: 'Refazer calibração completa',
                subtitle: 'Olhos abertos, fechados, bocejo e sorriso.',
                onTap: () {
                  // Fecha Configurações e o painel antigo; a calibração abre um painel novo ao final.
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => CalibrationScreen(vision: vision)),
                    (route) => route.isFirst,
                  );
                },
              ),
            ]),

            // ------------------------------------------------------------ tempos
            const _SectionLabel(icon: Icons.timer_outlined, text: 'TEMPOS DOS ALERTAS'),
            _Card(children: [
              _SliderRow(
                title: 'Olhos fechados para alertar',
                description: 'Tempo contínuo de olhos fechados até o ALERTA. Piscadas (até 0,4 s) '
                    'nunca disparam alerta. ATENÇÃO aparece em ${formatSeconds(s.eyesWarnMs)} s.',
                valueLabel: '${formatSeconds(s.eyesAlertMs)} s',
                value: s.eyesAlertMs.toDouble(),
                min: 800,
                max: 3000,
                divisions: 22,
                onChanged: (v) {
                  s.eyesAlertMs = v.round();
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Bocejo sustentado',
                description: 'Tempo contínuo de boca aberta para contar como bocejo. Fala e risada '
                    'abrem a boca por pouco tempo e ficam abaixo disso.',
                valueLabel: '${formatSeconds(s.yawnAlertMs)} s',
                value: s.yawnAlertMs.toDouble(),
                min: 1000,
                max: 3000,
                divisions: 20,
                onChanged: (v) {
                  s.yawnAlertMs = v.round();
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
              const Divider(height: 1),
              _SliderRow(
                title: 'Piscadas por minuto (atenção)',
                description: 'Piscar demais também é sinal de cansaço. Acima deste número aparece ATENÇÃO.',
                valueLabel: '${s.blinkWarnRate}/min',
                value: s.blinkWarnRate.toDouble(),
                min: 15,
                max: 40,
                divisions: 25,
                onChanged: (v) {
                  s.blinkWarnRate = v.round();
                  vision.refresh();
                },
                onChangeEnd: (_) => vision.saveSettings(),
              ),
            ]),

            // ------------------------------------------------------------ dados
            const _SectionLabel(icon: Icons.shield_outlined, text: 'DADOS E PRIVACIDADE'),
            _Card(children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'A câmera é processada no próprio celular. O app guarda apenas números e horários '
                  '(calibração, ajustes e histórico) — nunca fotos ou vídeos — e nada é enviado para a internet.',
                  style: AppText.body,
                ),
              ),
              if (vision.database != null) ...[
                const Divider(height: 1),
                _ActionRow(
                  icon: Icons.history,
                  title: 'Histórico de sessões',
                  subtitle: 'Ver, exportar em CSV ou apagar.',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => HistoryScreen(database: vision.database!))),
                ),
              ],
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.delete_outline,
                title: 'Apagar calibração salva',
                subtitle: 'Volta aos limiares padrão.',
                danger: true,
                onTap: () => _confirm(
                  context,
                  title: 'Apagar calibração?',
                  body: 'Os limiares voltam ao padrão e será preciso calibrar de novo.',
                  action: 'Apagar',
                  onOk: () async {
                    await vision.clearCalibration();
                    if (context.mounted) _snack(context, 'Calibração apagada.');
                  },
                ),
              ),
            ]),

            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Restaurar ajustes padrão',
              icon: Icons.settings_backup_restore,
              secondary: true,
              onPressed: () => _confirm(
                context,
                title: 'Restaurar padrões?',
                body: 'Som, vibração, alertas, filtro de sorriso, cabeça/rosto, modo deitado e tempos voltam '
                    'aos valores originais. '
                    'A calibração é mantida.',
                action: 'Restaurar',
                onOk: () async {
                  await vision.resetSettings();
                  if (context.mounted) _snack(context, 'Ajustes restaurados.');
                },
              ),
            ),

            // ------------------------------------------------------------ sobre
            const SizedBox(height: 28),
            const _SectionLabel(icon: Icons.info_outline, text: 'SOBRE'),
            const _Card(children: [
              Padding(
                padding: EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fatigue Guard • versão 1.0.0', style: AppText.cardTitle),
                  SizedBox(height: 6),
                  Text(
                    'Protótipo acadêmico (TCC) de detecção de sonolência ao volante. '
                    'Flutter + Google ML Kit (detecção facial no aparelho), métricas EAR, MAR e PERCLOS, '
                    'histórico em SQLite. Não substitui o descanso: ao sentir sono, pare em local seguro.',
                    style: AppText.body,
                  ),
                ]),
              ),
            ]),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(text, style: AppText.section),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: AppColors.accent, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.cardTitle),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.title,
    required this.description,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
  });

  final String title;
  final String description;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppText.cardTitle)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.panel2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.lineStrong),
              ),
              child: Text(valueLabel,
                  style: AppText.number.copyWith(fontSize: 17, color: AppColors.accentDark)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
        ]),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : AppColors.accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.cardTitle.copyWith(color: danger ? AppColors.red : AppColors.text)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
      ),
    );
  }
}
