import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../../auth/screens/login_screen.dart';
import '../screens/student_my_courses_screen.dart';
import '../screens/student_my_trails_screen.dart';
import '../screens/student_my_certificates_screen.dart';
import '../screens/student_personal_data_screen.dart';
import '../screens/student_profile_dashboard_screen.dart';

const Color _studentShellBackground = Color(0xFF050609);
const Color _studentShellPureBlack = Color(0xFF000000);
const Color _studentShellGold = UnlColors.gold;

abstract final class StudentAppRoutes {
  static const String home = '/student-home';
  static const String trails = '/student-trails';
  static const String courses = '/student-courses';
  static const String live = '/student-live';
  static const String community = '/student-community';
  static const String gamification = '/student-gamification';
}

enum StudentAppDestination {
  home,
  trails,
  courses,
  live,
  community,
  gamification,
}

enum _StudentShellHeaderPanel { search, notifications, profile }

enum _StudentProfileMenuItem {
  dashboard,
  personalData,
  courses,
  trails,
  certificates,
}

class _StudentShellProfile {
  const _StudentShellProfile({required this.fullName, required this.avatarUrl});

  final String? fullName;
  final String? avatarUrl;
}

class _StudentShellNavigationItem {
  const _StudentShellNavigationItem({
    required this.destination,
    required this.label,
    required this.icon,
  });

  final StudentAppDestination destination;
  final String label;
  final IconData icon;
}

class _StudentShellNotification {
  const _StudentShellNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.sentAt,
  });

  final String id;
  final String title;
  final String body;
  final String sentAt;
}

class _StudentShellSearchResult {
  const _StudentShellSearchResult({
    required this.title,
    required this.description,
    required this.category,
    required this.icon,
    required this.destination,
  });

  final String title;
  final String description;
  final String category;
  final IconData icon;
  final StudentAppDestination destination;
}

class _StudentShellActiveGlowPainter extends CustomPainter {
  const _StudentShellActiveGlowPainter({required this.centerX});

  final double centerX;

  @override
  void paint(Canvas canvas, Size size) {
    final verticalGlowRect = Rect.fromLTWH(centerX - 62, -10, 124, 86);
    final verticalGlowPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x8FFFFFFF),
          Color(0x5EFFFFFF),
          Color(0x2BFFFFFF),
          Color(0x0FFFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [0.0, 0.16, 0.38, 0.68, 1.0],
      ).createShader(verticalGlowRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);

    final verticalGlowPath = Path()
      ..moveTo(centerX - 48, -4)
      ..cubicTo(centerX - 66, 18, centerX - 52, 55, centerX - 23, 76)
      ..lineTo(centerX + 23, 76)
      ..cubicTo(centerX + 52, 55, centerX + 66, 18, centerX + 48, -4)
      ..close();

    canvas.drawPath(verticalGlowPath, verticalGlowPaint);

