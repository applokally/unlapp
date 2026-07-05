// VERSÃO: v31
import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/unl_colors.dart';
import '../../../core/widgets/auth_background.dart';
import '../../../core/widgets/glow_card.dart';
import '../../../core/widgets/premium_pill_button.dart';
import '../../../core/widgets/unl_text_field.dart';
import '../../student/screens/student_home_screen.dart';
import '../widgets/auth_link_button.dart';
import '../widgets/auth_logo.dart';
import '../widgets/auth_message_box.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const String routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _busy = false;
  String? _message;
  AuthMessageType _messageType = AuthMessageType.error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

    final result = await _authService.signInStudent(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _busy = false;
        _message = null;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => const StudentHomeScreen(),
        ),
      );

      return;
    }

    setState(() {
      _busy = false;
      _messageType = AuthMessageType.error;
      _message = result.message ?? 'Não foi possível entrar agora.';
    });
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ForgotPasswordScreen(),
      ),
    );
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const RegisterScreen()),
    );
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
                              'Entrar na plataforma',
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
                          'Use seu e-mail e senha para acessar como aluno.',
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
                          textInputAction: TextInputAction.next,
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
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: Text(
                                'Senha',
                                style: TextStyle(
                                  color: UnlColors.textStrong,
                                  fontSize: 14,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            AuthLinkButton(
                              label: 'Esqueci minha senha',
                              onTap: _openForgotPassword,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        UnlTextField(
                          controller: _passwordController,
                          placeholder: 'Digite sua senha',
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          validator: (value) {
                            if ((value ?? '').isEmpty) {
                              return 'Informe sua senha.';
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
                          label: _busy ? 'Entrando...' : 'Acessar',
                          loading: _busy,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          height: 1,
                          width: double.infinity,
                          color: Colors.white.withOpacity(0.08),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 6,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Ainda não tem acesso?',
                              style: TextStyle(
                                color: UnlColors.textSecondary,
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            AuthLinkButton(
                              label: 'Criar cadastro',
                              onTap: _openRegister,
                            ),
                          ],
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
