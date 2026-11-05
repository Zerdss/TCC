import 'package:flutter/material.dart';

import '../theme.dart';

/// Estrutura comum: área segura, rolagem, largura máxima e cabeçalho do app.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.children, this.bottom});

  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
              children: [const AppHeader(), const SizedBox(height: 26), ...children],
            ),
          ),
        ),
      ),
      bottomNavigationBar: bottom,
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.panel2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: const Icon(Icons.remove_red_eye_outlined, color: AppColors.amber, size: 22),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TCC • VISÃO COMPUTACIONAL', style: AppText.overline, overflow: TextOverflow.ellipsis),
              Text('FATIGUE / GUARD',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 15)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFF10251F), borderRadius: BorderRadius.circular(20)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 14, color: AppColors.green),
              SizedBox(width: 5),
              Text('100% LOCAL',
                  style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
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
    final fg = secondary ? AppColors.text : AppColors.bg;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: onPressed == null ? AppColors.muted : fg),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(
          backgroundColor: secondary ? AppColors.panel : AppColors.amber,
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
  const StatusDot({super.key, this.color = AppColors.amber, this.size = 7});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
