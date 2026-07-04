import 'package:flutter/material.dart';

import '../../../core/theme/unl_colors.dart';

class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/images/logo.png',
        width: 220,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const _LogoFallback();
        },
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.school_outlined, color: UnlColors.gold, size: 52),
        SizedBox(height: 10),
        Text(
          'UNIVERSIDADE',
          style: TextStyle(
            color: UnlColors.gold,
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'DE LÍDERES',
          style: TextStyle(
            color: UnlColors.textSecondary,
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
          ),
        ),
      ],
    );
  }
}
