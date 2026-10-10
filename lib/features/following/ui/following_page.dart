import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/bili_following.dart';
import 'package:bilimusic/features/following/following_service.dart';

/// 「查看关注」页：列出自己关注的全部 UP 主。
class FollowingPage extends ConsumerStatefulWidget {
  const FollowingPage({super.key});

  @override
  ConsumerState<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends ConsumerState<FollowingPage> {
  /// 距底部多远开始预取下一页（列表滚动时触发）。
  static const double _loadMoreThreshold = 400;

  final ScrollController _scrollController = ScrollController();
  final List<BiliFollowing> _users = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _total = 0;
  int _page = 0;
  String? _errorMessage;

  /// 正在攒歌单的 UP 主 mid（行内转圈 + 拦住重复点击）
  int? _openingMid;

  /// 攒歌单的进度文案（如「已取 30 / 218 首」）
  String? _openingHint;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 当前登录用户的 mid；没登录 / 拿不到 uid 时为 0。
  int get _currentVmid {
    final uid = ref.read(userManagerProvider).userInfo?.uid;
    return int.tryParse(uid ?? '') ?? 0;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    final vmid = _currentVmid;
    if (vmid == 0) {
      setState(() {
        _isLoading = false;
        _errorMessage = '请先登录后再查看关注';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await ref
        .read(followingServiceProvider)
        .fetchFollowingsPage(vmid: vmid, page: 1);
    if (!mounted) return;

    setState(() {
      _users
        ..clear()
        ..addAll(result.items);
      _total = result.total;
      _page = 1;
      // 不满一页就是最后一面；接口在「翻到底」时回的是空页，同样是 false。
      _hasMore = result.items.length >= FollowingService.followingPageSize;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final vmid = _currentVmid;
    if (vmid == 0) return;

    setState(() => _isLoadingMore = true);

    final result = await ref
        .read(followingServiceProvider)
        .fetchFollowingsPage(vmid: vmid, page: _page + 1);
    if (!mounted) return;

    setState(() {
      _users.addAll(result.items);
      // total 只在接口真给了数时覆盖：翻页失败回的 0 不该把表头数字抹掉。
      if (result.total > 0) _total = result.total;
      _page += 1;
      _hasMore = result.items.length >= FollowingService.followingPageSize;
      _isLoadingMore = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _hasMore = false;
      _page = 0;
      _total = 0;
    });
    await _loadFirstPage();
  }

  /// 把某位 UP 主的投稿攒成临时歌单并跳过去浏览。
  Future<void> _openUserSongs(BiliFollowing user) async {
    if (_openingMid != null) return;

    setState(() {
      _openingMid = user.mid;
      _openingHint = '正在整理投稿…';
    });

    try {
      final songs = await ref
          .read(followingServiceProvider)
          .collectUserSongs(
            user,
            onProgress: (loaded, total) {
              if (!mounted) return;
              setState(() {
                _openingHint = total > 0
                    ? '已取 $loaded / $total 首'
                    : '已取 $loaded 首';
              });
            },
          );
      if (!mounted) return;

      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有取到投稿：可能撞上风控，或 TA 还没有可播的稿件')),
        );
        return;
      }

      ShellPageManager.instance.goToPlaylist(
        playlistId: 'bili_up_${user.mid}',
        songs: songs,
        playlistName: '${user.name} 的投稿',
      );
    } catch (e) {
      debugPrint('[FollowingPage] 加载投稿失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载投稿失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingMid = null;
          _openingHint = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_total > 0 ? '我的关注（$_total）' : '我的关注'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        forceMaterialTransparency: true,
        leading: ShellPageManager.instance.canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                onPressed: () => ShellPageManager.instance.pop(),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_openingMid != null) _buildOpeningBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 攒歌单时的顶部进度条：要翻好几页投稿，没有反馈会让人以为点了没反应。
  Widget _buildOpeningBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _openingHint ?? '正在整理投稿…',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('还没有关注任何人', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text(
              '去 Bilibili 关注一些 UP 主再来吧',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        // 末尾多一格给「加载更多」用
        itemCount: _users.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _users.length) return _buildFooter();
          return _buildUserTile(_users[index]);
        },
      ),
    );
  }

  Widget _buildUserTile(BiliFollowing user) {
    final isOpening = _openingMid == user.mid;
    final busy = _openingMid != null;
    final subtitle = user.sign.isNotEmpty
        ? user.sign
        : (user.verifyDesc.isNotEmpty ? user.verifyDesc : '这个人很神秘，什么都没写');

    return ListTile(
      leading: _buildAvatar(user),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.name.isNotEmpty ? user.name : 'mid ${user.mid}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (user.isVerified) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified, size: 14, color: Colors.blue[400]),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: isOpening
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.queue_music, size: 20, color: Colors.grey[500]),
      onTap: busy ? null : () => _openUserSongs(user),
    );
  }

  Widget _buildAvatar(BiliFollowing user) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey.withValues(alpha: 0.2),
      child: ClipOval(
        child: user.face.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: user.face,
                httpHeaders: NetworkConfig.biliHeaders,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                cacheManager: imageCacheManager,
                placeholder: (context, url) =>
                    Icon(Icons.person, size: 22, color: Colors.grey[500]),
                errorWidget: (context, url, error) =>
                    Icon(Icons.person, size: 22, color: Colors.grey[500]),
              )
            : Icon(Icons.person, size: 22, color: Colors.grey[500]),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: _isLoadingMore
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                '上滑加载更多',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
      ),
    );
  }
}
