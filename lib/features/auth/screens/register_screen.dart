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
import 'forgot_password_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const String routeName = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mmnLoginController = TextEditingController();
  final _leaderNameController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();

  bool _busy = false;
  String? _message;
  AuthMessageType _messageType = AuthMessageType.error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _mmnLoginController.dispose();
    _leaderNameController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _firstNameController.clear();
    _lastNameController.clear();
    _phoneController.clear();
    _emailController.clear();
    _passwordController.clear();
    _mmnLoginController.clear();
    _leaderNameController.clear();
    _streetController.clear();
    _numberController.clear();
    _neighborhoodController.clear();
    _cityController.clear();
    _stateController.clear();
    _zipCodeController.clear();
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

    final result = await _authService.registerStudent(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      phone: _phoneController.text,
      email: _emailController.text,
      password: _passwordController.text,
      mmnLogin: _mmnLoginController.text,
      leaderName: _leaderNameController.text,
      street: _streetController.text,
      number: _numberController.text,
      neighborhood: _neighborhoodController.text,
      city: _cityController.text,
      state: _stateController.text,
      zipCode: _zipCodeController.text,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;

      if (result.success) {
        _messageType = AuthMessageType.success;
        _message =
            result.message ??
            'Cadastro enviado com sucesso. Em breve sua solicitação será analisada.';
        _clearForm();
      } else {
        _messageType = AuthMessageType.error;
        _message =
            result.message ??
            'Não foi possível criar o cadastro agora. Tente novamente.';
      }
    });
  }

  void _goBackToLogin() {
    Navigator.of(context).pop();
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ForgotPasswordScreen(),
      ),
    );
  }

  String? _requiredValidator(String? value, String message) {
    if ((value ?? '').trim().isEmpty) {
      return message;
    }

    return null;
  }

  String? _emailValidator(String? value) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return 'Informe seu e-mail.';
    }

    if (!text.contains('@') || !text.contains('.')) {
      return 'Informe um e-mail válido.';
    }

    return null;
  }

  String? _passwordValidator(String? value) {
    final text = value ?? '';

    if (text.isEmpty) {
      return 'Crie sua senha.';
    }

    if (text.length < 6) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }

    return null;
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Text(
        title,
        style: const TextStyle(
          color: UnlColors.gold,
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
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
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                const AuthLogo(),
                const SizedBox(height: 28),
                GlowCard(
                  maxWidth: 560,
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(
                          child: Text(
                            'Criar cadastro',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: UnlColors.textPrimary,
                              fontSize: 32,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Crie o seu cadastro para ter acesso à Universidade de Líderes. Preencha os mesmos dados cadastrados na empresa parceira. Após o envio, sua solicitação será analisada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: UnlColors.textSecondary,
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 30),
                        UnlTextField(
                          label: 'Nome',
                          controller: _firstNameController,
                          placeholder: 'Digite seu nome',
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.givenName],
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe seu nome.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Sobrenome',
                          controller: _lastNameController,
                          placeholder: 'Digite seu sobrenome',
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.familyName],
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe seu sobrenome.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Telefone',
                          controller: _phoneController,
                          placeholder: 'Digite seu telefone',
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe seu telefone.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
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
                          validator: _emailValidator,
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Senha',
                          controller: _passwordController,
                          placeholder: 'Crie sua senha',
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          validator: _passwordValidator,
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Login MMN',
                          controller: _mmnLoginController,
                          placeholder: 'Digite seu login MMN',
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe seu login MMN.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Nome do seu líder',
                          controller: _leaderNameController,
                          placeholder: 'Digite o nome do seu líder',
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe o nome do seu líder.',
                            );
                          },
                        ),
                        const SizedBox(height: 26),
                        Container(
                          height: 1,
                          width: double.infinity,
                          color: Colors.white.withOpacity(0.08),
                        ),
                        const SizedBox(height: 22),
                        _sectionTitle('ENDEREÇO COMPLETO'),
                        UnlTextField(
                          label: 'Logradouro',
                          controller: _streetController,
                          placeholder: 'Digite o logradouro',
                          textInputAction: TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.streetAddressLine1,
                          ],
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe o logradouro.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Número',
                          controller: _numberController,
                          placeholder: 'Digite o número',
                          keyboardType: TextInputType.streetAddress,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe o número.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Bairro',
                          controller: _neighborhoodController,
                          placeholder: 'Digite seu bairro',
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe seu bairro.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Cidade',
                          controller: _cityController,
                          placeholder: 'Digite sua cidade',
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.addressCity],
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe sua cidade.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'Estado',
                          controller: _stateController,
                          placeholder: 'UF',
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.addressState],
                          validator: (value) {
                            return _requiredValidator(
                              value,
                              'Informe o estado.',
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        UnlTextField(
                          label: 'CEP',
                          controller: _zipCodeController,
                          placeholder: 'Digite o CEP',
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.postalCode],
                          validator: (value) {
                            return _requiredValidator(value, 'Informe o CEP.');
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
                          label: _busy ? 'Enviando cadastro...' : 'Cadastrar',
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
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AuthLinkButton(
                              label: 'Voltar para login',
                              onTap: _goBackToLogin,
                            ),
                            Text(
                              '•',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.20),
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            AuthLinkButton(
                              label: 'Esqueci minha senha',
                              onTap: _openForgotPassword,
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
