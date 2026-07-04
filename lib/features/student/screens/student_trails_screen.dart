import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../screens/student_trail_detail_screen.dart';
import '../widgets/student_app_shell.dart';

const Color _trailsBackground = Color(0xFF050609);
const Color _trailCardBackground = Color(0xFF050505);

class _StudentTrail {
  const _StudentTrail({
    required this.id,
    required this.title,
    required this.slug,
    required this.description,
    required this.coverUrl,
    required this.requiredRank,
  });

  final String id;
  final String? slug;
  final String title;
  final String? description;
  final String? coverUrl;
  final int requiredRank;
}

class StudentTrailsScreen extends StatefulWidget {
  const StudentTrailsScreen({super.key});

  static const String routeName = '/student-trails';

  @override
  State<StudentTrailsScreen> createState() => _StudentTrailsScreenState();
}

class _StudentTrailsScreenState extends State<StudentTrailsScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  String? _loadError;

  List<_StudentTrail> _trails = const [];

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadScreen();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadScreen() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final trails = await _loadTrails();

      if (!mounted) return;

      setState(() {
        _trails = trails;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível carregar as trilhas disponíveis agora.';
      });
    }
  }

  Future<List<_StudentTrail>> _loadTrails() async {
    final dynamic response = await _supabase
        .from('course_categories')
        .select(
          'id,title,slug,description,cover_path,cover_vertical_path,'
          'cover_horizontal_path,cover_featured_path,status,is_featured,'
          'required_rank',
        )
        .eq('status', 'published')
        .order('is_featured', ascending: false)
        .order('title', ascending: true);

    return _rows(response)
        .map(
          (row) => _StudentTrail(
            id: _text(row['id']) ?? '',
            title: _text(row['title']) ?? 'Trilha',
            slug: _text(row['slug']),
            description: _text(row['description']),
            // Nesta tela, a imagem correta é sempre a capa vertical grande.
            // A capa horizontal pertence à página interna da trilha.
            coverUrl: _resolveCoverUrl(_selectTrailListCover(row)),
            requiredRank: _asInt(row['required_rank']),
          ),
        )
        .where((trail) => trail.id.isNotEmpty)
        .toList(growable: false);
  }

  String? _selectTrailListCover(Map<String, dynamic> trail) {
    return _text(trail['cover_vertical_path']) ??
        _text(trail['cover_featured_path']) ??
        _text(trail['cover_path']);
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.trails,
      scrollController: _scrollController,
      backgroundColor: _trailsBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: const Color(0xFF191A20),
        onRefresh: _loadScreen,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // Espaço de respiro entre o header global e o conteúdo da página.
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
            SliverToBoxAdapter(child: _buildIntro()),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else if (_trails.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyState())
            else
              SliverToBoxAdapter(child: _buildTrailGrid()),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BIBLIOTECA',
            style: TextStyle(
              color: UnlColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.1,
            ),
          ),
          SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Trilhas de Aprendizado',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.1,
              ),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Acesse as trilhas disponíveis e avance pelos cursos, módulos e aulas publicados.',
            style: TextStyle(
              color: Color(0xA6FFFFFF),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GridView.builder(
        itemCount: _trails.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1 / 1.88,
        ),
        itemBuilder: (context, index) =>
            _buildVerticalTrailCard(_trails[index]),
      ),
    );
  }

  Widget _buildVerticalTrailCard(_StudentTrail trail) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StudentTrailDetailScreen(trailId: trail.id),
            ),
          );
        },
        splashColor: Colors.white.withOpacity(0.06),
        highlightColor: Colors.white.withOpacity(0.03),
        child: Container(
          decoration: BoxDecoration(
            color: _trailCardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 14, child: _buildTrailImage(trail)),
              Expanded(flex: 6, child: _buildTrailDetails(trail)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrailImage(_StudentTrail trail) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (trail.coverUrl != null)
          Image.network(
            trail.coverUrl!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildTrailCoverFallback(),
          )
        else
          _buildTrailCoverFallback(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x18000000), Color(0xE8050505)],
              stops: [0.0, 0.48, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrailDetails(_StudentTrail trail) {
    return Container(
      width: double.infinity,
      color: _trailCardBackground,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trail.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              height: 1.06,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.45,
            ),
          ),
          const Spacer(),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Abrir trilha',
                style: TextStyle(
                  color: UnlColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 3),
              Icon(
                Icons.arrow_forward_rounded,
                color: UnlColors.gold,
                size: 15,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrailCoverFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A482A), Color(0xFF201A10), Color(0xFF050505)],
        ),
      ),
      child: Center(
        child: Icon(Icons.school_outlined, color: UnlColors.gold, size: 38),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GridView.builder(
        itemCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1 / 1.88,
        ),
        itemBuilder: (_, __) => _skeleton(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: UnlColors.errorBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: UnlColors.error.withOpacity(0.34)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Não foi possível carregar as trilhas.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _loadError ?? '',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 13),
            TextButton.icon(
              onPressed: _loadScreen,
              style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0B10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withOpacity(0.10),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.school_outlined,
              color: UnlColors.gold.withOpacity(0.55),
              size: 46,
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhuma trilha encontrada',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.45,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Assim que novas trilhas forem publicadas, elas aparecerão aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.48),
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }

  String? _resolveCoverUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;

    final cleanPath = path.trim();

    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return cleanPath;
    }

    var normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');

    if (normalized.startsWith('public/')) {
      normalized = normalized.replaceFirst('public/', '');
      return 'https://www.universidadedelideres.com.br/$normalized';
    }

    if (normalized.startsWith('_next/')) {
      return 'https://www.universidadedelideres.com.br/$normalized';
    }

    normalized = normalized
        .replaceFirst('covers/', '')
        .replaceFirst('course-covers/', '');

    if (normalized.isEmpty) return null;

    return _supabase.storage.from('covers').getPublicUrl(normalized);
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((row) {
          return Map<String, dynamic>.from(row);
        })
        .toList(growable: false);
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') return null;

    return text;
  }

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }
}
