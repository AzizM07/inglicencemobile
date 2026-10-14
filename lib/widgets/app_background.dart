import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Fond dégradé équivalent aux `body[data-page=...]` du CSS :
/// un dégradé vertical clair + un halo radial bleuté en haut.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFDDE4F8),
            Color(0xFFEEF1FB),
            Color(0xFFF7F8FC),
            Color(0xFFFFFFFF),
          ],
          stops: [0.0, 0.26, 0.5, 0.72],
        ),
      ),
      child: Stack(
        children: [
          // Halo radial (radial-gradient at 50% -220px du CSS)
          Positioned(
            top: -240,
            left: 0,
            right: 0,
            height: 480,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [Color(0xFFB7C4F0), Color(0x00B7C4F0)],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Carte blanche arrondie (équivalent de .card / .fcard / .filiere-card).
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppRadius.xl,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A28326E),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Petite pastille "badge" (.badge / .eyebrow).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg = AppColors.blueSoft, this.fg = AppColors.blue});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}