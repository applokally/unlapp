// VERSÃO: v31
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../widgets/student_app_shell.dart';

const Color _personalDataBackground = Color(0xFF050609);

class StudentPersonalDataScreen extends StatefulWidget {
  const StudentPersonalDataScreen({super.key});

  static const String routeName = '/student-personal-data';

  @override
  State<StudentPersonalDataScreen> createState() =>
      _StudentPersonalDataScreenState();
}

class _StudentPersonalDataScreenState extends State<StudentPersonalDataScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  _StudentProfileData? _profile;
  String _email = '';
  String _accessLevel = 'Ativo';
  DateTime? _memberSince;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw const _StudentDataException(
          'Não foi possível identificar sua conta. Entre novamente para continuar.',
        );
      }

      final dynamic profileResponse = await _supabase
          .from('profiles')
          .select('id,role,full_name,phone,avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      final profile = profileResponse is Map
          ? _StudentProfileData.fromMap(
              Map<String, dynamic>.from(profileResponse),
            )
          : _StudentProfileData(
              id: user.id,
              role: 'member',
              fullName: _metadataName(
                user.userMetadata ?? const <String, dynamic>{},
              ),
              phone: '',
              avatarUrl: '',
            );

      final accessLevel = await _loadAccessLevel(
        email: user.email ?? '',
        role: profile.role,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = profile;
        _email = user.email ?? '';
        _accessLevel = accessLevel;
        _memberSince = DateTime.tryParse(user.createdAt)?.toLocal();
        _fullNameController.text = profile.fullName.isNotEmpty
            ? profile.fullName
            : _metadataName(user.userMetadata ?? const <String, dynamic>{});
        _phoneController.text = profile.phone;
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _isLoading = false;
        _loadError = null;
      });
    } on _StudentDataException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível carregar seus dados agora.';
      });
    }
  }

  Future<String> _loadAccessLevel({
    required String email,
    required String role,
  }) async {
    if (email.trim().isNotEmpty) {
      try {
        final dynamic response = await _supabase
            .from('student_registration_requests')
            .select('access_level')
            .ilike('email', email.trim())
            .eq('status', 'approved')
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (response is Map) {
          final label = _accessLevelLabel(_text(response['access_level']));
          if (label.isNotEmpty) {
            return label;
          }
        }
      } catch (_) {
        // A conta continua utilizável mesmo quando o nível de acesso não
        // estiver exposto pela política de leitura do estudante.
      }
    }

    if (role.trim().toLowerCase() == 'admin') {
      return 'Administrador';
    }

    return 'Ativo';
  }

  Future<void> _saveProfile() async {
    if (_isSaving) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Entre novamente para salvar seus dados.');
      return;
    }

    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty) {
      _showMessage('Informe seu nome completo para continuar.');
      return;
    }

    if ((newPassword.isNotEmpty || confirmPassword.isNotEmpty) &&
        newPassword != confirmPassword) {
      _showMessage('A confirmação da nova senha não confere.');
      return;
    }

    if (newPassword.isNotEmpty && newPassword.length < 6) {
      _showMessage('A nova senha deve ter pelo menos 6 caracteres.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (newPassword.isNotEmpty) {
        final response = await _supabase.auth.updateUser(
          UserAttributes(password: newPassword),
        );

        if (response.user == null) {
          throw const _StudentDataException(
            'Não foi possível atualizar sua senha agora.',
          );
        }
      }

      final role = _profile?.role.trim().isNotEmpty == true
          ? _profile!.role
          : 'member';

      final dynamic profileResponse = await _supabase
          .from('profiles')
          .upsert({
            'id': user.id,
            'role': role,
            'full_name': fullName,
            'phone': phone.isEmpty ? null : phone,
            'avatar_url': _profile?.avatarUrl.isEmpty == true
                ? null
                : _profile?.avatarUrl,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'id')
          .select('id,role,full_name,phone,avatar_url')
          .maybeSingle();

      if (profileResponse is! Map) {
        throw const _StudentDataException(
          'Não foi possível salvar seus dados agora.',
        );
      }

      final updatedProfile = _StudentProfileData.fromMap(
        Map<String, dynamic>.from(profileResponse),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = updatedProfile;
        _fullNameController.text = updatedProfile.fullName;
        _phoneController.text = updatedProfile.phone;
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });

      _showMessage(
        newPassword.isEmpty
            ? 'Seus dados foram atualizados.'
            : 'Seus dados e sua senha foram atualizados.',
      );
    } on _StudentDataException catch (error) {
      _showMessage(error.message);
    } on AuthException catch (error) {
      _showMessage(_friendlyAuthMessage(error.message));
    } on PostgrestException catch (_) {
      _showMessage('Não foi possível salvar seus dados agora.');
    } catch (_) {
      _showMessage('Não foi possível salvar seus dados agora.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF151515),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.home,
      scrollController: _scrollController,
      backgroundColor: _personalDataBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadProfile,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
            SliverToBoxAdapter(child: _buildContent()),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 120),
        child: Center(
          child: CircularProgressIndicator(
            color: UnlColors.gold,
            strokeWidth: 2.2,
          ),
        ),
      );
    }

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const Icon(
              Icons.person_outline_rounded,
              color: UnlColors.gold,
              size: 42,
            ),
            const SizedBox(height: 18),
            const Text(
              'Não foi possível abrir seus dados',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                height: 1.12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.56),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _loadProfile,
              style: OutlinedButton.styleFrom(
                foregroundColor: UnlColors.gold,
                side: const BorderSide(color: Color(0x44DBC094)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final profile = _profile;
    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : _fallbackName(_email);
    final avatarUrl = profile?.avatarUrl ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PERFIL',
                  style: TextStyle(
                    color: UnlColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.9,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Fechar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Text(
            'Meus dados',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Mantenha seus dados atualizados e cuide da segurança da sua conta.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 14,
              height: 1.48,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              _ProfileAvatar(name: displayName, avatarUrl: avatarUrl, size: 68),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        height: 1.14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.25,
                      ),
                    ),
                    if (_email.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        _email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.52),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 22),
          _buildField(
            label: 'Nome completo',
            icon: Icons.person_outline_rounded,
            controller: _fullNameController,
            textCapitalization: TextCapitalization.words,
            hintText: 'Informe seu nome completo',
          ),
          const SizedBox(height: 20),
          _buildReadOnlyField(
            label: 'E-mail',
            icon: Icons.mail_outline_rounded,
            value: _email.isEmpty ? 'Não informado' : _email,
          ),
          const SizedBox(height: 20),
          _buildField(
            label: 'Telefone',
            icon: Icons.phone_outlined,
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-\s]')),
            ],
            hintText: 'Informe seu telefone',
          ),
          const SizedBox(height: 30),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 22),
          const Text(
            'Segurança',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Preencha os campos abaixo somente se desejar alterar sua senha.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.52),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 18),
          _buildField(
            label: 'Nova senha',
            icon: Icons.lock_outline_rounded,
            controller: _newPasswordController,
            obscureText: true,
            textInputAction: TextInputAction.next,
            hintText: 'Digite sua nova senha',
          ),
          const SizedBox(height: 16),
          _buildField(
            label: 'Confirmar nova senha',
            icon: Icons.lock_reset_outlined,
            controller: _confirmPasswordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveProfile(),
            hintText: 'Digite novamente sua nova senha',
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: UnlColors.gold,
                disabledBackgroundColor: UnlColors.gold.withOpacity(0.38),
                foregroundColor: Colors.black,
                disabledForegroundColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2.2,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 20),
              label: Text(
                _isSaving ? 'Salvando...' : 'Salvar alterações',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: UnlColors.gold,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Acesso $_accessLevel',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_memberSince != null)
                Text(
                  'Membro desde ${_formatDate(_memberSince)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, icon: icon),
        const SizedBox(height: 9),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          obscureText: obscureText,
          enableSuggestions: !obscureText,
          autocorrect: !obscureText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: _inputDecoration(hintText),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required IconData icon,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, icon: icon),
        const SizedBox(height: 9),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.025),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white.withOpacity(0.42),
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
    );

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.white.withOpacity(0.32),
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: Colors.black,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: UnlColors.gold),
      ),
    );
  }

  String _metadataName(Map<String, dynamic>? metadata) {
    final fullName = _text(metadata?['full_name']);
    if (fullName != null) {
      return fullName;
    }

    final name = _text(metadata?['name']);
    return name ?? '';
  }

  String _accessLevelLabel(String? value) {
    final normalized = (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll('_', '-');

    const labels = <String, String>{
      'executivo': 'Executivo',
      'executive': 'Executivo',
      'lider': 'Líder',
      'líder': 'Líder',
      'diamante': 'Diamante',
      'diamond-pro': 'Diamond Pro',
      'diamante-pro': 'Diamond Pro',
      'diamond-elite': 'Diamond Elite',
      'diamante-elite': 'Diamond Elite',
      'imperial-diamond': 'Imperial Diamond',
      'imperial-diamante': 'Imperial Diamond',
    };

    return labels[normalized] ?? '';
  }

  String _friendlyAuthMessage(String message) {
    final normalized = message.toLowerCase();

    if (normalized.contains('password')) {
      return 'Não foi possível atualizar sua senha agora.';
    }

    return 'Não foi possível salvar seus dados agora.';
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return text;
  }

  String _fallbackName(String email) {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      return 'Aluno';
    }

    return cleanEmail.split('@').first;
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '';
    }

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class _StudentProfileData {
  const _StudentProfileData({
    required this.id,
    required this.role,
    required this.fullName,
    required this.phone,
    required this.avatarUrl,
  });

  final String id;
  final String role;
  final String fullName;
  final String phone;
  final String avatarUrl;

  factory _StudentProfileData.fromMap(Map<String, dynamic> map) {
    return _StudentProfileData(
      id: map['id']?.toString() ?? '',
      role: map['role']?.toString() ?? 'member',
      fullName: map['full_name']?.toString().trim() ?? '',
      phone: map['phone']?.toString().trim() ?? '',
      avatarUrl: map['avatar_url']?.toString().trim() ?? '',
    );
  }
}

class _StudentDataException implements Exception {
  const _StudentDataException(this.message);

  final String message;
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
  });

  final String name;
  final String avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: UnlColors.gold.withOpacity(0.12),
        border: Border.all(color: UnlColors.gold.withOpacity(0.62)),
      ),
      child: ClipOval(
        child: avatarUrl.isEmpty
            ? Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: UnlColors.gold,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: UnlColors.gold,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) {
      return 'A';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: UnlColors.gold, size: 18),
        const SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
