import 'package:flutter/material.dart';

import '../theme/unl_colors.dart';

class PremiumPillButton extends StatefulWidget {
  const PremiumPillButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.disabled = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool disabled;

  @override
  State<PremiumPillButton> createState() => _PremiumPillButtonState();
}

class _PremiumPillButtonState extends State<PremiumPillButton> {
  bool _pressed = false;

  bool get _isDisabled {
    return widget.disabled || widget.loading || widget.onPressed == null;
  }

  void _setPressed(bool value) {
    if (_isDisabled) return;

    setState(() {
      _pressed = value;
    });
  }

  void _tap() {
    if (_isDisabled) return;
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: _isDisabled ? 0.55 : 1,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: _tap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: _pressed ? 0.985 : 1,
          child: Container(
            height: 50,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: UnlColors.gold.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: UnlColors.gold.withOpacity(0.42),
                width: 1,
              ),
            ),
            child: widget.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
