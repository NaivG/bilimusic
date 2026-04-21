import 'dart:convert';
import 'dart:math';
import 'package:bilimusic/components/auto_appbar.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/pages/data_migration_page.dart';
import 'package:restart_app/restart_app.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';

class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  bool _loading = true;

  // 数据概览
  int _playHistoryCount = 0;
  int _favoritesCount = 0;
  int _playlistCount = 0;
  bool _isLoggedIn = false;

  // 存储占用
  String _musicCacheSize = '计算中...';
  String _imageCacheSize = '计算中...';
  String _totalCacheSize = '计算中...';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await Future.wait([_loadAppData(), _loadCacheSize()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAppData() async {
    final prefs = await SharedPreferences.getInstance();

    // 播放历史
    final historyJson = prefs.getString('play_history');
    int historyCount = 0;
    if (historyJson != null && historyJson.isNotEmpty) {
      try {
        final list = jsonDecode(historyJson) as List;
        historyCount = list.length;
      } catch (_) {}
    }

    // 收藏列表
    final favJson = prefs.getString('favorites');
    int favCount = 0;
    if (favJson != null && favJson.isNotEmpty) {
      try {
        final list = jsonDecode(favJson) as List;
        favCount = list.length;
      } catch (_) {}
    }

    // 用户歌单
    final playlistJson =
        prefs.getString('user_playlists_enhanced') ??
        prefs.getString('user_playlists');
    int playlistCount = 0;
    if (playlistJson != null && playlistJson.isNotEmpty) {
      try {
        final list = jsonDecode(playlistJson) as List;
        playlistCount = list.length;
      } catch (_) {}
    }

    // 登录状态
    final cookies = prefs.getString('cookies');
    final isLoggedIn =
        cookies != null &&
        cookies.isNotEmpty &&
        cookies.contains('DedeUserID=');

    if (mounted) {
      setState(() {
        _playHistoryCount = historyCount;
        _favoritesCount = favCount;
        _playlistCount = playlistCount;
        _isLoggedIn = isLoggedIn;
      });
    }
  }

  Future<void> _loadCacheSize() async {
    final sizes = await LocalStorage.getCacheSize();
    debugPrint('Cache sizes: $sizes');
    final musicSize = int.tryParse(sizes['music'] ?? '0') ?? 0;
    final imageSize = int.tryParse(sizes['image'] ?? '0') ?? 0;
    final totalSize = musicSize + imageSize;

    if (mounted) {
      setState(() {
        _musicCacheSize = _formatBytes(musicSize, 2);
        _imageCacheSize = _formatBytes(imageSize, 2);
        _totalCacheSize = _formatBytes(totalSize, 2);
      });
    }
  }

  static String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (bytes == 0 ? 0 : (log(bytes) / log(1024)).floor()).clamp(
      0,
      suffixes.length - 1,
    );
    final size = (bytes / pow(1024, i)).toStringAsFixed(decimals);
    return '$size ${suffixes[i]}';
  }

  Color _getPrimaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Theme.of(context).primaryColor;
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: _getPrimaryColor(context),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '数据管理'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 数据概览
                  _buildSectionTitle('数据概览'),
                  _buildInfoCard(
                    children: [
                      _buildInfoRow('播放历史', '$_playHistoryCount 条'),
                      _buildDivider(),
                      _buildInfoRow('收藏列表', '$_favoritesCount 首'),
                      _buildDivider(),
                      _buildInfoRow('用户歌单', '$_playlistCount 个'),
                      _buildDivider(),
                      _buildInfoRow(
                        '登录状态',
                        _isLoggedIn ? '已登录' : '未登录',
                        valueColor: _isLoggedIn ? Colors.green : Colors.grey,
                      ),
                    ],
                  ),

                  // 存储占用
                  _buildSectionTitle('存储占用'),
                  _buildInfoCard(
                    children: [
                      _buildInfoRow('音乐缓存', _musicCacheSize),
                      _buildDivider(),
                      _buildInfoRow('图片缓存', _imageCacheSize),
                      _buildDivider(),
                      _buildInfoRow(
                        '合计',
                        _totalCacheSize,
                        valueColor: _getPrimaryColor(context),
                      ),
                    ],
                  ),

                  // 数据操作
                  _buildSectionTitle('数据操作'),
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.swap_horiz,
                            color: _getPrimaryColor(context),
                          ),
                          title: const Text('数据迁移'),
                          subtitle: const Text('导出或导入应用数据'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: () {
                            ShellPageManager.instance.push(
                              ShellPage.dataMigration,
                            );
                          },
                        ),
                        _buildDivider(),
                        ListTile(
                          leading: Icon(
                            Icons.cleaning_services,
                            color: _getPrimaryColor(context),
                          ),
                          title: const Text('清除缓存数据'),
                          subtitle: const Text('清除图片和音乐缓存文件'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: _clearCache,
                        ),
                        _buildDivider(),
                        ListTile(
                          leading: const Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                          ),
                          title: const Text(
                            '清除所有数据',
                            style: TextStyle(color: Colors.red),
                          ),
                          subtitle: const Text('清除用户数据并重启应用'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: _clearAllData,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  void _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除缓存'),
          content: const Text('确定要清除所有缓存吗？这将包括图片缓存和音乐缓存数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await imageCacheManager.emptyCache();
        await musicCacheManager.emptyCache();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('缓存清除成功')));
          // 刷新缓存大小显示
          _loadCacheSize();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('缓存清除失败: $e')));
        }
      }
    }
  }

  void _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('清除所有数据'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('此操作将清除以下数据：'),
              const SizedBox(height: 8),
              const Text('• 播放历史'),
              const Text('• 收藏列表'),
              const Text('• 用户创建的歌单'),
              const Text('• 自定义标签'),
              const Text('• 登录信息'),
              const Text('• 推荐缓存'),
              const Text('• 文件系统缓存'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '注意：基本设置（主题、通知等）将被保留。',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '此操作不可撤销，应用将自动重启。',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定清除'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys().toList();

        for (final key in keys) {
          if (key.startsWith('playlist_songs_') ||
              key.startsWith('playlist_info_')) {
            await prefs.remove(key);
          }
        }

        await prefs.remove('play_history');
        await prefs.remove('favorites');
        await prefs.remove('user_playlists');
        await prefs.remove('user_playlists_enhanced');
        await prefs.remove('custom_tags');
        await prefs.remove('cookies');
        await prefs.remove('login_time');
        await prefs.remove('recommendations_cache');
        await prefs.remove('guess_you_like_cache');

        await musicCacheManager.emptyCache();
        await imageCacheManager.emptyCache();

        await Restart.restartApp();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('清除数据失败: $e')));
        }
      }
    }
  }
}
