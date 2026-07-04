import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AuthResult {
  const AuthResult({required this.success, this.message});

  final bool success;
  final String? message;
}

class AuthService {
  SupabaseClient get _client {
    return Supabase.instance.client;
  }

  Future<void> _safeSignOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Ignora erro de logout para não esconder o erro real do cadastro.
    }
  }

  String _traduzirErroLogin(String mensagem) {
    final texto = mensagem.toLowerCase();

    if (texto.contains('invalid login credentials')) {
      return 'E-mail ou senha inválidos.';
    }

    if (texto.contains('email not confirmed')) {
      return 'Seu e-mail ainda não foi confirmado.';
    }

    if (texto.contains('too many requests')) {
      return 'Muitas tentativas seguidas. Aguarde um momento e tente novamente.';
    }

    if (texto.contains('network') || texto.contains('fetch')) {
      return 'Não foi possível conectar. Verifique sua internet e tente novamente.';
    }

    return 'Não foi possível entrar agora. Tente novamente em instantes.';
  }

  String _traduzirErroRecuperacao(String mensagem) {
    final texto = mensagem.toLowerCase();

    if (texto.contains('email rate limit exceeded')) {
      return 'Muitas solicitações para este e-mail. Aguarde um momento e tente novamente.';
    }

    if (texto.contains('too many requests')) {
      return 'Muitas tentativas seguidas. Aguarde um momento e tente novamente.';
    }

    if (texto.contains('invalid email')) {
      return 'Informe um e-mail válido.';
    }

    if (texto.contains('network') || texto.contains('fetch')) {
      return 'Não foi possível conectar. Verifique sua internet e tente novamente.';
    }

    return 'Não foi possível enviar as instruções agora. Tente novamente em instantes.';
  }

  String _traduzirErroCadastro(String mensagem) {
    final texto = mensagem.toLowerCase();

    if (texto.contains('already') ||
        texto.contains('registered') ||
        texto.contains('already been registered') ||
        texto.contains('user already registered')) {
      return 'Este e-mail já possui login cadastrado. Acesse a tela de login ou aguarde a aprovação do seu cadastro.';
    }

    if (texto.contains('password') && texto.contains('6')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }

    if (texto.contains('weak password')) {
      return 'A senha informada é muito fraca. Crie uma senha mais segura.';
    }

    if (texto.contains('invalid email')) {
      return 'Informe um e-mail válido.';
    }

    if (texto.contains('signup') && texto.contains('disabled')) {
      return 'O cadastro está temporariamente indisponível.';
    }

    if (texto.contains('too many requests')) {
      return 'Muitas tentativas seguidas. Aguarde um momento e tente novamente.';
    }

    if (texto.contains('network') || texto.contains('fetch')) {
      return 'Não foi possível conectar. Verifique sua internet e tente novamente.';
    }

    return 'Não foi possível criar o cadastro agora. Tente novamente em instantes.';
  }

  Future<AuthResult> signInStudent({
    required String email,
    required String password,
  }) async {
    try {
      final emailNormalizado = email.trim().toLowerCase();

      final loginData = await _client.auth.signInWithPassword(
        email: emailNormalizado,
        password: password,
      );

      final user = loginData.user;
      final session = loginData.session;

      if (user == null || session == null) {
        return const AuthResult(
          success: false,
          message: 'Não foi possível iniciar sua sessão. Tente novamente.',
        );
      }

      final alunoAprovado = await _client.rpc<bool>(
        'is_approved_student',
        params: {'user_id': user.id},
      );

      if (alunoAprovado != true) {
        await _safeSignOut();

        return const AuthResult(
          success: false,
          message:
              'Seu cadastro ainda não foi aprovado para acessar a área do aluno.',
        );
      }

      return const AuthResult(success: true);
    } on AuthException catch (error) {
      return AuthResult(
        success: false,
        message: _traduzirErroLogin(error.message),
      );
    } catch (_) {
      await _safeSignOut();

      return const AuthResult(
        success: false,
        message: 'Não foi possível entrar agora. Tente novamente em instantes.',
      );
    }
  }

  Future<AuthResult> sendPasswordResetEmail({required String email}) async {
    try {
      final emailNormalizado = email.trim().toLowerCase();

      await _client.auth.resetPasswordForEmail(
        emailNormalizado,
        redirectTo: SupabaseConfig.passwordResetRedirectUrl,
      );

      return const AuthResult(
        success: true,
        message:
            'Enviamos as instruções de redefinição de senha para o seu e-mail.',
      );
    } on AuthException catch (error) {
      return AuthResult(
        success: false,
        message: _traduzirErroRecuperacao(error.message),
      );
    } catch (_) {
      return const AuthResult(
        success: false,
        message:
            'Não foi possível enviar as instruções agora. Tente novamente em instantes.',
      );
    }
  }

  Future<AuthResult> registerStudent({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String password,
    required String mmnLogin,
    required String leaderName,
    required String street,
    required String number,
    required String neighborhood,
    required String city,
    required String state,
    required String zipCode,
  }) async {
    try {
      final firstNameTrim = firstName.trim();
      final lastNameTrim = lastName.trim();
      final phoneTrim = phone.trim();
      final emailNormalizado = email.trim().toLowerCase();
      final mmnLoginTrim = mmnLogin.trim();
      final leaderNameTrim = leaderName.trim();
      final streetTrim = street.trim();
      final numberTrim = number.trim();
      final neighborhoodTrim = neighborhood.trim();
      final cityTrim = city.trim();
      final stateTrim = state.trim().toUpperCase();
      final zipCodeTrim = zipCode.trim();

      final fullName = '$firstNameTrim $lastNameTrim'.trim();

      final fullAddress = [
        streetTrim,
        numberTrim,
        neighborhoodTrim,
        cityTrim,
        stateTrim,
        zipCodeTrim,
      ].where((item) => item.isNotEmpty).join(', ');

      final payload = <String, dynamic>{
        'first_name': firstNameTrim,
        'last_name': lastNameTrim,
        'full_name': fullName,
        'phone': phoneTrim,
        'email': emailNormalizado,
        'requested_password': password,
        'mmn_login': mmnLoginTrim,
        'leader_name': leaderNameTrim,
        'street': streetTrim,
        'number': numberTrim,
        'neighborhood': neighborhoodTrim,
        'city': cityTrim,
        'state': stateTrim,
        'zip_code': zipCodeTrim,
        'full_address': fullAddress,
        'status': 'pending',
      };

      await _client.auth.signUp(
        email: emailNormalizado,
        password: password,
        data: {
          'full_name': fullName,
          'first_name': firstNameTrim,
          'last_name': lastNameTrim,
          'phone': phoneTrim,
          'role': 'member',
        },
      );

      await _client.from('student_registration_requests').insert(payload);

      await _safeSignOut();

      return const AuthResult(
        success: true,
        message:
            'Cadastro enviado com sucesso. Em breve sua solicitação será analisada.',
      );
    } on AuthException catch (error) {
      await _safeSignOut();

      return AuthResult(
        success: false,
        message:
            'Erro técnico Auth: ${error.message} | status: ${error.statusCode ?? 'sem status'}',
      );
    } on PostgrestException catch (error) {
      await _safeSignOut();

      return AuthResult(
        success: false,
        message:
            'Erro técnico Banco: ${error.message} | code: ${error.code ?? 'sem code'} | details: ${error.details ?? 'sem details'} | hint: ${error.hint ?? 'sem hint'}',
      );
    } catch (error) {
      await _safeSignOut();

      return AuthResult(
        success: false,
        message: 'Erro técnico Geral: ${error.runtimeType} | $error',
      );
    }
  }
}
