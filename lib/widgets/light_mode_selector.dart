import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/fatigue_engine.dart';
import '../vision/vision_controller.dart';

/// Seletor Dia / Noite / Automático, como o botão claro/escuro dos sites.
class LightModeSelector extends StatelessWidget {
  const LightModeSelector({super.key, required this.vision, this.compact = false});

  final VisionController vision;

  /// Versão curta (só ícones e nomes curtos), para o painel ao vivo.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vision,
      builder: (context, _) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<LightMode>(
          key: const Key('light-mode'),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
            textStyle: WidgetStatePropertyAll(
                TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 13 : 14)),
            backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected)
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.panel),
            foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected) ? AppColors.accentDark : AppColors.muted),
          ),
          segments: [
            const ButtonSegment(value: LightMode.day, icon: Icon(Icons.wb_sunny_outlined, size: 18), label: Text('Dia')),
            const ButtonSegment(value: LightMode.night, icon: Icon(Icons.nightlight_outlined, size: 18), label: Text('Noite')),
            ButtonSegment(
                value: LightMode.auto,
                icon: const Icon(Icons.brightness_auto_outlined, size: 18),
                label: Text(compact ? 'Auto' : 'Automático')),
          ],
          selected: {vision.settings.lightMode},
          onSelectionChanged: (s) => vision.setLightMode(s.first),
        ),
      ),
    );
  }
}