    final topHaloRect = Rect.fromCenter(
      center: Offset(centerX, -2),
      width: 92,
      height: 46,
    );
    final topHaloPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.topCenter,
        radius: 1.05,
        colors: [
          Color(0xCCFFFFFF),
          Color(0x73FFFFFF),
          Color(0x21FFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [0.0, 0.22, 0.58, 1.0],
      ).createShader(topHaloRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    canvas.drawOval(topHaloRect, topHaloPaint);

    final topLineRect = Rect.fromCenter(
      center: Offset(centerX, 1),
      width: 58,
      height: 2.4,
    );
    final topLinePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(topLineRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawRRect(
      RRect.fromRectAndRadius(topLineRect, const Radius.circular(99)),
      topLinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StudentShellActiveGlowPainter oldDelegate) {
    return oldDelegate.centerX != centerX;
  }
}

class StudentAppShell extends StatefulWidget {
  const StudentAppShell({
    super.key,
    required this.activeDestination,
    required this.scrollController,
    required this.body,
    this.backgroundColor = _studentShellBackground,
    this.onSearchTap,
    this.onNotificationsTap,
    this.onProfileTap,
  });

  final StudentAppDestination activeDestination;
  final ScrollController scrollController;
  final Widget body;
  final Color backgroundColor;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onProfileTap;

  @override
  State<StudentAppShell> createState() => _StudentAppShellState();
}

class _StudentAppShellState extends State<StudentAppShell> {
  final TextEditingController _searchController = TextEditingController();

  _StudentShellProfile? _profile;
  _StudentShellHeaderPanel? _openPanel;
  _StudentProfileMenuItem _activeProfileMenuItem =
      _StudentProfileMenuItem.dashboard;
  List<_StudentShellNotification> _notifications = const [];
  List<_StudentShellSearchResult> _searchResults = const [];
  Timer? _searchDebounce;
  bool _headerScrolled = false;
  bool _isLoadingNotifications = false;
  bool _isSearching = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScroll);
    _searchController.addListener(_handleSearchChange);
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant StudentAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScroll);
      widget.scrollController.addListener(_handleScroll);
      _handleScroll();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    _searchDebounce?.cancel();
    _searchController
      ..removeListener(_handleSearchChange)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final shouldShowGlassHeader =
        widget.scrollController.hasClients &&
        widget.scrollController.offset > 36;

    if (_headerScrolled != shouldShowGlassHeader && mounted) {
      setState(() {
        _headerScrolled = shouldShowGlassHeader;
      });
    }
  }

