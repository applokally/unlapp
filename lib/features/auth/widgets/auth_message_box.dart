import 'package:flutter/material.dart';

import '../../../core/theme/unl_colors.dart';

enum AuthMessageType { error, success, warning }

class AuthMessageBox extends StatelessWidget {
  const AuthMessageBox({
    required this.message,
    this.type = AuthMessageType.warning,
    super.key,
  });

  final String message;
  final AuthMessageType type;

  Color get _textColor {
    switch (type) {
      case AuthMessageType.error:
        return const Color(0xFFFF0000);
      case AuthMessageType.success:
        return UnlColors.gold;
      case AuthMessageType.warning:
        return UnlColors.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: SizedBox(
        key: ValueKey<String>(message),
        width: double.infinity,
        child: Text(
          message,
          style: TextStyle(
            color: _textColor,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
