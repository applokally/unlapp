import 'package:flutter/material.dart';

import '../theme/unl_colors.dart';

class GlowCard extends StatelessWidget {
  const GlowCard({
    required this.child,
    this.borderRadius = 32,
    this.padding = const EdgeInsets.all(24),
    this.maxWidth,
    super.key,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.82),
            blurRadius: 80,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius - 1),
            color: UnlColors.black,
          ),
          child: child,
        ),
      ),
    );

    if (maxWidth == null) {
      return card;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: card,
    );
  }
}
