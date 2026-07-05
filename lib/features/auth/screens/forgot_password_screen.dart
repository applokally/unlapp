// VERSÃO: v31
import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/unl_colors.dart';
import '../../../core/widgets/auth_background.dart';
import '../../../core/widgets/glow_card.dart';
import '../../../core/widgets/premium_pill_button.dart';
import '../../../core/widgets/unl_text_field.dart';
import '../widgets/auth_link_button.dart';
import '../widgets/auth_logo.dart';
import '../widgets/auth_message_box.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static const String routeName = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _emailController = TextEditingController();

  bool _busy = false;
  String? _message;
  AuthMessageType _messageType = AuthMessageType.error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;

    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
      _messageType = AuthMessageType.error;
    });

    final result = await _authService.sendPasswordResetEmail(
      email: _emailController.text,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;

      if (result.success) {
        _messageType = AuthMessageType.success;
        _message =
            result.message ??
            'Enviamos as instruções de redefinição de senha para o seu e-mail.';
      } else {
        _messageType = AuthMessageType.error;
        _message =
            result.message ??
            'Não foi possível enviar as instruções agora. Tente novamente.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                const AuthLogo(),
                const SizedBox(height: 28),
                GlowCard(
                  maxWidth: 500,
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Recuperar senha',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: UnlColors.textPrimary,
                                fontSize: 26,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.55,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Informe seu e-mail para receber as instruções de redefinição de senha.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: UnlColors.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 26),
                        UnlTextField(
                          label: 'E-mail',
                          controller: _emailController,
                          placeholder: 'Digite seu e-mail',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [
                            AutofillHints.email,
                            AutofillHints.username,
                          ],
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Informe seu e-mail.';
                            }

                            return null;
                          },
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 18),
                          AuthMessageBox(
                            message: _message!,
                            type: _messageType,
                          ),
                        ],
                        const SizedBox(height: 24),
                        PremiumPillButton(
                          label: _busy ? 'Enviando...' : 'Enviar instruções',
                          loading: _busy,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: AuthLinkButton(
                            label: 'Voltar para o login',
                            onTap: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
