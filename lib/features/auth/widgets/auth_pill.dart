import 'package:flutter/material.dart';

import '../../../core/theme/unl_colors.dart';

class AuthPill extends StatelessWidget {
  const AuthPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: UnlColors.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: UnlColors.gold.withOpacity(0.22), width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: UnlColors.gold,
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w600,
          letterSpacing: 3.36,
        ),
      ),
    );
  }
}
