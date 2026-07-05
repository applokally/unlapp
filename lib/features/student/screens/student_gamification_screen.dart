// VERSÃO: v31
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../widgets/student_app_shell.dart';

const Color _gamificationBackground = Color(0xFF050609);
const Color _gamificationPanel = Color(0xFF0B0B0D);
const Color _gamificationPanelSoft = Color(0xFF111114);

class _GamificationProfile {
  const _GamificationProfile({
    required this.id,
    required this.fullName,
    required this.avatarUrl,
  });

  final String id;
  final String? fullName;
  final String? avatarUrl;
}

class _LedgerEntry {
  const _LedgerEntry({
    required this.id,
    required this.points,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final int points;
  final String? description;
  final DateTime? createdAt;
}

class _Reward {
  const _Reward({
    required this.id,
    required this.title,
    required this.description,
    required this.pointsRequired,
    required this.stock,
  });

  final String id;
  final String title;
  final String? description;
  final int pointsRequired;
  final int? stock;

  bool get isAvailable => stock == null || stock! > 0;
}

class _Redemption {
  const _Redemption({required this.pointsSpent, required this.status});

  final int pointsSpent;
  final String status;
}

class _Badge {
  const _Badge({
    required this.id,
    required this.title,
    required this.description,
    required this.requirementValue,
  });

  final String id;
  final String title;
  final String? description;
  final int requirementValue;
}

class _RankingEntry {
  const _RankingEntry({
    required this.userId,
    required this.fullName,
    required this.avatarUrl,
    required this.earnedPoints,
  });

  final String userId;
  final String? fullName;
  final String? avatarUrl;
  final int earnedPoints;
}

class StudentGamificationScreen extends StatefulWidget {
  const StudentGamificationScreen({super.key});

  static const String routeName = StudentAppRoutes.gamification;

  @override
  State<StudentGamificationScreen> createState() =>
      _StudentGamificationScreenState();
}

class _StudentGamificationScreenState extends State<StudentGamificationScreen> {
  final ScrollController _scrollController = ScrollController();

  _GamificationProfile? _profile;
  List<_LedgerEntry> _ledger = const [];
  List<_Reward> _rewards = const [];
  List<_Redemption> _redemptions = const [];
  List<_Badge> _badges = const [];
  List<_RankingEntry> _ranking = const [];

  bool _isLoading = true;
  String? _loadError;
  final Set<String> _redeemingRewardIds = <String>{};

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadGamification();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGamification() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Entre na sua conta para acompanhar sua evolução.';
      });
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('profiles')
            .select('id,full_name,avatar_url')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase
            .from('gamification_point_ledger')
            .select('id,points,description,created_at')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(80),
        _supabase
            .from('gamification_rewards')
            .select('id,title,description,points_required,stock,is_active')
            .eq('is_active', true)
            .order('points_required', ascending: true),
        _supabase
            .from('gamification_reward_redemptions')
            .select('points_spent,status')
            .eq('user_id', user.id),
        _supabase
            .from('gamification_badges')
            .select('id,title,description,requirement_value,is_active')
            .eq('is_active', true)
            .order('requirement_value', ascending: true),
        _supabase
            .from('gamification_public_ranking')
            .select('user_id,full_name,avatar_url,earned_points')
            .order('earned_points', ascending: false)
            .limit(50),
      ]);

      if (!mounted) return;

      setState(() {
        _profile = _profileFrom(results[0], user.id);
        _ledger = _rows(results[1]).map(_ledgerFrom).toList(growable: false);
        _rewards = _rows(results[2]).map(_rewardFrom).toList(growable: false);
        _redemptions = _rows(
          results[3],
        ).map(_redemptionFrom).toList(growable: false);
        _badges = _rows(results[4]).map(_badgeFrom).toList(growable: false);
        _ranking = _rows(results[5]).map(_rankingFrom).toList(growable: false);
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível carregar sua área de gamificação agora.';
      });
    }
  }

  Future<void> _redeemReward(_Reward reward) async {
    final user = _supabase.auth.currentUser;

    if (user == null || _redeemingRewardIds.contains(reward.id)) return;

    if (!reward.isAvailable) {
      _showMessage('Esta recompensa não está disponível no momento.');
      return;
    }

    if (_balance < reward.pointsRequired) {
      _showMessage(
        'Você ainda não possui pontos suficientes para este resgate.',
      );
      return;
    }

    setState(() {
      _redeemingRewardIds.add(reward.id);
    });

    try {
      await _supabase.from('gamification_reward_redemptions').insert({
        'reward_id': reward.id,
        'user_id': user.id,
        'points_spent': reward.pointsRequired,
        'status': 'pending',
      });

      if (!mounted) return;

      _showMessage('Resgate solicitado com sucesso!');
      await _loadGamification();
    } catch (_) {
      if (!mounted) return;

      _showMessage('Não foi possível solicitar este resgate agora.');
    } finally {
      if (mounted) {
        setState(() {
          _redeemingRewardIds.remove(reward.id);
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF181818),
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

  int get _earnedPoints =>
      _ledger.fold<int>(0, (sum, entry) => sum + entry.points);

  int get _spentPoints => _redemptions
      .where(
        (redemption) => const <String>{
          'pending',
          'approved',
          'delivered',
        }.contains(redemption.status.toLowerCase()),
      )
      .fold<int>(0, (sum, redemption) => sum + redemption.pointsSpent);

  int get _balance {
    final value = _earnedPoints - _spentPoints;
    return value < 0 ? 0 : value;
  }

  int get _myPosition {
    final userId = _supabase.auth.currentUser?.id;

    if (userId == null) return 0;

    return _ranking.indexWhere((entry) => entry.userId == userId) + 1;
  }

  List<_Badge> get _visibleBadges {
    if (_badges.isNotEmpty) return _badges;

    return const [
      _Badge(
        id: 'initial',
        title: 'Início',
        description: 'Sua jornada começou.',
        requirementValue: 100,
      ),
      _Badge(
        id: 'focus',
        title: 'Foco',
        description: 'Continue avançando.',
        requirementValue: 500,
      ),
      _Badge(
        id: 'mastery',
        title: 'Maestria',
        description: 'Conquiste novos patamares.',
        requirementValue: 1000,
      ),
    ];
  }

  int get _maxMilestone {
    final values = _visibleBadges
        .map((badge) => badge.requirementValue)
        .where((value) => value > 0);

    if (values.isEmpty) return 100;

    return values.reduce((largest, value) => value > largest ? value : largest);
  }

  int get _progressPercent {
    if (_maxMilestone <= 0) return 0;

    final progress = ((_earnedPoints / _maxMilestone) * 100).round();
    return progress.clamp(0, 100).toInt();
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.gamification,
      scrollController: _scrollController,
      backgroundColor: _gamificationBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: const Color(0xFF191A20),
        onRefresh: _loadGamification,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else
              SliverToBoxAdapter(child: _buildGamificationContent()),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildGamificationContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroBoard(),
          const SizedBox(height: 28),
          _buildSpecializationSection(),
          const SizedBox(height: 28),
          _buildRewardsSection(),
          const SizedBox(height: 28),
          _buildRankingSection(),
          const SizedBox(height: 28),
          _buildActivitySection(),
        ],
      ),
    );
  }

  Widget _buildHeroBoard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: _gamificationPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: UnlColors.gold.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sports_esports_rounded,
                color: UnlColors.gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'ARENA UNL',
                style: TextStyle(
                  color: UnlColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Lute pelo Topo.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 0.98,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.75,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Assista aulas, participe e transforme suas conquistas em pontos e recompensas.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 14,
              height: 1.48,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildHeroStat(
                  icon: Icons.bolt_rounded,
                  label: 'Saldo atual',
                  value: _formatPoints(_balance),
                  highlighted: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildHeroStat(
                  icon: Icons.my_location_rounded,
                  label: 'Seu rank',
                  value: _myPosition > 0 ? '#$_myPosition' : '—',
                  highlighted: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildPodium(),
        ],
      ),
    );
  }

  Widget _buildHeroStat({
    required IconData icon,
    required String label,
    required String value,
    required bool highlighted,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted
            ? UnlColors.gold.withOpacity(0.08)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? UnlColors.gold.withOpacity(0.28)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: highlighted
                ? UnlColors.gold
                : Colors.white.withOpacity(0.42),
            size: 17,
          ),
          const SizedBox(height: 9),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: highlighted
                  ? UnlColors.gold.withOpacity(0.82)
                  : Colors.white.withOpacity(0.50),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              height: 1.04,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodium() {
    final top = List<_RankingEntry?>.filled(3, null);

    for (var index = 0; index < _ranking.length && index < 3; index++) {
      top[index] = _ranking[index];
    }

    return SizedBox(
      height: 238,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _buildPodiumPlace(top[1], place: 2)),
          const SizedBox(width: 8),
          Expanded(child: _buildPodiumPlace(top[0], place: 1)),
          const SizedBox(width: 8),
          Expanded(child: _buildPodiumPlace(top[2], place: 3)),
        ],
      ),
    );
  }

  Widget _buildPodiumPlace(_RankingEntry? entry, {required int place}) {
    final isFirst = place == 1;
    final height = switch (place) {
      1 => 134.0,
      2 => 108.0,
      _ => 90.0,
    };

    final medalColor = switch (place) {
      1 => UnlColors.gold,
      2 => const Color(0xFFC8CDD5),
      _ => const Color(0xFFD79258),
    };

    final name = entry?.fullName?.trim();
    final firstName = name == null || name.isEmpty
        ? '—'
        : name.split(RegExp(r'\s+')).first;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(
          isFirst
              ? Icons.workspace_premium_rounded
              : Icons.emoji_events_rounded,
          color: medalColor,
          size: isFirst ? 30 : 24,
        ),
        const SizedBox(height: 6),
        _Avatar(
          name: name,
          avatarUrl: entry?.avatarUrl,
          size: isFirst ? 58 : 46,
          goldBorder: isFirst,
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
          decoration: BoxDecoration(
            color: medalColor.withOpacity(isFirst ? 0.18 : 0.10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border.all(color: medalColor.withOpacity(0.36)),
          ),
          child: Column(
            children: [
              Text(
                '$placeº',
                style: TextStyle(
                  color: medalColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatPoints(entry?.earnedPoints ?? 0)} pts',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.60),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpecializationSection() {
    return _SectionContainer(
      title: 'Trilha de Especialização',
      icon: Icons.track_changes_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: UnlColors.gold,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '$_progressPercent%',
            style: const TextStyle(
              color: UnlColors.gold,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      subtitle: 'Desbloqueie novas conquistas em sua jornada.',
      child: SizedBox(
        height: 162,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _visibleBadges.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, index) {
            return _buildBadgeNode(_visibleBadges[index]);
          },
        ),
      ),
    );
  }

  Widget _buildBadgeNode(_Badge badge) {
    final unlocked = _earnedPoints >= badge.requirementValue;
    final progress = badge.requirementValue <= 0
        ? 0.0
        : (_earnedPoints / badge.requirementValue).clamp(0.0, 1.0).toDouble();

    return Container(
      width: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unlocked
            ? UnlColors.gold.withOpacity(0.08)
            : Colors.white.withOpacity(0.025),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unlocked
              ? UnlColors.gold.withOpacity(0.35)
              : Colors.white.withOpacity(0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            unlocked ? Icons.bolt_rounded : Icons.lock_outline_rounded,
            color: unlocked ? UnlColors.gold : Colors.white.withOpacity(0.34),
            size: 27,
          ),
          const Spacer(),
          Text(
            badge.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unlocked ? Colors.white : Colors.white.withOpacity(0.62),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatPoints(badge.requirementValue)} pts',
            style: TextStyle(
              color: unlocked ? UnlColors.gold : Colors.white.withOpacity(0.38),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: unlocked ? UnlColors.gold : Colors.white.withOpacity(0.34),
              backgroundColor: Colors.white.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardsSection() {
    return _SectionContainer(
      title: 'Recompensas',
      icon: Icons.card_giftcard_rounded,
      subtitle: 'Troque seus pontos por benefícios especiais.',
      child: _rewards.isEmpty
          ? _buildEmptyInline(
              'Novas recompensas serão disponibilizadas em breve.',
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _rewards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildRewardItem(_rewards[index]);
              },
            ),
    );
  }

  Widget _buildRewardItem(_Reward reward) {
    final hasEnoughPoints = _balance >= reward.pointsRequired;
    final isRedeeming = _redeemingRewardIds.contains(reward.id);
    final canRedeem = hasEnoughPoints && reward.isAvailable && !isRedeeming;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _gamificationPanelSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reward.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (reward.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              reward.description!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_formatPoints(reward.pointsRequired)} pontos',
                  style: const TextStyle(
                    color: UnlColors.gold,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: 38,
                child: FilledButton(
                  onPressed: canRedeem ? () => _redeemReward(reward) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: UnlColors.gold,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white.withOpacity(0.08),
                    disabledForegroundColor: Colors.white.withOpacity(0.32),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  child: isRedeeming
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(reward.isAvailable ? 'RESGATAR' : 'INDISPONÍVEL'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRankingSection() {
    return _SectionContainer(
      title: 'Top Ranking',
      icon: Icons.emoji_events_rounded,
      subtitle: 'Veja quem está em destaque na Arena UNL.',
      child: _ranking.isEmpty
          ? _buildEmptyInline('A arena aguarda seus primeiros campeões.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ranking.length > 10 ? 10 : _ranking.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildRankingItem(_ranking[index], index + 1);
              },
            ),
    );
  }

  Widget _buildRankingItem(_RankingEntry entry, int position) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isCurrentUser = entry.userId == currentUserId;

    final placeColor = switch (position) {
      1 => UnlColors.gold,
      2 => const Color(0xFFC8CDD5),
      3 => const Color(0xFFD79258),
      _ => Colors.white.withOpacity(0.48),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? UnlColors.gold.withOpacity(0.10)
            : Colors.white.withOpacity(0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? UnlColors.gold.withOpacity(0.32)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$position',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: placeColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Avatar(
            name: entry.fullName,
            avatarUrl: entry.avatarUrl,
            size: 36,
            goldBorder: false,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.fullName?.trim().isNotEmpty == true
                  ? entry.fullName!.trim()
                  : 'Aluno',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrentUser ? UnlColors.gold : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_formatPoints(entry.earnedPoints)} pts',
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySection() {
    return _SectionContainer(
      title: 'Atividades recentes',
      icon: Icons.auto_awesome_rounded,
      subtitle: 'Acompanhe os pontos conquistados na sua jornada.',
      child: _ledger.isEmpty
          ? _buildEmptyInline('Suas próximas conquistas aparecerão aqui.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ledger.length > 10 ? 10 : _ledger.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildLedgerItem(_ledger[index]);
              },
            ),
    );
  }

  Widget _buildLedgerItem(_LedgerEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: UnlColors.gold, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description?.trim().isNotEmpty == true
                      ? entry.description!.trim()
                      : 'Conquista registrada',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(entry.createdAt),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+${_formatPoints(entry.points)}',
            style: const TextStyle(
              color: UnlColors.gold,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyInline(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.46),
          fontSize: 13,
          height: 1.48,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _skeleton(height: 500, radius: 24),
          const SizedBox(height: 14),
          _skeleton(height: 250, radius: 22),
          const SizedBox(height: 14),
          _skeleton(height: 260, radius: 22),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: UnlColors.errorBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: UnlColors.error.withOpacity(0.34)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: UnlColors.gold,
              size: 30,
            ),
            const SizedBox(height: 14),
            const Text(
              'Não foi possível abrir sua área de gamificação.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _loadError ?? '',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _loadGamification,
              style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton({required double height, required double radius}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  _GamificationProfile? _profileFrom(dynamic value, String userId) {
    if (value is! Map) return null;

    final row = Map<String, dynamic>.from(value);

    return _GamificationProfile(
      id: _text(row['id']) ?? userId,
      fullName: _text(row['full_name']),
      avatarUrl: _resolveAvatarUrl(_text(row['avatar_url'])),
    );
  }

  _LedgerEntry _ledgerFrom(Map<String, dynamic> row) {
    return _LedgerEntry(
      id: _text(row['id']) ?? '',
      points: _asInt(row['points']),
      description: _text(row['description']),
      createdAt: _date(row['created_at']),
    );
  }

  _Reward _rewardFrom(Map<String, dynamic> row) {
    return _Reward(
      id: _text(row['id']) ?? '',
      title: _text(row['title']) ?? 'Recompensa',
      description: _text(row['description']),
      pointsRequired: _asInt(row['points_required']),
      stock: _nullableInt(row['stock']),
    );
  }

  _Redemption _redemptionFrom(Map<String, dynamic> row) {
    return _Redemption(
      pointsSpent: _asInt(row['points_spent']),
      status: _text(row['status']) ?? '',
    );
  }

  _Badge _badgeFrom(Map<String, dynamic> row) {
    return _Badge(
      id: _text(row['id']) ?? '',
      title: _text(row['title']) ?? 'Conquista',
      description: _text(row['description']),
      requirementValue: _asInt(row['requirement_value']),
    );
  }

  _RankingEntry _rankingFrom(Map<String, dynamic> row) {
    return _RankingEntry(
      userId: _text(row['user_id']) ?? '',
      fullName: _text(row['full_name']),
      avatarUrl: _resolveAvatarUrl(_text(row['avatar_url'])),
      earnedPoints: _asInt(row['earned_points']),
    );
  }

  String? _resolveAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    return _supabase.storage
        .from('avatars')
        .getPublicUrl(url.replaceFirst(RegExp(r'^/+'), ''));
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
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

  int? _nullableInt(dynamic value) {
    if (value == null) return null;

    if (value is num) return value.toInt();

    return int.tryParse(value.toString());
  }

  DateTime? _date(dynamic value) {
    if (value == null) return null;

    return DateTime.tryParse(value.toString());
  }

  String _formatPoints(int value) {
    final negative = value < 0;
    final raw = value.abs().toString();
    final characters = raw.split('').reversed.toList();
    final buffer = StringBuffer();

    for (var index = 0; index < characters.length; index++) {
      if (index > 0 && index % 3 == 0) {
        buffer.write('.');
      }

      buffer.write(characters[index]);
    }

    final formatted = buffer.toString().split('').reversed.join();

    return negative ? '-$formatted' : formatted;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';

    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month • $hour:$minute';
  }
}

class _SectionContainer extends StatelessWidget {
  const _SectionContainer({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _gamificationPanel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: UnlColors.gold, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.50),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
    required this.goldBorder,
  });

  final String? name;
  final String? avatarUrl;
  final double size;
  final bool goldBorder;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1B1B1D),
        border: Border.all(
          color: goldBorder
              ? UnlColors.gold.withOpacity(0.80)
              : Colors.white.withOpacity(0.10),
          width: goldBorder ? 1.6 : 1,
        ),
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => _avatarText(initials),
              )
            : _avatarText(initials),
      ),
    );
  }

  Widget _avatarText(String initials) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: UnlColors.gold,
          fontSize: size * 0.30,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _initials(String? value) {
    final clean = value?.trim();

    if (clean == null || clean.isEmpty) return '—';

    final parts = clean.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);

    if (parts.isEmpty) return '—';

    final items = parts.toList();

    if (items.length == 1) {
      return items.first.substring(0, 1).toUpperCase();
    }

    return '${items.first.substring(0, 1)}${items.last.substring(0, 1)}'
        .toUpperCase();
  }
}
