// VERSÃO: v31
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/unl_colors.dart';
import '../../widgets/student_app_shell.dart';
import '../data/live_repository.dart';

const Color _liveBackground = Color(0xFF050609);

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, this.initialLiveId});

  static const String routeName = StudentAppRoutes.live;

  final String? initialLiveId;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final StudentLiveRepository _repository = StudentLiveRepository();
  final ScrollController _scrollController = ScrollController();

  Timer? _refreshTimer;
  List<StudentLive> _lives = const [];
  StudentLive? _selectedLive;
  VideoPlayerController? _videoController;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isPreparingPlayer = false;
  String? _loadError;
  String? _playerError;

  @override
  void initState() {
    super.initState();
    _loadLives();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadLives(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    _disposeVideoController();
    super.dispose();
  }

  Future<void> _loadLives({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final lives = await _repository.loadVisibleLives();

      if (!mounted) return;

      final preferredId = widget.initialLiveId?.trim();
      final currentId = _selectedLive?.id;
      final selected = _selectLive(
        lives,
        preferredId: preferredId?.isNotEmpty == true ? preferredId : currentId,
      );

      final selectedChanged = selected?.id != _selectedLive?.id;

      setState(() {
        _lives = lives;
        _selectedLive = selected;
        _isLoading = false;
        _loadError = null;
      });

      if (selectedChanged || _videoController == null) {
        await _preparePlayer(selected);
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível carregar as transmissões.';
      });
    }
  }

  StudentLive? _selectLive(List<StudentLive> lives, {String? preferredId}) {
    final cleanPreferredId = preferredId?.trim();

    if (cleanPreferredId != null && cleanPreferredId.isNotEmpty) {
      for (final live in lives) {
        if (live.id == cleanPreferredId) return live;
      }
    }

    for (final live in lives) {
      if (live.phaseAt(DateTime.now().toUtc()) == StudentLivePhase.live) {
        return live;
      }
    }

    for (final live in lives) {
      if (live.phaseAt(DateTime.now().toUtc()) == StudentLivePhase.scheduled) {
        return live;
      }
    }

    return lives.isEmpty ? null : lives.first;
  }

  Future<void> _selectAndPrepareLive(StudentLive live) async {
    if (live.id == _selectedLive?.id) return;

    setState(() {
      _selectedLive = live;
    });

    await _preparePlayer(live);
  }

  Future<void> _preparePlayer(StudentLive? live) async {
    await _disposeVideoController();

    final source = _playableNativeSource(live);

    if (source == null) {
      if (!mounted) return;

      setState(() {
        _isPreparingPlayer = false;
        _playerError = null;
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _isPreparingPlayer = true;
      _playerError = null;
    });

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(source));
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
        _isPreparingPlayer = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isPreparingPlayer = false;
        _playerError = 'Não foi possível abrir esta transmissão agora.';
      });
    }
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;

    if (controller != null) {
      await controller.dispose();
    }
  }

  String? _playableNativeSource(StudentLive? live) {
    if (live == null) return null;

    final phase = live.phaseAt(DateTime.now().toUtc());
    final rawUrl = switch (phase) {
      StudentLivePhase.live => live.liveUrl,
      StudentLivePhase.ended => live.hasRecording ? live.recordingUrl : null,
      StudentLivePhase.scheduled || StudentLivePhase.cancelled => null,
    };

    final url = rawUrl?.trim();

    if (url == null || url.isEmpty) return null;

    final type = live.broadcastType.toLowerCase();

    if (type == 'youtube' ||
        type == 'vimeo' ||
        type == 'zoom' ||
        type == 'embed') {
      return null;
    }

    final uri = Uri.tryParse(url);

    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }

    return uri.toString();
  }

  Future<void> _togglePlayback() async {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selectedLive = _selectedLive;
    final hasScheduledHero =
        !_isLoading &&
        _loadError == null &&
        selectedLive != null &&
        selectedLive.phaseAt(DateTime.now().toUtc()) ==
            StudentLivePhase.scheduled;

    return StudentAppShell(
      activeDestination: StudentAppDestination.live,
      scrollController: _scrollController,
      backgroundColor: _liveBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: const Color(0xFF191A20),
        onRefresh: () async {
          setState(() => _isRefreshing = true);
          await _loadLives();
          if (mounted) setState(() => _isRefreshing = false);
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            if (hasScheduledHero)
              SliverToBoxAdapter(child: _buildScheduledHero(selectedLive!))
            else ...[
              const SliverToBoxAdapter(child: SizedBox(height: 104)),
              SliverToBoxAdapter(child: _buildPageHeader()),
            ],
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else if (selectedLive == null)
              SliverToBoxAdapter(child: _buildEmptyState())
            else ...[
              SliverToBoxAdapter(
                child: hasScheduledHero
                    ? _buildScheduledLiveContent(selectedLive!)
                    : _buildSelectedLive(),
              ),
              if (_otherLives.isNotEmpty)
                SliverToBoxAdapter(child: _buildOtherLives()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  List<StudentLive> get _otherLives {
    final selectedId = _selectedLive?.id;

    return _lives.where((live) => live.id != selectedId).toList();
  }

  Widget _buildPageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ao vivo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                height: 1.08,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.55,
              ),
            ),
          ),
          IconButton(
            onPressed: _isRefreshing
                ? null
                : () async {
                    setState(() => _isRefreshing = true);
                    await _loadLives();
                    if (mounted) setState(() => _isRefreshing = false);
                  },
            tooltip: 'Atualizar',
            icon: _isRefreshing
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: UnlColors.gold,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 24),
            color: UnlColors.gold,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedLive() {
    final live = _selectedLive!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPlayer(live),
          const SizedBox(height: 16),
          _buildLiveInformation(live),
        ],
      ),
    );
  }

  Widget _buildScheduledHero(StudentLive live) {
    final screenHeight = MediaQuery.of(context).size.height;
    final heroHeight = (screenHeight * 0.58).clamp(500.0, 650.0).toDouble();

    return SizedBox(
      width: double.infinity,
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildPlayerBackground(live),
          const Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF050609),
                      Color(0xFF050609),
                      Color(0x00050609),
                    ],
                    stops: [0.0, 0.10, 0.46],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00050609),
                      Color(0x00050609),
                      Color(0xFF050609),
                    ],
                    stops: [0.0, 0.48, 1.0],
                  ),
                ),
              ),
            ],
          ),
          Positioned(top: 134, left: 0, right: 0, child: _buildPageHeader()),
          Positioned(
            left: 28,
            right: 28,
            bottom: 34,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: UnlColors.gold,
                  size: 44,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Transmissão agendada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Esta sala será atualizada automaticamente quando a transmissão começar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledLiveContent(StudentLive live) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 0),
      child: _buildScheduledLiveInformation(live),
    );
  }

  Widget _buildScheduledLiveInformation(StudentLive live) {
    final phase = live.phaseAt(DateTime.now().toUtc());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                live.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.45,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildStatusBadge(phase),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          live.displayDescription,
          style: TextStyle(
            color: Colors.white.withOpacity(0.60),
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 20,
          runSpacing: 14,
          children: [
            _buildInformationItem(
              icon: Icons.calendar_today_outlined,
              label: 'Data',
              value: _formatDate(live.startsAt),
            ),
            _buildInformationItem(
              icon: Icons.access_time_rounded,
              label: 'Horário',
              value: _formatTime(live.startsAt),
            ),
            if (live.presenterName != null && live.presenterName!.isNotEmpty)
              _buildInformationItem(
                icon: Icons.videocam_outlined,
                label: 'Apresentador',
                value: live.presenterName!,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlayer(StudentLive live) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF101116),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPlayerBackground(live),
              if (_isPreparingPlayer)
                const Center(
                  child: CircularProgressIndicator(color: UnlColors.gold),
                )
              else if (_videoController?.value.isInitialized == true)
                _buildNativeVideoPlayer()
              else
                _buildPlayerMessage(live),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerBackground(StudentLive live) {
    if (live.coverUrl != null) {
      return Image.network(
        live.coverUrl!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildFallbackPlayerBackground(),
      );
    }

    return _buildFallbackPlayerBackground();
  }

  Widget _buildFallbackPlayerBackground() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A3920), Color(0xFF16130E), Color(0xFF050609)],
        ),
      ),
    );
  }

  Widget _buildNativeVideoPlayer() {
    final controller = _videoController!;

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _togglePlayback,
              child: Center(
                child: AnimatedOpacity(
                  opacity: controller.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 33,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildVideoProgress(controller),
        ),
      ],
    );
  }

  Widget _buildVideoProgress(VideoPlayerController controller) {
    final duration = controller.value.duration.inMilliseconds;
    final position = controller.value.position.inMilliseconds;
    final progress = duration <= 0
        ? 0.0
        : (position / duration).clamp(0.0, 1.0);

    return Container(
      height: 5,
      color: Colors.black.withOpacity(0.38),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        child: Container(color: UnlColors.gold),
      ),
    );
  }

  Widget _buildPlayerMessage(StudentLive live) {
    final phase = live.phaseAt(DateTime.now().toUtc());
    final isScheduled = phase == StudentLivePhase.scheduled;
    final isEnded = phase == StudentLivePhase.ended;

    final title = isScheduled
        ? 'Transmissão agendada'
        : isEnded
        ? live.hasRecording
              ? 'Gravação disponível'
              : 'Live encerrada'
        : _playerError ?? 'Transmissão indisponível';

    final description = isScheduled
        ? 'Esta sala será atualizada automaticamente quando a transmissão começar.'
        : isEnded
        ? live.hasRecording
              ? 'A gravação será exibida aqui quando a fonte estiver disponível.'
              : 'Esta transmissão foi encerrada e não possui gravação disponível.'
        : _playerError ?? _nativePlaybackNotice(live);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x44050609), Color(0xED050609)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isScheduled ? Icons.schedule_rounded : Icons.radio_rounded,
                color: UnlColors.gold,
                size: 38,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nativePlaybackNotice(StudentLive live) {
    switch (live.broadcastType.toLowerCase()) {
      case 'zoom':
        return 'A entrada nativa pelo Zoom será conectada na próxima etapa desta área.';
      case 'youtube':
      case 'vimeo':
        return 'Esta transmissão será aberta pelo player nativo configurado para esta fonte.';
      case 'embed':
        return 'A fonte desta transmissão ainda não foi disponibilizada para reprodução nativa.';
      default:
        return 'O link da transmissão ainda não está disponível.';
    }
  }

  Widget _buildLiveInformation(StudentLive live) {
    final phase = live.phaseAt(DateTime.now().toUtc());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF101116),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  live.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildStatusBadge(phase),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            live.displayDescription,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontSize: 13.5,
              height: 1.48,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _buildInformationItem(
                icon: Icons.calendar_today_outlined,
                label: 'Data',
                value: _formatDate(live.startsAt),
              ),
              _buildInformationItem(
                icon: Icons.access_time_rounded,
                label: 'Horário',
                value: _formatTime(live.startsAt),
              ),
              if (live.presenterName != null && live.presenterName!.isNotEmpty)
                _buildInformationItem(
                  icon: Icons.videocam_outlined,
                  label: 'Apresentador',
                  value: live.presenterName!,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(StudentLivePhase phase) {
    final (label, background, foreground) = switch (phase) {
      StudentLivePhase.live => (
        'Ao vivo',
        const Color(0xFFDB554E),
        Colors.white,
      ),
      StudentLivePhase.scheduled => ('Agendada', UnlColors.gold, Colors.black),
      StudentLivePhase.ended => (
        'Encerrada',
        const Color(0x1FFFFFFF),
        Colors.white70,
      ),
      StudentLivePhase.cancelled => (
        'Cancelada',
        const Color(0xFFDB554E),
        Colors.white,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.45,
        ),
      ),
    );
  }

  Widget _buildInformationItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: UnlColors.gold, size: 16),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.34),
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.75,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: Colors.white.withOpacity(0.77),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtherLives() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 30, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Outras transmissões',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.35,
            ),
          ),
          const SizedBox(height: 13),
          ..._otherLives.map(_buildLiveListItem),
        ],
      ),
    );
  }

  Widget _buildLiveListItem(StudentLive live) {
    final phase = live.phaseAt(DateTime.now().toUtc());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _selectAndPrepareLive(live),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF101116),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: SizedBox(
                    width: 88,
                    height: 56,
                    child: live.coverUrl != null
                        ? Image.network(
                            live.coverUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildListCoverFallback(),
                          )
                        : _buildListCoverFallback(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        live.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_formatDate(live.startsAt)} • ${_formatTime(live.startsAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.46),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _buildStatusBadge(phase),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListCoverFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5E4B2A), Color(0xFF14120E)],
        ),
      ),
      child: Center(
        child: Icon(Icons.radio_rounded, color: UnlColors.gold, size: 23),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          _skeleton(width: double.infinity, height: 210, radius: 22),
          const SizedBox(height: 16),
          _skeleton(width: double.infinity, height: 150, radius: 18),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
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
              'Não foi possível atualizar as lives.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
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
              onPressed: _loadLives,
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 122, 28, 36),
      child: Column(
        children: [
          Icon(Icons.sensors_rounded, color: UnlColors.gold, size: 48),
          SizedBox(height: 20),
          Text(
            'Nenhuma transmissão disponível',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          SizedBox(height: 11),
          Text(
            'Quando uma live estiver agendada ou ao vivo, ela aparecerá aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: UnlColors.textSecondary,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  String? _text(dynamic value) {
    final raw = value?.toString();
    final text = raw?.trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return text;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Data a definir';

    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');

    return '$day/$month/${local.year}';
  }

  String _formatTime(DateTime? value) {
    if (value == null) return 'Horário a definir';

    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }
}
