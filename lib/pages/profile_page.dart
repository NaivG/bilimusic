import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/models/music.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _playHistoryCount = 0;
  int _favoritesCount = 0;
  int _playlistsCount = 0;
  bool _isLoggedIn = false;
  String _userName = '点击登录';
  String _userAvatar = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkLoginStatus();
  }

  Future<void> _loadData() async {
    // 获取播放历史数量
    final playHistory = sl.playerManager.playHistory;

    // 获取收藏数量
    final favorites = sl.playerManager.favorites;

    // 获取用户自定义播放列表数量
    final playlists = sl.playlistManager.getAllPlaylists();

    setState(() {
      _playHistoryCount = playHistory.length;
      _favoritesCount = favorites.length;
      _playlistsCount = playlists.length;
    });
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final cookies = prefs.getString('cookies');
    if (cookies != null && cookies.isNotEmpty) {
      // 检查是否是有效的登录cookie（包含SESSDATA）
      if (cookies.contains('SESSDATA')) {
        try {
          // 获取用户信息
          await _loadUserInfo();
          setState(() {
            _isLoggedIn = true;
          });
        } catch (e) {
          // 获取用户信息失败
          debugPrint('获取用户信息失败: $e');
        }
      }
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
        headers: NetworkConfig.biliHeaders,
      );
      debugPrint(NetworkConfig.biliHeaders.toString());
      debugPrint(response.body);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0 && data['data']['isLogin']) {
          setState(() {
            _userName = data['data']['uname'];
            _userAvatar = data['data']['face'];
          });
        }
      }
    } catch (e) {
      debugPrint('获取用户信息失败: $e');
    }
  }

  // 退出登录
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final cookiesJson = prefs.getString('cookies');

    if (cookiesJson != null && cookiesJson.isNotEmpty) {
      try {
        // 解析现有的 cookies
        final cookiesMap = json.decode(cookiesJson) as Map;
        final cookies = Map<String, String>.from(
          cookiesMap.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        );

        // 删除指定的Cookie字段
        cookies.removeWhere(
          (key, value) =>
              key == 'SESSDATA' ||
              key == 'bili_jct' ||
              key == 'DedeUserID' ||
              key == 'DedeUserID__ckMd5' ||
              key == 'sid',
        );

        // 保存更新后的 cookies
        await prefs.setString('cookies', json.encode(cookies));

        // 更新NetworkConfig中的cookies
        NetworkConfig.setCookies(cookies);

        // 更新UI状态
        setState(() {
          _isLoggedIn = false;
          _userName = '点击登录';
          _userAvatar = '';
        });

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已退出登录')));
        }
      } catch (e) {
        debugPrint('退出登录失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('退出登录失败: $e')));
        }
      }
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
  void dispose() {
    // sl.playlistManager不需要dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                          if (_isLoggedIn) {
                            _showLogoutDialog();
                          } else {
                            // 跳转到登录页面
                            Navigator.pushNamed(context, '/login');
                          }
                        },
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white,
                          backgroundImage: _userAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(_userAvatar)
                              : null,
                          child: _userAvatar.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Theme.of(context).primaryColor,
                                )
                              : null,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        _userName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isLoggedIn ? '已登录' : '登录后可同步数据',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
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

                  SizedBox(height: 20),

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
    // 在深色主题中使用白色，在浅色主题中使用primaryColor
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Theme.of(context).primaryColor;
  }

  Widget _buildStatItem(IconData icon, String count, String label) {
    return Column(
      children: [
        Icon(icon, size: 30, color: _getPrimaryColor(context)),
        SizedBox(height: 5),
        Text(
          count,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.history, color: Colors.blue),
          ),
          title: Text('播放历史'),
          trailing: Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    PlaylistPage(songs: sl.playerManager.playHistory),
              ),
            );
          },
        ),

        Divider(height: 1),

        // 我的收藏
        ListTile(
          leading: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.favorite, color: Colors.red),
          ),
          title: Text('我的收藏'),
          trailing: Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    PlaylistPage(songs: sl.playerManager.favorites),
              ),
            );
          },
        ),

        Divider(height: 1),

        // 我的歌单
        ListTile(
          leading: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.playlist_play, color: Colors.green),
          ),
          title: Text('我的歌单'),
          trailing: Icon(Icons.arrow_forward_ios),
          onTap: () {
            _showPlaylists();
          },
        ),
      ],
    );
  }

  void _showPlaylists() {
    final playlists = sl.playlistManager.getAllPlaylists();

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
                    Text(
                      '我的歌单',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add),
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
                            Icon(
                              Icons.playlist_add,
                              size: 50,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 10),
                            Text(
                              '暂无歌单',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _createNewPlaylist();
                              },
                              child: Text('创建歌单'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return FutureBuilder<List<Music>>(
                            future: sl.playlistManager.getPlaylistSongs(
                              playlist.id,
                            ),
                            builder: (context, snapshot) {
                              final songCount = snapshot.data?.length ?? 0;
                              return ListTile(
                                leading: Icon(Icons.queue_music),
                                title: Text(playlist.name),
                                subtitle: Text('$songCount 首歌曲'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  if (mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PlaylistPage(
                                          playlistId: playlist.id,
                                        ),
                                      ),
                                    );
                                  }
                                },
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
    final TextEditingController _controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('创建歌单'),
          content: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: '请输入歌单名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_controller.text.trim().isNotEmpty) {
                  await sl.playlistManager.createPlaylist(
                    _controller.text.trim(),
                  );
                  Navigator.pop(context);
                  _loadData(); // 刷新数据
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('歌单创建成功')));
                }
              },
              child: Text('创建'),
            ),
          ],
        );
      },
    );
  }
}
