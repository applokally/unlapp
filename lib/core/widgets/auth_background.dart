// VERSÃO: v30
import 'package:flutter/material.dart';

import '../theme/unl_colors.dart';

class AuthBackground extends StatefulWidget {
  const AuthBackground({required this.child, super.key});

  final Widget child;

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UnlColors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: UnlColors.black)),
          Positioned.fill(
            child: Opacity(
              opacity: 0.22,
              child: Image.asset(
                'assets/images/HtbB34sFMlId7A1hElSRnTAjLsc.png',
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.50),
                    Colors.black.withValues(alpha: 0.90),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.72, -0.24),
                  radius: 0.82,
                  colors: [
                    UnlColors.gold.withValues(alpha: 0.055),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                final value = _glowController.value;

                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(
                        -0.42 + (value * 0.18),
                        -0.58 + (value * 0.12),
                      ),
                      radius: 0.74,
                      colors: [
                        UnlColors.gold.withValues(
                          alpha: 0.035 + (value * 0.025),
                        ),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(child: SafeArea(child: widget.child)),
        ],
      ),
    );
  }
}
