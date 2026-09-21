import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/auth/user_manager.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/network/passport_client.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/roam/ui/roam_section.dart';
import 'package:bilimusic/features/lan_sync/ui/lansync_section.dart';
import 'package:super_context_menu/super_context_menu.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  int _playHistoryCount = 0;
  int _favoritesCount = 0;
  int _playlistsCount = 0;
  late final UserManager _userManager;

  @override
  void initState() {
    super.initState();
    _userManager = ref.read(userManagerProvider);
    _loadData();
    // 监听用户管理器变化
    _userManager.addListener(_onUserChanged);
    // 监听页面切换，回到此页面时刷新数据
    ShellPageManager.instance.addListener(_onPageChanged);
    // 如果缓存已有用户信息且登录态一致，无需额外操作；
    // 否则触发一次检查
    if (!_userManager.isFresh) {
      _userManager.getUserInfo();
    }
  }

  @override
  void dispose() {
    _userManager.removeListener(_onUserChanged);
    ShellPageManager.instance.removeListener(_onPageChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  void _onPageChanged() {
    if (mounted && ShellPageManager.instance.currentPage == ShellPage.profile) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final playHistory = ref.read(playHistoryProvider);
    final favorites = ref.read(favoritesProvider);
    final playlists = ref.read(userPlaylistsProvider);

    setState(() {
      _playHistoryCount = playHistory.length;
      _favoritesCount = favorites.length;
      _playlistsCount = playlists.length;
    });
  }

  // 退出登录
  //
  // 先请求服务端注销当前 SESSDATA（`/login/exit/v2`，PassportClient.logout），
  // 成功才动本地——服务端没注销成功就清本地，网络一抖用户就被"登丢"了：
  // 本地 Cookie 看似清干净了，服务端会话却还活着。失败时本地登录态原样保留。
  // 本地清理只摘会话 Cookie：`clearSession()` 按名字清掉 SESSDATA / bili_jct /
  // DedeUserID 等登录态，保留 buvid3 / b_nut / bili_ticket 这些设备标识
  // （清掉它们等于下次启动要从零自举，白白多几次撞风控的机会）。
  // 落盘由 jar 的 saver 钩子自动完成，这里不再手写 prefs；
  // refresh_token 凭据（PassportStore）一并清掉。
  Future<void> _logout() async {
    final passport = PassportClient();
    try {
      await passport.logout();

      // 清 refresh_token 凭据；失败不拦着登出（Cookie 才是登录态的事实来源）。
      try {
        await ref.read(passportStoreProvider).clear();
      } catch (e) {
        debugPrint('refresh_token 清理失败: $e');
      }

      // 只摘会话 Cookie，保留设备标识。
      NetworkConfig.cookieJar.clearSession();

      // 清除用户缓存
      await ref.read(userManagerProvider).clear();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已退出登录')));
      }
    } catch (e) {
      debugPrint('退出登录失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('退出登录失败：服务端注销未完成，本地登录态保持不变')),
        );
      }
    } finally {
      passport.close();
    }
  }

  // 显示退出登录确认对话框
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text('确定要退出登录吗？'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _logout();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userManager = ref.read(userManagerProvider);
    final isLoggedIn = userManager.isLoggedIn;
    final userInfo = userManager.userInfo;
    final userName = userInfo?.userName ?? '点击登录';
    final userAvatar = userInfo?.avatar ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // 用户信息头部
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (isLoggedIn) {
                            _showLogoutDialog();
                          } else {
                            ShellPageManager.instance.push(ShellPage.login);
                          }
                        },
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white,
                          backgroundImage: userAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(userAvatar)
                              : null,
                          child: userAvatar.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Theme.of(context).primaryColor,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isLoggedIn ? '已登录' : '登录后可同步数据',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 功能磁贴
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // 数据统计卡片
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            Icons.history,
                            '$_playHistoryCount',
                            '播放历史',
                          ),
                          _buildStatItem(
                            Icons.favorite,
                            '$_favoritesCount',
                            '我的收藏',
                          ),
                          _buildStatItem(
                            Icons.playlist_play,
                            '$_playlistsCount',
                            '我的歌单',
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 功能列表
                  _buildFunctionList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 获取适合当前主题的主色调
  Color _getPrimaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Theme.of(context).primaryColor;
  }

  Widget _buildStatItem(IconData icon, String count, String label) {
    return Column(
      children: [
        Icon(icon, size: 30, color: _getPrimaryColor(context)),
        const SizedBox(height: 5),
        Text(
          count,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildFunctionList() {
    return Column(
      children: [
        // 播放历史
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.history, color: Colors.blue),
          ),
          title: const Text('播放历史'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            ShellPageManager.instance.goToPlaylist(
              playlistId: 'history', // 播放历史，这里之前写错了没发现绷
              songs: ref.read(playHistoryProvider),
            );
          },
        ),

        const Divider(height: 1),

        // 我的收藏
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.favorite, color: Colors.red),
          ),
          title: const Text('我的收藏'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            ShellPageManager.instance.goToPlaylist(
              playlistId: 'favorites',
              songs: ref.read(favoritesProvider),
            );
          },
        ),

        const Divider(height: 1),

        // 我的歌单
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.playlist_play, color: Colors.green),
          ),
          title: const Text('我的歌单'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            _showPlaylists();
          },
        ),

        const Divider(height: 1),

        // 漫游模式
        const RoamSection(),

        const Divider(height: 1),

        // 局域网同步
        const LanSyncSection(),

        // Bilibili 收藏夹同步（仅登录后显示）
        if (ref.read(userManagerProvider).isLoggedIn) ...[
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud_download, color: Colors.cyan),
            ),
            title: const Text('Bilibili 收藏夹同步'),
            subtitle: const Text('直接从Bilibili收藏夹导入歌单'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              ShellPageManager.instance.push(ShellPage.favImport);
            },
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  void _showPlaylists() {
    final playlists = ref.read(userPlaylistsProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '我的歌单',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        Navigator.pop(context);
                        _createNewPlaylist();
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: playlists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.playlist_add,
                              size: 50,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '暂无歌单',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _createNewPlaylist();
                              },
                              child: const Text('创建歌单'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return FutureBuilder<Playlist?>(
                            future: ref
                                .read(playlistServiceProvider)
                                .getPlaylistDetail(playlist.id),
                            builder: (context, snapshot) {
                              final songCount =
                                  snapshot.data?.songs.length ?? 0;
                              final tile = ListTile(
                                leading: const Icon(Icons.queue_music),
                                title: Text(playlist.name),
                                subtitle: Text('$songCount 首歌曲'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  if (mounted) {
                                    ShellPageManager.instance.goToPlaylist(
                                      playlistId: playlist.id,
                                    );
                                  }
                                },
                              );
                              if (playlist.isDefault) return tile;
                              return ContextMenuWidget(
                                menuProvider: (_) => buildPlaylistContextMenu(
                                  context: context,
                                  playlist: playlist,
                                  onDelete: () => confirmAndDeletePlaylist(
                                    context: context,
                                    playlist: playlist,
                                    commands: ref.read(
                                      playlistCommandsProvider.notifier,
                                    ),
                                  ),
                                ),
                                child: tile,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _createNewPlaylist() {
    final TextEditingController controller = TextEditingController();
    // 弹窗的 context 在 pop 之后就不再可靠，messenger 从页面 context 上先取好
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建歌单'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '请输入歌单名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  await ref
                      .read(playlistServiceProvider)
                      .createPlaylist(name: controller.text.trim());
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _loadData();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('歌单创建成功')),
                  );
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }
}
