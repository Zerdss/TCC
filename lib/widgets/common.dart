import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../theme.dart';
import '../vision/vision_controller.dart';

/// Dá acesso ao [VisionController] em qualquer tela (ex.: botão de configurações).
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.vision, required super.child});

  final VisionController vision;

  static VisionController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.vision;

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.vision != vision;
}

/// Estrutura comum: área segura, rolagem, largura máxima e cabeçalho do app.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.children, this.showSettings = true, this.maxWidth = 760});

  final List<Widget> children;
  final bool showSettings;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.9, -1.1),
            radius: 1.2,
            colors: [Color(0x40CDEBD7), AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
                children: [AppHeader(showSettings: showSettings), const SizedBox(height: 24), ...children],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.showSettings = true});

  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final vision = AppScope.maybeOf(context);
    // Em telas estreitas o selo "100% LOCAL" vira só o ícone, para o nome caber.
    final compact = MediaQuery.sizeOf(context).width < 430 && showSettings && vision != null;
    return Row(
      children: [
        if (canPop)
          _HeaderButton(
            icon: Icons.arrow_back,
            tooltip: 'Voltar',
            onTap: () => Navigator.of(context).maybePop(),
          )
        else
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.panel2, AppColors.panel],
              ),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.lineStrong),
            ),
            child: const Icon(Icons.remove_red_eye_outlined, color: AppColors.accent, size: 22),
          ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TCC • VISÃO COMPUTACIONAL', style: AppText.overline, overflow: TextOverflow.ellipsis),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('FATIGUE / GUARD', style: AppText.brand, maxLines: 1),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 9, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFA8D5B9)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 13, color: AppColors.green),
              if (!compact) const SizedBox(width: 5),
              if (!compact)
                const Text('100% LOCAL',
                  style: TextStyle(
                      fontFamily: displayFont,
                      color: AppColors.green,
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (showSettings && vision != null) ...[
          const SizedBox(width: 8),
          _HeaderButton(
            key: const Key('button-configuracoes'),
            icon: Icons.tune,
            tooltip: 'Configurações',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => SettingsScreen(vision: vision))),
          ),
        ],
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: AppColors.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: SizedBox(width: 42, height: 42, child: Icon(icon, color: AppColors.text, size: 20)),
        ),
      ),
    );
  }
}

/// Cabeçalho de seção de página: rótulo, título e descrição.
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, required this.kicker, required this.title, this.subtitle});

  final String kicker;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kicker, style: AppText.kicker),
        const SizedBox(height: 6),
        Text(title, style: AppText.h2),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(subtitle!, style: AppText.body),
        ],
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final fg = secondary ? AppColors.text : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: onPressed == null ? AppColors.muted : fg),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(
          backgroundColor: secondary ? AppColors.panel : AppColors.accent,
          foregroundColor: fg,
          disabledBackgroundColor: AppColors.panel2,
          disabledForegroundColor: AppColors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: secondary ? const BorderSide(color: AppColors.line) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.border});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border ?? AppColors.line),
      ),
      child: child,
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, this.color = AppColors.accent, this.size = 7});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
