import 'package:flutter/material.dart';

import '../theme/unl_colors.dart';

class UnlTextField extends StatefulWidget {
  const UnlTextField({
    required this.controller,
    required this.placeholder,
    this.label,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.autofillHints,
    this.validator,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  @override
  State<UnlTextField> createState() => _UnlTextFieldState();
}

class _UnlTextFieldState extends State<UnlTextField> {
  late final FocusNode _focusNode;
  late bool _obscured;

  bool _focused = false;

  @override
  void initState() {
    super.initState();

    _focusNode = FocusNode();
    _obscured = widget.obscureText;

    _focusNode.addListener(() {
      setState(() {
        _focused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: color, width: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: UnlColors.gold.withOpacity(0.08),
                  blurRadius: 0,
                  spreadRadius: 4,
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        obscureText: _obscured,
        autofillHints: widget.autofillHints,
        validator: widget.validator,
        onChanged: widget.onChanged,
        cursorColor: UnlColors.gold,
        style: const TextStyle(
          color: UnlColors.textPrimary,
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          isDense: false,
          filled: true,
          fillColor: _focused
              ? Colors.white.withOpacity(0.05)
              : Colors.white.withOpacity(0.03),
          hintText: widget.placeholder,
          hintStyle: const TextStyle(
            color: UnlColors.textMuted,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          enabledBorder: _border(Colors.white.withOpacity(0.10)),
          focusedBorder: _border(UnlColors.gold.withOpacity(0.45)),
          errorBorder: _border(UnlColors.error.withOpacity(0.60)),
          focusedErrorBorder: _border(UnlColors.error.withOpacity(0.70)),
          disabledBorder: _border(Colors.white.withOpacity(0.06)),
          errorStyle: const TextStyle(
            color: UnlColors.error,
            fontSize: 13,
            height: 1.25,
            fontWeight: FontWeight.w500,
          ),
          suffixIcon: widget.obscureText
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      _obscured = !_obscured;
                    });
                  },
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _focused ? UnlColors.gold : UnlColors.textMuted,
                    size: 21,
                  ),
                )
              : null,
        ),
      ),
    );

    if (widget.label == null || widget.label!.trim().isEmpty) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label!,
          style: const TextStyle(
            color: UnlColors.textStrong,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }
}
