import 'package:flutter/material.dart';

class UnlColors {
  const UnlColors._();

  // Base global.css
  static const Color webLightBackground = Color(0xFFFFFFFF);
  static const Color webLightForeground = Color(0xFF171717);

  static const Color webDarkBackground = Color(0xFF0A0A0A);
  static const Color webDarkForeground = Color(0xFFEDEDED);

  // Base auth/aluno usada nas telas escuras
  static const Color background = Color(0xFF0A0A0A);
  static const Color black = Color(0xFF000000);

  // Dourado oficial usado na UI web
  static const Color gold = Color(0xFFDBC094);

  // Superfícies escuras equivalentes aos bg-white/[0.03], bg-white/[0.04]
  static const Color card = Color(0x0AFFFFFF);
  static const Color cardSoft = Color(0x05FFFFFF);
  static const Color inputFill = Color(0x08FFFFFF);

  // Textos equivalentes ao text-white, text-white/82, text-white/62, text-white/28
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textStrong = Color(0xD1FFFFFF);
  static const Color textSecondary = Color(0x9EFFFFFF);
  static const Color textMuted = Color(0x47FFFFFF);

  // Bordas equivalentes ao border-white/8, border-white/10, border-[#DBC094]/22
  static const Color border = Color(0x14FFFFFF);
  static const Color borderStrong = Color(0x1AFFFFFF);
  static const Color goldBorder = Color(0x38DBC094);

  // Estados
  static const Color error = Color(0xFFFFB4B4);
  static const Color errorBackground = Color(0x1AFF3B3B);

  static const Color success = Color(0xFFDBC094);
  static const Color successBackground = Color(0x14DBC094);
}