  void _handleSearchChange() {
    _searchDebounce?.cancel();

    if (mounted) {
      setState(() {});
    }

    final query = _searchController.text.trim();
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _isSearching = false;
        });
      }
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 360), () {
      _loadSearchResults(query);
    });
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    try {
      final dynamic response = await _supabase
          .from('profiles')
          .select('id,full_name,avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (response is! Map) {
        setState(() {
          _profile = const _StudentShellProfile(
            fullName: null,
            avatarUrl: null,
          );
        });
        return;
      }

      final profile = Map<String, dynamic>.from(response);

      setState(() {
        _profile = _StudentShellProfile(
          fullName: _text(profile['full_name']),
          avatarUrl: _resolveAvatarUrl(_text(profile['avatar_url'])),
        );
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _profile = const _StudentShellProfile(fullName: null, avatarUrl: null);
      });
    }
  }

  Future<void> _loadNotifications() async {
    if (mounted) {
      setState(() => _isLoadingNotifications = true);
    }

    try {
      final dynamic response = await _supabase
          .from('community_notifications')
          .select('id,title,body,sent_at,created_at')
          .eq('status', 'sent')
          .order('sent_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);

      final notifications = _rows(response)
          .map(
            (row) => _StudentShellNotification(
              id: _text(row['id']) ?? '',
              title: _text(row['title']) ?? 'Universidade de Líderes',
              body: _text(row['body']) ?? '',
              sentAt: _text(row['sent_at']) ?? _text(row['created_at']) ?? '',
            ),
          )
          .where((notification) => notification.id.isNotEmpty)
          .toList(growable: false);

      if (!mounted || _openPanel != _StudentShellHeaderPanel.notifications) {
        return;
      }

      setState(() => _notifications = notifications);
    } catch (_) {
      if (!mounted || _openPanel != _StudentShellHeaderPanel.notifications) {
        return;
      }

      setState(() => _notifications = const []);
    } finally {
      if (mounted && _openPanel == _StudentShellHeaderPanel.notifications) {
        setState(() => _isLoadingNotifications = false);
      }
    }
  }

  Future<void> _loadSearchResults(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) return;

    if (mounted && _openPanel == _StudentShellHeaderPanel.search) {
      setState(() => _isSearching = true);
    }

    final searchPattern =
        '%${normalizedQuery.replaceAll('%', '').replaceAll('_', '')}%';

    try {
      final dynamic coursesResponse = await _supabase
          .from('courses')
          .select('id,title')
          .ilike('title', searchPattern)
          .limit(12);

      final dynamic postsResponse = await _supabase
          .from('community_posts')
          .select('id,body')
          .eq('status', 'published')
          .ilike('body', searchPattern)
          .limit(12);

      if (!mounted ||
          _openPanel != _StudentShellHeaderPanel.search ||
          _searchController.text.trim() != normalizedQuery) {
        return;
      }

      final results = <_StudentShellSearchResult>[
        for (final row in _rows(coursesResponse))
          if ((_text(row['title']) ?? '').isNotEmpty)
            _StudentShellSearchResult(
              title: _text(row['title'])!,
              description: 'Curso disponível para você',
              category: 'Cursos',
              icon: Icons.menu_book_outlined,
              destination: StudentAppDestination.courses,
            ),
        for (final row in _rows(postsResponse))
          if ((_text(row['body']) ?? '').isNotEmpty)
            _StudentShellSearchResult(
              title: _truncate(_text(row['body'])!, 94),
              description: 'Publicação da comunidade',
              category: 'Comunidade',
              icon: Icons.forum_outlined,
              destination: StudentAppDestination.community,
            ),
      ];

      setState(() => _searchResults = results);
    } catch (_) {
      if (!mounted || _openPanel != _StudentShellHeaderPanel.search) {
        return;
      }

      setState(() => _searchResults = const []);
    } finally {
      if (mounted && _openPanel == _StudentShellHeaderPanel.search) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _openSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _openPanel = _StudentShellHeaderPanel.search;
      _searchResults = const [];
      _isSearching = false;
    });
  }

  void _openNotifications() {
    setState(() {
      _openPanel = _StudentShellHeaderPanel.notifications;
      _notifications = const [];
    });
    _loadNotifications();
  }

  void _openProfile() {
    setState(() {
      _openPanel = _StudentShellHeaderPanel.profile;
      _activeProfileMenuItem = _StudentProfileMenuItem.dashboard;
    });
  }

  void _closeHeaderPanel() {
    _searchDebounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _openPanel = null;
      _isSearching = false;
      _isLoadingNotifications = false;
    });
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _studentShellPureBlack,
            content: Text(
              'Não foi possível encerrar sua sessão agora.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlayStyle = SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: widget.backgroundColor,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: widget.backgroundColor,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        extendBody: false,
        bottomNavigationBar: _buildBottomNavigation(),
        body: Stack(
          children: [
            widget.body,
            if (_openPanel != null) _buildHeaderPanel(),
            Positioned(top: 0, left: 0, right: 0, child: _buildGlobalHeader()),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalHeader() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _headerScrolled || _openPanel != null
            ? _studentShellPureBlack
            : Colors.transparent,
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _headerScrolled && _openPanel == null ? 14 : 0,
            sigmaY: _headerScrolled && _openPanel == null ? 14 : 0,
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 68,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 150,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return const Text(
                          'UNIVERSIDADE\nDE LÍDERES',
                          style: TextStyle(
                            color: UnlColors.gold,
                            fontSize: 12,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Buscar',
                      onPressed: widget.onSearchTap ?? _openSearch,
                      icon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Notificações',
                      onPressed:
                          widget.onNotificationsTap ?? _openNotifications,
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 3),
                    InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: widget.onProfileTap ?? _openProfile,
                      child: Container(
                        width: 39,
                        height: 39,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: UnlColors.gold.withOpacity(0.66),
                          ),
                          color: UnlColors.gold.withOpacity(0.14),
                        ),
                        child: ClipOval(
                          child: _profile?.avatarUrl != null
                              ? Image.network(
                                  _profile!.avatarUrl!,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) {
                                    return _buildAvatarFallback();
                                  },
                                )
                              : _buildAvatarFallback(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderPanel() {
    final isProfilePanel = _openPanel == _StudentShellHeaderPanel.profile;

    return Positioned.fill(
      child: Material(
        color: _studentShellPureBlack,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 106, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isProfilePanel)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: _closeHeaderPanel,
                      tooltip: 'Fechar',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _panelTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            height: 1,
                            letterSpacing: -0.8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _closeHeaderPanel,
                        tooltip: 'Fechar',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: isProfilePanel ? 4 : 20),
                Expanded(child: _buildPanelContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _panelTitle {
    return switch (_openPanel) {
      _StudentShellHeaderPanel.search => 'Buscar',
      _StudentShellHeaderPanel.notifications => 'Notificações',
      _StudentShellHeaderPanel.profile => 'Meu perfil',
      null => '',
    };
  }

  Widget _buildPanelContent() {
    return switch (_openPanel) {
      _StudentShellHeaderPanel.search => _buildSearchPanel(),
      _StudentShellHeaderPanel.notifications => _buildNotificationsPanel(),
      _StudentShellHeaderPanel.profile => _buildProfilePanel(),
      null => const SizedBox.shrink(),
    };
  }

  Widget _buildSearchPanel() {
    final query = _searchController.text.trim();

    return Column(
      children: [
        TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'O que você procura?',
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    tooltip: 'Limpar busca',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                    ),
                  ),
            filled: true,
            fillColor: _studentShellPureBlack,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            border: _panelInputBorder,
            enabledBorder: _panelInputBorder,
            focusedBorder: _panelInputBorder.copyWith(
              borderSide: const BorderSide(color: _studentShellGold),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: _isSearching
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: _studentShellGold,
                    ),
                  ),
                )
              : query.length < 2
              ? _buildPanelEmptyState(
                  icon: Icons.search_rounded,
                  title: 'Encontre o que precisa',
                  description:
                      'Pesquise cursos e conteúdos compartilhados pela comunidade.',
                )
              : _searchResults.isEmpty
              ? _buildPanelEmptyState(
                  icon: Icons.manage_search_rounded,
                  title: 'Nenhum resultado encontrado',
                  description:
                      'Tente buscar por outro termo para encontrar conteúdos da Universidade de Líderes.',
                )
              : ListView.separated(
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _closeHeaderPanel();
                          _navigateTo(result.destination);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _studentShellGold.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  result.icon,
                                  color: _studentShellGold,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      result.category,
                                      style: const TextStyle(
                                        color: _studentShellGold,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      result.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 1.3,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      result.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white38,
                                size: 15,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNotificationsPanel() {
    if (_isLoadingNotifications) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: _studentShellGold,
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return _buildPanelEmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'Nenhuma notificação por enquanto',
        description:
            'Quando houver uma novidade para você, ela aparecerá aqui.',
      );
    }

    return ListView.separated(
      itemCount: _notifications.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final notification = _notifications[index];

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _closeHeaderPanel();
              _navigateTo(StudentAppDestination.community);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _studentShellGold.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.notifications_active_outlined,
                      color: _studentShellGold,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (notification.body.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            notification.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ],
                        if (notification.sentAt.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            _relativeTime(notification.sentAt),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white38,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfilePanel() {
    final user = _supabase.auth.currentUser;
    final name = _profile?.fullName?.trim();
    final displayName = name == null || name.isEmpty ? 'Aluno' : name;
    final email = user?.email?.trim() ?? '';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(
          'Área do aluno',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1,
            letterSpacing: -0.9,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.circle, color: _studentShellGold, size: 8),
            SizedBox(width: 8),
            Text(
              'Conta ativa',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _studentShellGold.withOpacity(0.65)),
                color: _studentShellGold.withOpacity(0.14),
              ),
              child: ClipOval(
                child: _profile?.avatarUrl != null
                    ? Image.network(
                        _profile!.avatarUrl!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => _buildProfileAvatarText(),
                      )
                    : _buildProfileAvatarText(),
              ),
            ),
            const SizedBox(width: 14),
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
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(height: 1, color: Colors.white10),
        const SizedBox(height: 10),
        _ProfileMenuItem(
          icon: Icons.grid_view_rounded,
          label: 'Dashboard',
          active: _activeProfileMenuItem == _StudentProfileMenuItem.dashboard,
          onTap: () =>
              _selectProfileMenuItem(_StudentProfileMenuItem.dashboard),
        ),
        _ProfileMenuItem(
          icon: Icons.person_outline_rounded,
          label: 'Meus dados',
          active:
              _activeProfileMenuItem == _StudentProfileMenuItem.personalData,
          onTap: () =>
              _selectProfileMenuItem(_StudentProfileMenuItem.personalData),
        ),
        _ProfileMenuItem(
          icon: Icons.menu_book_outlined,
          label: 'Meus cursos',
          active: _activeProfileMenuItem == _StudentProfileMenuItem.courses,
          onTap: () => _selectProfileMenuItem(_StudentProfileMenuItem.courses),
        ),
        _ProfileMenuItem(
          icon: Icons.school_outlined,
          label: 'Minhas trilhas',
          active: _activeProfileMenuItem == _StudentProfileMenuItem.trails,
          onTap: () => _selectProfileMenuItem(_StudentProfileMenuItem.trails),
        ),
        _ProfileMenuItem(
          icon: Icons.workspace_premium_outlined,
          label: 'Meus certificados',
          active:
              _activeProfileMenuItem == _StudentProfileMenuItem.certificates,
          onTap: () =>
              _selectProfileMenuItem(_StudentProfileMenuItem.certificates),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: Colors.white10),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _signOut,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: _studentShellGold,
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: const Text(
            'Sair da conta',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  void _selectProfileMenuItem(_StudentProfileMenuItem item) {
    if (item == _StudentProfileMenuItem.dashboard) {
      _closeHeaderPanel();

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const StudentProfileDashboardScreen(),
        ),
      );
      return;
    }

    if (item == _StudentProfileMenuItem.personalData) {
      _closeHeaderPanel();

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const StudentPersonalDataScreen(),
        ),
      );
      return;
    }

    if (item == _StudentProfileMenuItem.courses) {
      _closeHeaderPanel();

      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const StudentMyCoursesScreen()),
      );
      return;
    }

    if (item == _StudentProfileMenuItem.trails) {
      _closeHeaderPanel();

      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const StudentMyTrailsScreen()),
      );
      return;
    }

    if (item == _StudentProfileMenuItem.certificates) {
      _closeHeaderPanel();

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const StudentMyCertificatesScreen(),
        ),
      );
      return;
    }

    setState(() => _activeProfileMenuItem = item);
  }

  Widget _buildProfileAvatarText() {
    final name = _profile?.fullName?.trim();
    String initials = 'A';

    if (name != null && name.isNotEmpty) {
      final parts = name
          .split(RegExp(r'\s+'))
          .where((part) => part.trim().isNotEmpty)
          .toList();

      if (parts.length == 1) {
        initials = parts.first.substring(0, 1).toUpperCase();
      } else {
        initials = '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
            .toUpperCase();
      }
    } else {
      final email = _supabase.auth.currentUser?.email ?? 'A';
      initials = email.substring(0, 1).toUpperCase();
    }

    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: _studentShellGold,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildPanelEmptyState({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _studentShellGold.withOpacity(0.10),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: _studentShellGold, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    final name = _profile?.fullName?.trim();
    String initials = 'A';

    if (name != null && name.isNotEmpty) {
      final parts = name
          .split(RegExp(r'\s+'))
          .where((part) => part.trim().isNotEmpty)
          .toList();

      if (parts.length == 1) {
        initials = parts.first.substring(0, 1).toUpperCase();
      } else {
        initials = '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
            .toUpperCase();
      }
    } else {
      final email = _supabase.auth.currentUser?.email ?? 'A';
      initials = email.substring(0, 1).toUpperCase();
    }

    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: UnlColors.gold,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    const items = [
      _StudentShellNavigationItem(
        destination: StudentAppDestination.home,
        label: 'Início',
        icon: Icons.home_rounded,
      ),
      _StudentShellNavigationItem(
        destination: StudentAppDestination.trails,
        label: 'Trilhas',
        icon: Icons.school_outlined,
      ),
      _StudentShellNavigationItem(
        destination: StudentAppDestination.courses,
        label: 'Cursos',
        icon: Icons.menu_book_outlined,
      ),
      _StudentShellNavigationItem(
        destination: StudentAppDestination.live,
        label: 'Ao Vivo',
        icon: Icons.live_tv_outlined,
      ),
      _StudentShellNavigationItem(
        destination: StudentAppDestination.community,
        label: 'Comunidade',
        icon: Icons.forum_outlined,
      ),
      _StudentShellNavigationItem(
        destination: StudentAppDestination.gamification,
        label: 'Gamificação',
        icon: Icons.emoji_events_outlined,
      ),
    ];

    final activeIndex = items.indexWhere(
      (item) => item.destination == widget.activeDestination,
    );

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF1181A22), Color(0xF50B0C11)],
              ),
              border: const Border(top: BorderSide(color: Color(0x22FFFFFF))),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xB8000000),
                  blurRadius: 24,
                  offset: Offset(0, -8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / items.length;
                final activeCenter = itemWidth * (activeIndex + 0.5);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _StudentShellActiveGlowPainter(
                            centerX: activeCenter,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(items.length, (index) {
                        final item = items[index];
                        final active =
                            item.destination == widget.activeDestination;

                        return Expanded(
                          child: InkWell(
                            onTap: active
                                ? null
                                : () => _navigateTo(item.destination),
                            splashColor: Colors.white.withOpacity(0.06),
                            highlightColor: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 8,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.icon,
                                    color: active
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.50),
                                    size: 24,
                                    shadows: active
                                        ? const [
                                            Shadow(
                                              color: Color(0xB3FFFFFF),
                                              blurRadius: 10,
                                            ),
                                            Shadow(
                                              color: Color(0x66FFFFFF),
                                              blurRadius: 18,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.50),
                                      fontSize: 8.7,
                                      fontWeight: active
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      shadows: active
                                          ? const [
                                              Shadow(
                                                color: Color(0x73FFFFFF),
                                                blurRadius: 6,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _navigateTo(StudentAppDestination destination) {
    final routeName = switch (destination) {
      StudentAppDestination.home => StudentAppRoutes.home,
      StudentAppDestination.trails => StudentAppRoutes.trails,
      StudentAppDestination.courses => StudentAppRoutes.courses,
      StudentAppDestination.live => StudentAppRoutes.live,
      StudentAppDestination.community => StudentAppRoutes.community,
      StudentAppDestination.gamification => StudentAppRoutes.gamification,
    };

    Navigator.of(context).pushNamedAndRemoveUntil(routeName, (route) => false);
  }

  OutlineInputBorder get _panelInputBorder {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Colors.white10),
    );
  }

  String? _resolveAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    return null;
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return text;
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];

    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _truncate(String value, int maxLength) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= maxLength) return normalized;

    return '${normalized.substring(0, maxLength).trimRight()}…';
  }

  String _relativeTime(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';

    final difference = DateTime.now().difference(date);
    if (difference.isNegative || difference.inMinutes < 1) return 'Agora';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min';
    if (difference.inHours < 24) return '${difference.inHours} h';
    if (difference.inDays == 1) return 'Ontem';

    return '${difference.inDays} dias';
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? _studentShellGold : Colors.white70;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 22),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: active ? _studentShellGold : Colors.white38,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
