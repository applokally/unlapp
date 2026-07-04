import 'package:flutter/material.dart';

import '../../../core/theme/unl_colors.dart';

class AuthLinkButton extends StatefulWidget {
  const AuthLinkButton({
    required this.label,
    required this.onTap,
    this.fontSize = 14,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double fontSize;

  @override
  State<AuthLinkButton> createState() => _AuthLinkButtonState();
}

class _AuthLinkButtonState extends State<AuthLinkButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;

    setState(() {
      _pressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        opacity: _pressed ? 0.72 : 1,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          style: TextStyle(
            color: _pressed ? UnlColors.textPrimary : UnlColors.gold,
            fontSize: widget.fontSize,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}
