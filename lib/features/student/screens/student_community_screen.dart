// VERSÃO: v31
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/student_app_shell.dart';

const Color _communityBackground = Color(0xFF000000);
const Color _communityGold = Color(0xFFDBC094);

enum _CommunityTab { forYou, following, alerts, questions, networking, lives }

class StudentCommunityScreen extends StatefulWidget {
  const StudentCommunityScreen({super.key});

  static const String routeName = StudentAppRoutes.community;

  @override
  State<StudentCommunityScreen> createState() => _StudentCommunityScreenState();
}

class _StudentCommunityScreenState extends State<StudentCommunityScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _composerController = TextEditingController();
  final Map<String, TextEditingController> _commentControllers = {};

  _CommunityTab _activeTab = _CommunityTab.forYou;
  List<_CommunityChannel> _channels = const [];
  List<_FeedPost> _posts = const [];
  _CommunityProfile? _currentUser;
  String _selectedChannelId = '';
  String _searchTerm = '';
  String _submittingCommentPostId = '';
  final Map<String, bool> _openComments = {};
  final Map<String, int> _visibleComments = {};
  bool _isLoading = true;
  bool _isPublishing = false;
  bool _showBackToTop = false;
  String _focusedNotificationId = '';

  @override
  void initState() {
    super.initState();
    _focusedNotificationId = Uri.base.queryParameters['notificacao'] ?? '';
    _scrollController.addListener(_handleScroll);
    _loadCommunity();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    _composerController.dispose();
    for (final controller in _commentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 420;

    if (shouldShow != _showBackToTop && mounted) {
      setState(() => _showBackToTop = shouldShow);
    }
  }

  Future<void> _loadCommunity({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final user = _supabase.auth.currentUser;
      final currentProfile = await _loadCurrentProfile(user?.id);

      final channelsResponse = await _supabase
          .from('community_channels')
          .select(
            'id,name,slug,description,is_locked,is_active,sort_order,created_at',
          )
          .eq('is_active', true)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: false);

      final postsResponse = await _supabase
          .from('community_posts')
          .select(
            'id,channel_id,author_id,title,body,image_path,status,is_pinned,allow_comments,published_at,created_at',
          )
          .eq('status', 'published')
          .order('published_at', ascending: false)
          .limit(100);

      final notificationsResponse = await _supabase
          .from('community_notifications')
          .select(
            'id,title,body,target_type,channel_id,status,sent_at,created_at',
          )
          .eq('status', 'sent')
          .order('sent_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);

      final channels = _toRows(
        channelsResponse,
      ).map(_CommunityChannel.fromMap).toList(growable: false);
      final postRows = _toRows(postsResponse);
      final notificationRows = _toRows(notificationsResponse);
      final postIds = postRows
          .map((row) => _stringValue(row['id']))
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      final commentsResponse = postIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _supabase
                .from('community_comments')
                .select('id,post_id,author_id,body,status,created_at')
                .inFilter('post_id', postIds)
                .eq('status', 'published')
                .order('created_at', ascending: false);

      final reactionsResponse = postIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _supabase
                .from('community_reactions')
                .select('id,post_id,user_id,reaction_type')
                .inFilter('post_id', postIds)
                .eq('reaction_type', 'like');

      final savedResponse = user == null || postIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _supabase
                .from('community_saved_posts')
                .select('id,post_id,user_id')
                .eq('user_id', user.id)
                .inFilter('post_id', postIds);

      final commentRows = _toRows(commentsResponse);
      final reactionRows = _toRows(reactionsResponse);
      final savedRows = _toRows(savedResponse);

      final authorIds = <String>{
        for (final row in postRows) _stringValue(row['author_id']),
        for (final row in commentRows) _stringValue(row['author_id']),
      }..removeWhere((id) => id.isEmpty);

      final profilesResponse = authorIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _supabase
                .from('profiles')
                .select('id,full_name,avatar_url,role')
                .inFilter('id', authorIds.toList(growable: false));

      final profilesById = <String, _CommunityProfile>{
        for (final row in _toRows(profilesResponse))
          _stringValue(row['id']): _CommunityProfile.fromMap(row),
      };

      if (currentProfile != null) {
        profilesById[currentProfile.id] = currentProfile;
      }

      final channelsById = <String, _CommunityChannel>{
        for (final channel in channels) channel.id: channel,
      };

      final commentsByPost = <String, List<_FeedComment>>{};
      for (final row in commentRows) {
        final postId = _stringValue(row['post_id']);
        if (postId.isEmpty) {
          continue;
        }

        final author = profilesById[_stringValue(row['author_id'])];
        final authorName = author?.fullName.isNotEmpty == true
            ? author!.fullName
            : 'Aluno';

        commentsByPost
            .putIfAbsent(postId, () => <_FeedComment>[])
            .add(
              _FeedComment(
                id: _stringValue(row['id']),
                author: authorName,
                initials: _initials(authorName),
                avatarUrl: _resolveAvatarUrl(author?.avatarUrl),
                body: _stringValue(row['body']),
                time: _relativeTime(_stringValue(row['created_at'])),
              ),
            );
      }

      final likesByPost = <String, int>{};
      final likedPostIds = <String>{};
      for (final row in reactionRows) {
        final postId = _stringValue(row['post_id']);
        if (postId.isEmpty) {
          continue;
        }

        likesByPost[postId] = (likesByPost[postId] ?? 0) + 1;
        if (_stringValue(row['user_id']) == user?.id) {
          likedPostIds.add(postId);
        }
      }

      final savedPostIds = <String>{
        for (final row in savedRows) _stringValue(row['post_id']),
      }..removeWhere((id) => id.isEmpty);

      final mappedPosts = <_FeedPost>[];
      for (final row in postRows) {
        final id = _stringValue(row['id']);
        final author = profilesById[_stringValue(row['author_id'])];
        final channel = channelsById[_stringValue(row['channel_id'])];
        final isOfficial =
            (author?.role.isNotEmpty == true && author!.role != 'member') ||
            _tabForSlug(channel?.slug) == _CommunityTab.alerts;
        final authorName = author?.fullName.isNotEmpty == true
            ? author!.fullName
            : 'Aluno';
        final comments = commentsByPost[id] ?? const <_FeedComment>[];

        mappedPosts.add(
          _FeedPost(
            id: id,
            tab: _tabForSlug(channel?.slug),
            authorId: _stringValue(row['author_id']),
            author: isOfficial ? 'Universidade de Líderes' : authorName,
            username: isOfficial
                ? '@universidadedelideres'
                : _userHandle(authorName),
            initials: isOfficial ? 'UL' : _initials(authorName),
            avatarUrl: isOfficial ? '' : _resolveAvatarUrl(author?.avatarUrl),
            time: _relativeTime(
              _stringValue(row['published_at']).isNotEmpty
                  ? _stringValue(row['published_at'])
                  : _stringValue(row['created_at']),
            ),
            channelId: _stringValue(row['channel_id']),
            channel: channel?.name.isNotEmpty == true
                ? channel!.name
                : 'Comunidade',
            text: _stringValue(row['body']),
            comments: comments.length,
            likes: likesByPost[id] ?? 0,
            liked: likedPostIds.contains(id),
            saved: savedPostIds.contains(id),
            verified: isOfficial,
            official: isOfficial,
            isNotification: false,
            notificationId: '',
            allowComments: _boolValue(row['allow_comments'], fallback: true),
            commentsList: comments,
          ),
        );
      }

      final mappedNotifications = <_FeedPost>[];
      for (final row in notificationRows) {
        final channel = channelsById[_stringValue(row['channel_id'])];
        final title = _stringValue(row['title']).trim();
        final body = _stringValue(row['body']).trim();
        final message = <String>[
          title,
          body,
        ].where((part) => part.isNotEmpty).join('\n\n');

        if (message.isEmpty) {
          continue;
        }

        mappedNotifications.add(
          _FeedPost(
            id: 'notification-${_stringValue(row['id'])}',
            tab: _CommunityTab.alerts,
            authorId: 'unl',
            author: 'Universidade de Líderes',
            username: '@universidadedelideres',
            initials: 'UL',
            avatarUrl: '',
            time: _relativeTime(
              _stringValue(row['sent_at']).isNotEmpty
                  ? _stringValue(row['sent_at'])
                  : _stringValue(row['created_at']),
            ),
            channelId: _stringValue(row['channel_id']),
            channel: channel?.name.isNotEmpty == true
                ? channel!.name
                : 'Avisos oficiais',
            text: message,
            comments: 0,
            likes: 0,
            liked: false,
            saved: false,
            verified: true,
            official: true,
            isNotification: true,
            notificationId: _stringValue(row['id']),
            allowComments: false,
            commentsList: const <_FeedComment>[],
          ),
        );
      }

      final firstAvailableChannel = channels
          .cast<_CommunityChannel?>()
          .firstWhere(
            (channel) => channel != null && !channel.isLocked,
            orElse: () => null,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentUser =
            currentProfile ??
            (user == null
                ? null
                : _CommunityProfile(
                    id: user.id,
                    fullName: user.email?.split('@').first ?? 'Aluno',
                    avatarUrl: '',
                    role: 'member',
                  ));
        _channels = channels;
        _posts = <_FeedPost>[...mappedNotifications, ...mappedPosts];
        if (_selectedChannelId.isEmpty ||
            !channels.any(
              (channel) =>
                  channel.id == _selectedChannelId && !channel.isLocked,
            )) {
          _selectedChannelId = firstAvailableChannel?.id ?? '';
        }
      });
    } catch (_) {
      if (mounted) {
        _showMessage('Não foi possível carregar a comunidade agora.');
      }
    } finally {
      if (mounted && showLoader) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<_CommunityProfile?> _loadCurrentProfile(String? userId) async {
    if (userId == null || userId.isEmpty) {
      return null;
    }

    try {
      final response = await _supabase
          .from('profiles')
          .select('id,full_name,avatar_url,role')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return _CommunityProfile.fromMap(Map<String, dynamic>.from(response));
    } catch (_) {
      return null;
    }
  }

  List<_FeedPost> get _visiblePosts {
    final normalizedSearch = _searchTerm.trim().toLowerCase();

    return _posts
        .where((post) {
          final tabMatches = switch (_activeTab) {
            _CommunityTab.forYou => true,
            _CommunityTab.following => !post.official,
            _ => post.tab == _activeTab,
          };

          if (!tabMatches) {
            return false;
          }

          if (normalizedSearch.isEmpty) {
            return true;
          }

          return '${post.author} ${post.channel} ${post.text}'
              .toLowerCase()
              .contains(normalizedSearch);
        })
        .toList(growable: false);
  }

  Map<_CommunityTab, int> get _tabCounts {
    final counts = <_CommunityTab, int>{};
    for (final post in _posts) {
      counts[post.tab] = (counts[post.tab] ?? 0) + 1;
    }
    return counts;
  }

  TextEditingController _commentControllerFor(String postId) {
    return _commentControllers.putIfAbsent(postId, TextEditingController.new);
  }

  Future<void> _publishPost() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _selectedChannelId.isEmpty || _isPublishing) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Entre na sua conta para publicar na comunidade.');
      return;
    }

    setState(() => _isPublishing = true);

    try {
      await _supabase.from('community_posts').insert({
        'channel_id': _selectedChannelId,
        'author_id': user.id,
        'title': null,
        'body': text,
        'status': 'published',
        'published_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (!mounted) {
        return;
      }

      _composerController.clear();
      setState(() => _activeTab = _CommunityTab.forYou);
      await _loadCommunity(showLoader: false);

      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {
      _showMessage('Não foi possível publicar agora. Tente novamente.');
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  Future<void> _toggleLike(_FeedPost post) async {
    if (post.isNotification) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Entre na sua conta para curtir.');
      return;
    }

    setState(() {
      _posts = _posts
          .map(
            (item) => item.id == post.id
                ? item.copyWith(
                    liked: !item.liked,
                    likes: item.liked
                        ? (item.likes > 0 ? item.likes - 1 : 0)
                        : item.likes + 1,
                  )
                : item,
          )
          .toList(growable: false);
    });

    try {
      if (post.liked) {
        await _supabase
            .from('community_reactions')
            .delete()
            .eq('post_id', post.id)
            .eq('user_id', user.id)
            .eq('reaction_type', 'like');
      } else {
        await _supabase.from('community_reactions').insert({
          'post_id': post.id,
          'user_id': user.id,
          'reaction_type': 'like',
        });
      }
    } catch (_) {
      _showMessage('Não foi possível atualizar a curtida agora.');
      await _loadCommunity(showLoader: false);
    }
  }

  Future<void> _toggleSavedPost(_FeedPost post) async {
    if (post.isNotification) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Entre na sua conta para salvar esta publicação.');
      return;
    }

    setState(() {
      _posts = _posts
          .map(
            (item) =>
                item.id == post.id ? item.copyWith(saved: !item.saved) : item,
          )
          .toList(growable: false);
    });

    try {
      if (post.saved) {
        await _supabase
            .from('community_saved_posts')
            .delete()
            .eq('post_id', post.id)
            .eq('user_id', user.id);
      } else {
        await _supabase.from('community_saved_posts').insert({
          'post_id': post.id,
          'user_id': user.id,
        });
      }
    } catch (_) {
      _showMessage('Não foi possível atualizar seus itens salvos agora.');
      await _loadCommunity(showLoader: false);
    }
  }

  void _toggleComments(_FeedPost post) {
    if (!post.allowComments || post.isNotification) {
      return;
    }

    setState(() {
      _openComments[post.id] = !(_openComments[post.id] ?? false);
      _visibleComments.putIfAbsent(post.id, () => 5);
    });
  }

  void _showMoreComments(String postId) {
    setState(() {
      _visibleComments[postId] = (_visibleComments[postId] ?? 5) + 5;
    });
  }

  Future<void> _submitComment(_FeedPost post) async {
    if (!post.allowComments || post.isNotification) {
      return;
    }

    final controller = _commentControllerFor(post.id);
    final body = controller.text.trim();
    if (body.isEmpty || _submittingCommentPostId.isNotEmpty) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Entre na sua conta para comentar.');
      return;
    }

    setState(() => _submittingCommentPostId = post.id);

    try {
      await _supabase.from('community_comments').insert({
        'post_id': post.id,
        'author_id': user.id,
        'body': body,
        'status': 'published',
      });

      if (!mounted) {
        return;
      }

      controller.clear();
      setState(() {
        _openComments[post.id] = true;
        _visibleComments.putIfAbsent(post.id, () => 5);
      });
      await _loadCommunity(showLoader: false);
    } catch (_) {
      _showMessage('Não foi possível enviar seu comentário agora.');
    } finally {
      if (mounted) {
        setState(() => _submittingCommentPostId = '');
      }
    }
  }

  Future<void> _showReportDialog(_FeedPost post) async {
    if (post.isNotification) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Entre na sua conta para enviar uma denúncia.');
      return;
    }

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF000000),
          title: const Text(
            'Denunciar publicação',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              hintText: 'Conte o que aconteceu para nossa equipe analisar.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _communityGold,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );

    final reason = controller.text.trim();
    controller.dispose();

    if (confirmed != true || reason.isEmpty) {
      return;
    }

    try {
      await _supabase.from('community_reports').insert({
        'post_id': post.id,
        'reporter_id': user.id,
        'reason': reason,
        'message': null,
        'status': 'open',
      });
      _showMessage('Denúncia recebida. Nossa equipe fará a análise.');
    } catch (_) {
      _showMessage('Não foi possível enviar a denúncia agora.');
    }
  }

  Future<void> _confirmDelete(_FeedPost post) async {
    if (post.isNotification ||
        post.authorId != _supabase.auth.currentUser?.id) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF000000),
          title: const Text(
            'Excluir publicação?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          content: const Text(
            'Esta publicação deixará de aparecer na comunidade.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _communityGold,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _supabase
          .from('community_posts')
          .update({'status': 'deleted'})
          .eq('id', post.id)
          .eq('author_id', _supabase.auth.currentUser!.id);
      await _loadCommunity(showLoader: false);
      _showMessage('Sua publicação foi excluída.');
    } catch (_) {
      _showMessage('Não foi possível excluir esta publicação agora.');
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
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF000000),
        ),
      );
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }

    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.community,
      scrollController: _scrollController,
      backgroundColor: _communityBackground,
      body: Stack(
        children: [
          RefreshIndicator(
            color: Colors.black,
            backgroundColor: _communityGold,
            onRefresh: () => _loadCommunity(showLoader: false),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 128)),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _buildPageContent(context),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 116)),
              ],
            ),
          ),
          if (_showBackToTop)
            Positioned(
              right: 18,
              bottom: 104,
              child: SafeArea(
                top: false,
                child: Material(
                  color: _communityGold,
                  borderRadius: BorderRadius.circular(24),
                  elevation: 8,
                  child: InkWell(
                    onTap: _scrollToTop,
                    borderRadius: BorderRadius.circular(24),
                    child: const SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPageContent(BuildContext context) {
    final visiblePosts = _visiblePosts;
    final tabCounts = _tabCounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text(
            'Feed',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.45,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchTerm = value),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDecoration(
              hintText: 'Buscar na comunidade',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _searchTerm.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchTerm = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Limpar busca',
                    ),
              filled: true,
              fillColor: Colors.black,
              borderRadius: 26,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              _CommunityTabButton(
                label: 'Para você',
                active: _activeTab == _CommunityTab.forYou,
                onTap: () => setState(() => _activeTab = _CommunityTab.forYou),
              ),
              _CommunityTabButton(
                label: 'Seguindo',
                active: _activeTab == _CommunityTab.following,
                onTap: () =>
                    setState(() => _activeTab = _CommunityTab.following),
              ),
              _CommunityTabButton(
                label: 'Avisos',
                count: tabCounts[_CommunityTab.alerts],
                active: _activeTab == _CommunityTab.alerts,
                onTap: () => setState(() => _activeTab = _CommunityTab.alerts),
              ),
              _CommunityTabButton(
                label: 'Dúvidas',
                count: tabCounts[_CommunityTab.questions],
                active: _activeTab == _CommunityTab.questions,
                onTap: () =>
                    setState(() => _activeTab = _CommunityTab.questions),
              ),
              _CommunityTabButton(
                label: 'Networking',
                count: tabCounts[_CommunityTab.networking],
                active: _activeTab == _CommunityTab.networking,
                onTap: () =>
                    setState(() => _activeTab = _CommunityTab.networking),
              ),
              _CommunityTabButton(
                label: 'Lives',
                count: tabCounts[_CommunityTab.lives],
                active: _activeTab == _CommunityTab.lives,
                onTap: () => setState(() => _activeTab = _CommunityTab.lives),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),
        _buildComposer(),
        const Divider(height: 1, color: Colors.white10),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 68),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _communityGold,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Carregando comunidade...',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          )
        else if (visiblePosts.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 58, 28, 62),
            child: Column(
              children: [
                Text(
                  'Nenhuma publicação por aqui',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 9),
                Text(
                  'Compartilhe uma dúvida, uma experiência ou escolha outro canal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          for (final post in visiblePosts)
            _FeedPostCard(
              post: post,
              currentUserId: _currentUser?.id ?? '',
              highlighted:
                  _focusedNotificationId.isNotEmpty &&
                  post.notificationId == _focusedNotificationId,
              commentsOpen: _openComments[post.id] ?? false,
              visibleComments: _visibleComments[post.id] ?? 5,
              commentController: _commentControllerFor(post.id),
              submittingComment: _submittingCommentPostId == post.id,
              onLike: () => _toggleLike(post),
              onToggleComments: () => _toggleComments(post),
              onSave: () => _toggleSavedPost(post),
              onReport: () => _showReportDialog(post),
              onDelete: () => _confirmDelete(post),
              onShowMoreComments: () => _showMoreComments(post.id),
              onSubmitComment: () => _submitComment(post),
            ),
      ],
    );
  }

  Widget _buildComposer() {
    final availableChannels = _channels
        .where((channel) => !channel.isLocked)
        .toList(growable: false);
    final canPublish =
        _composerController.text.trim().isNotEmpty &&
        _selectedChannelId.isNotEmpty &&
        !_isPublishing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommunityAvatar(
            initials: _initials(_currentUser?.fullName),
            avatarUrl: _resolveAvatarUrl(_currentUser?.avatarUrl),
            official: true,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _composerController,
                  onChanged: (_) => setState(() {}),
                  minLines: 3,
                  maxLines: 6,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Compartilhe uma dúvida ou experiência...',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(0, 2, 0, 8),
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                const SizedBox(height: 11),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 10,
                  spacing: 10,
                  children: [
                    if (availableChannels.isNotEmpty)
                      Container(
                        height: 38,
                        constraints: const BoxConstraints(maxWidth: 230),
                        padding: const EdgeInsets.only(left: 13, right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white10),
                          color: Colors.black,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedChannelId.isEmpty
                                ? null
                                : _selectedChannelId,
                            dropdownColor: Colors.black,
                            iconEnabledColor: _communityGold,
                            style: const TextStyle(
                              color: _communityGold,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            hint: const Text(
                              'Escolha um canal',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            items: availableChannels
                                .map(
                                  (channel) => DropdownMenuItem<String>(
                                    value: channel.id,
                                    child: Text(
                                      channel.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() => _selectedChannelId = value);
                            },
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          'Ainda não há canais disponíveis para publicar.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: canPublish ? _publishPost : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _communityGold,
                        disabledBackgroundColor: _communityGold.withValues(
                          alpha: 0.35,
                        ),
                        foregroundColor: Colors.black,
                        disabledForegroundColor: Colors.black54,
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: const StadiumBorder(),
                      ),
                      icon: _isPublishing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.edit_outlined, size: 16),
                      label: const Text(
                        'Publicar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityTabButton extends StatelessWidget {
  const _CommunityTabButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool active;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? _communityGold : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: active ? _communityGold : Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatNumber(count!),
                    style: TextStyle(
                      color: active ? Colors.black : Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.currentUserId,
    required this.highlighted,
    required this.commentsOpen,
    required this.visibleComments,
    required this.commentController,
    required this.submittingComment,
    required this.onLike,
    required this.onToggleComments,
    required this.onSave,
    required this.onReport,
    required this.onDelete,
    required this.onShowMoreComments,
    required this.onSubmitComment,
  });

  final _FeedPost post;
  final String currentUserId;
  final bool highlighted;
  final bool commentsOpen;
  final int visibleComments;
  final TextEditingController commentController;
  final bool submittingComment;
  final VoidCallback onLike;
  final VoidCallback onToggleComments;
  final VoidCallback onSave;
  final VoidCallback onReport;
  final VoidCallback onDelete;
  final VoidCallback onShowMoreComments;
  final VoidCallback onSubmitComment;

  @override
  Widget build(BuildContext context) {
    final visible = post.commentsList
        .take(visibleComments)
        .toList(growable: false);
    final hasMoreComments = post.commentsList.length > visibleComments;
    final canDelete = post.authorId == currentUserId && !post.isNotification;

    return Container(
      decoration: BoxDecoration(
        color: highlighted ? _communityGold.withValues(alpha: 0.08) : null,
        border: Border(
          bottom: const BorderSide(color: Colors.white10),
          top: highlighted
              ? BorderSide(color: _communityGold.withValues(alpha: 0.28))
              : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommunityAvatar(
            initials: post.initials,
            avatarUrl: post.avatarUrl,
            official: post.official,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 5,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                post.author,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (post.verified)
                                const Icon(
                                  Icons.verified_rounded,
                                  color: _communityGold,
                                  size: 17,
                                ),
                              Text(
                                post.username,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '· ${post.time}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            post.channel,
                            style: const TextStyle(
                              color: Color(0xC2DBC094),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!post.isNotification)
                      PopupMenuButton<_PostMenuAction>(
                        tooltip: 'Mais opções',
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white38,
                        ),
                        color: const Color(0xFF1A1B20),
                        onSelected: (action) {
                          if (action == _PostMenuAction.report) {
                            onReport();
                          } else {
                            onDelete();
                          }
                        },
                        itemBuilder: (context) => [
                          if (!canDelete)
                            const PopupMenuItem<_PostMenuAction>(
                              value: _PostMenuAction.report,
                              child: Text('Denunciar'),
                            ),
                          if (canDelete)
                            const PopupMenuItem<_PostMenuAction>(
                              value: _PostMenuAction.delete,
                              child: Text('Excluir publicação'),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  post.text,
                  style: const TextStyle(
                    color: Color(0xD8FFFFFF),
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
                if (post.isNotification) ...[
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: _communityGold.withValues(alpha: 0.08),
                      border: Border.all(
                        color: _communityGold.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Text(
                      'Mensagem oficial da Universidade de Líderes',
                      style: TextStyle(
                        color: _communityGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 19,
                    runSpacing: 6,
                    children: [
                      _PostActionButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: _formatNumber(post.comments),
                        onTap: onToggleComments,
                      ),
                      _PostActionButton(
                        icon: post.liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: _formatNumber(post.likes),
                        active: post.liked,
                        onTap: onLike,
                      ),
                      _PostActionButton(
                        icon: post.saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        label: post.saved ? 'Salvo' : 'Salvar',
                        active: post.saved,
                        onTap: onSave,
                      ),
                    ],
                  ),
                  if (!post.allowComments)
                    const Padding(
                      padding: EdgeInsets.only(top: 11),
                      child: Text(
                        'Os comentários estão indisponíveis nesta publicação.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  else if (commentsOpen) ...[
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: commentController,
                            minLines: 2,
                            maxLines: 4,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.35,
                            ),
                            decoration: _inputDecoration(
                              hintText: 'Escreva seu comentário...',
                              filled: true,
                              fillColor: Colors.black,
                              borderRadius: 14,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: submittingComment
                                  ? null
                                  : onSubmitComment,
                              style: FilledButton.styleFrom(
                                backgroundColor: _communityGold,
                                disabledBackgroundColor: _communityGold
                                    .withValues(alpha: 0.45),
                                foregroundColor: Colors.black,
                                disabledForegroundColor: Colors.black54,
                                minimumSize: const Size(0, 46),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: submittingComment
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded, size: 18),
                              label: const Text(
                                'Enviar',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 13),
                          if (visible.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 5),
                              child: Text(
                                'Ainda não há comentários. Seja a primeira pessoa a comentar.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            )
                          else
                            for (
                              var index = 0;
                              index < visible.length;
                              index++
                            ) ...[
                              if (index > 0)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 11),
                                  child: Divider(
                                    height: 1,
                                    color: Colors.white10,
                                  ),
                                ),
                              _CommentItem(comment: visible[index]),
                            ],
                          if (hasMoreComments)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: onShowMoreComments,
                                style: TextButton.styleFrom(
                                  foregroundColor: _communityGold,
                                  padding: const EdgeInsets.only(top: 12),
                                ),
                                child: const Text(
                                  'Ver mais comentários',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _PostMenuAction { report, delete }

class _PostActionButton extends StatelessWidget {
  const _PostActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? _communityGold : Colors.white54;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  const _CommentItem({required this.comment});

  final _FeedComment comment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommunityAvatar(
          initials: comment.initials,
          avatarUrl: comment.avatarUrl,
          size: 34,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    comment.author,
                    style: const TextStyle(
                      color: Color(0xEFFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    comment.time,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                comment.body,
                style: const TextStyle(
                  color: Color(0xA8FFFFFF),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommunityAvatar extends StatelessWidget {
  const _CommunityAvatar({
    required this.initials,
    required this.avatarUrl,
    this.official = false,
    this.size = 40,
  });

  final String initials;
  final String avatarUrl;
  final bool official;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasImage = avatarUrl.trim().isNotEmpty;

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: official ? _communityGold : Colors.white10,
        child: hasImage
            ? Image.network(
                avatarUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initialsWidget(),
              )
            : _initialsWidget(),
      ),
    );
  }

  Widget _initialsWidget() {
    return Text(
      initials,
      style: TextStyle(
        color: official ? Colors.black : Colors.white,
        fontSize: size <= 34 ? 10 : 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CommunityChannel {
  const _CommunityChannel({
    required this.id,
    required this.name,
    required this.slug,
    required this.isLocked,
  });

  final String id;
  final String name;
  final String slug;
  final bool isLocked;

  factory _CommunityChannel.fromMap(Map<String, dynamic> map) {
    return _CommunityChannel(
      id: _stringValue(map['id']),
      name: _stringValue(map['name']).isNotEmpty
          ? _stringValue(map['name'])
          : 'Comunidade',
      slug: _stringValue(map['slug']),
      isLocked: _boolValue(map['is_locked']),
    );
  }
}

class _CommunityProfile {
  const _CommunityProfile({
    required this.id,
    required this.fullName,
    required this.avatarUrl,
    required this.role,
  });

  final String id;
  final String fullName;
  final String avatarUrl;
  final String role;

  factory _CommunityProfile.fromMap(Map<String, dynamic> map) {
    return _CommunityProfile(
      id: _stringValue(map['id']),
      fullName: _stringValue(map['full_name']),
      avatarUrl: _stringValue(map['avatar_url']),
      role: _stringValue(map['role']),
    );
  }
}

class _FeedComment {
  const _FeedComment({
    required this.id,
    required this.author,
    required this.initials,
    required this.avatarUrl,
    required this.body,
    required this.time,
  });

  final String id;
  final String author;
  final String initials;
  final String avatarUrl;
  final String body;
  final String time;
}

class _FeedPost {
  const _FeedPost({
    required this.id,
    required this.tab,
    required this.authorId,
    required this.author,
    required this.username,
    required this.initials,
    required this.avatarUrl,
    required this.time,
    required this.channelId,
    required this.channel,
    required this.text,
    required this.comments,
    required this.likes,
    required this.liked,
    required this.saved,
    required this.verified,
    required this.official,
    required this.isNotification,
    required this.notificationId,
    required this.allowComments,
    required this.commentsList,
  });

  final String id;
  final _CommunityTab tab;
  final String authorId;
  final String author;
  final String username;
  final String initials;
  final String avatarUrl;
  final String time;
  final String channelId;
  final String channel;
  final String text;
  final int comments;
  final int likes;
  final bool liked;
  final bool saved;
  final bool verified;
  final bool official;
  final bool isNotification;
  final String notificationId;
  final bool allowComments;
  final List<_FeedComment> commentsList;

  _FeedPost copyWith({int? likes, bool? liked, bool? saved}) {
    return _FeedPost(
      id: id,
      tab: tab,
      authorId: authorId,
      author: author,
      username: username,
      initials: initials,
      avatarUrl: avatarUrl,
      time: time,
      channelId: channelId,
      channel: channel,
      text: text,
      comments: comments,
      likes: likes ?? this.likes,
      liked: liked ?? this.liked,
      saved: saved ?? this.saved,
      verified: verified,
      official: official,
      isNotification: isNotification,
      notificationId: notificationId,
      allowComments: allowComments,
      commentsList: commentsList,
    );
  }
}

InputDecoration _inputDecoration({
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool filled = true,
  Color? fillColor,
  double borderRadius = 14,
  EdgeInsetsGeometry? contentPadding,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(borderRadius),
    borderSide: const BorderSide(color: Colors.white10),
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Colors.white38),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    prefixIconColor: Colors.white54,
    suffixIconColor: Colors.white54,
    filled: filled,
    fillColor: fillColor ?? Colors.black,
    contentPadding:
        contentPadding ?? const EdgeInsets.symmetric(horizontal: 16),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: _communityGold, width: 1),
    ),
  );
}

List<Map<String, dynamic>> _toRows(dynamic response) {
  if (response is! List) {
    return const <Map<String, dynamic>>[];
  }

  return response
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

String _stringValue(dynamic value) {
  return value?.toString() ?? '';
}

bool _boolValue(dynamic value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return fallback;
}

_CommunityTab _tabForSlug(String? slug) {
  final cleanSlug = (slug ?? '').trim().toLowerCase();

  if (cleanSlug.contains('aviso')) {
    return _CommunityTab.alerts;
  }
  if (cleanSlug.contains('duvida') || cleanSlug.contains('dúvida')) {
    return _CommunityTab.questions;
  }
  if (cleanSlug.contains('networking') || cleanSlug.contains('apresent')) {
    return _CommunityTab.networking;
  }
  if (cleanSlug.contains('mentoria') ||
      cleanSlug.contains('live') ||
      cleanSlug.contains('ao-vivo')) {
    return _CommunityTab.lives;
  }

  return _CommunityTab.forYou;
}

String _initials(String? name) {
  final cleanName = (name ?? '').trim();
  if (cleanName.isEmpty) {
    return 'UL';
  }

  final parts = cleanName
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length >= 2 ? 2 : parts.first.length)
        .toUpperCase();
  }

  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

String _userHandle(String name) {
  final normalized = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), '');

  return '@${normalized.isEmpty ? 'aluno' : normalized}';
}

String _resolveAvatarUrl(String? path) {
  final cleanPath = (path ?? '').trim();
  if (cleanPath.isEmpty ||
      cleanPath.startsWith('http://') ||
      cleanPath.startsWith('https://') ||
      cleanPath.startsWith('/')) {
    return cleanPath;
  }

  try {
    return Supabase.instance.client.storage
        .from('avatars')
        .getPublicUrl(cleanPath);
  } catch (_) {
    return cleanPath;
  }
}

String _relativeTime(String value) {
  if (value.trim().isEmpty) {
    return 'agora';
  }

  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) {
    return 'agora';
  }

  final difference = DateTime.now().difference(date);
  if (difference.isNegative || difference.inMinutes < 1) {
    return 'agora';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours} h';
  }
  if (difference.inDays == 1) {
    return 'ontem';
  }

  return '${difference.inDays} dias';
}

String _formatNumber(int value) {
  return value.toString();
}
