import 'dart:math';

import 'package:bilimusic/shared/widgets/auto_appbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/core/storage/storage_path_resolver.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/offline/services/offline_cache_service.dart';
import 'package:bilimusic/features/lyrics/lyrics_providers.dart';
import 'package:restart_app/restart_app.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  bool _loading = true;

  /// 离线服务实例：`dispose()` 里不能再碰 `ref`（BuildContext 已 deactivate，
  /// 会抛 "Using ref when a widget is about to or has been unmounted is unsafe"），
  /// 所以在 initState 就存一份，销毁时拿它摘监听。
  late final OfflineCacheService _offlineService;

  // 数据概览
  int _playHistoryCount = 0;
  int _favoritesCount = 0;
  int _playlistCount = 0;
  bool _isLoggedIn = false;

  // 存储占用
  String _musicCacheSize = '计算中...';
  String _imageCacheSize = '计算中...';
  String _lyricsCacheSize = '计算中...';
  String _totalCacheSize = '计算中...';

  /// 清空歌词缓存进行中（避免连点重复清空 + 重新搜索）。
  bool _lyricsBusy = false;

  // 离线缓存
  int _offlineCount = 0;
  String _offlineSize = '0 B';
  String _offlineDir = '加载中...';

  /// 当前离线目录是不是应用私有兜底目录（而不是用户在设置页选的）。
  bool _offlineDirIsPrivate = true;

  /// 非空表示「配置的目录这次不可用，已回退到私有目录」，内容为原因。
  String? _offlineDirFallback;

  bool _offlineBusy = false;

  @override
  void initState() {
    super.initState();
    _offlineService = ref.read(offlineCacheServiceProvider);
    _offlineService.addListener(_onOfflineChanged);
    _loadData();
  }

  @override
  void dispose() {
    _offlineService.removeListener(_onOfflineChanged);
    super.dispose();
  }

  /// 下载完成 / 切换目录 / 清空后刷新离线概览。
  void _onOfflineChanged() {
    if (mounted) _loadOfflineSummary();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadAppData(),
      _loadCacheSize(),
      _loadOfflineSummary(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadOfflineSummary() async {
    final offline = _offlineService;
    await offline.initialize();
    final count = await offline.count();
    final bytes = await offline.totalBytes();
    if (!mounted) return;
    setState(() {
      _offlineCount = count;
      _offlineSize = _formatBytes(bytes, 2);
      _offlineDir = offline.baseDirectory ?? (offline.rootError ?? '未配置');
      _offlineDirIsPrivate = offline.rootOrigin == StorageRootOrigin.appPrivate;
      _offlineDirFallback = offline.rootFallbackReason;
    });
  }

  Future<void> _loadAppData() async {
    final prefs = await SharedPreferences.getInstance();

    final historyCount = ref.read(playlistServiceProvider).historyCount;
    final favCount = ref.read(playlistServiceProvider).favoritesCount;
    final playlistCount = ref.read(playlistServiceProvider).userPlaylistsCount;

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
    final lyricsSize = int.tryParse(sizes['lyrics'] ?? '0') ?? 0;
    final totalSize = musicSize + imageSize + lyricsSize;

    if (mounted) {
      setState(() {
        _musicCacheSize = _formatBytes(musicSize, 2);
        _imageCacheSize = _formatBytes(imageSize, 2);
        _lyricsCacheSize = _formatBytes(lyricsSize, 2);
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

  /// 离线目录回退提示：用户选的目录这次探测不可写，已经暂时回到私有目录。
  Widget _buildOfflineDirWarning(String reason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: const TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '数据管理'),
      backgroundColor: Colors.transparent,
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
                      _buildInfoRow('歌词缓存', _lyricsCacheSize),
                      _buildDivider(),
                      _buildInfoRow(
                        '合计',
                        _totalCacheSize,
                        valueColor: _getPrimaryColor(context),
                      ),
                    ],
                  ),

                  // 离线缓存
                  _buildSectionTitle('离线缓存'),
                  _buildInfoCard(
                    children: [
                      _buildInfoRow('已下载', '$_offlineCount 首'),
                      _buildDivider(),
                      _buildInfoRow('占用空间', _offlineSize),
                      _buildDivider(),
                      _buildInfoRow(
                        '存放目录',
                        _offlineDir,
                        valueColor: Colors.grey,
                      ),
                      if (_offlineDirFallback != null) ...[
                        _buildDivider(),
                        _buildOfflineDirWarning(_offlineDirFallback!),
                      ],
                    ],
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        if (OfflineCacheService.supportsDirectoryPicker) ...[
                          ListTile(
                            leading: Icon(
                              Icons.drive_file_move_outline,
                              color: _getPrimaryColor(context),
                            ),
                            title: const Text('更改离线目录'),
                            subtitle: Text(
                              _offlineDirIsPrivate
                                  ? '当前为应用私有目录 · 已下载的文件不会自动搬移'
                                  : '已自定义目录 · 已下载的文件不会自动搬移',
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                            onTap: _offlineBusy ? null : _changeOfflineDir,
                          ),
                          _buildDivider(),
                          // 自定义目录之后必须留一条回到默认目录的路，
                          // 否则换机/删目录后用户只能靠清空 App 数据复位。
                          if (!_offlineDirIsPrivate) ...[
                            ListTile(
                              leading: Icon(
                                Icons.settings_backup_restore,
                                color: _getPrimaryColor(context),
                              ),
                              title: const Text('恢复默认目录'),
                              subtitle: const Text('回到应用私有目录 · 已下载的文件不会搬移'),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              onTap: _offlineBusy ? null : _resetOfflineDir,
                            ),
                            _buildDivider(),
                          ],
                        ],
                        ListTile(
                          leading: Icon(
                            Icons.delete_sweep_outlined,
                            color: _getPrimaryColor(context),
                          ),
                          title: const Text('清空离线缓存'),
                          subtitle: const Text('删除已下载的音频文件与记录'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: _offlineBusy ? null : _clearOffline,
                        ),
                      ],
                    ),
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
                            Icons.lyrics_outlined,
                            color: _getPrimaryColor(context),
                          ),
                          title: const Text('清空歌词缓存'),
                          subtitle: Text('当前 $_lyricsCacheSize · 清空后当前曲目重新搜索'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: _lyricsBusy ? null : _clearLyricsCache,
                        ),
                        _buildDivider(),
                        ListTile(
                          leading: Icon(
                            Icons.cleaning_services,
                            color: _getPrimaryColor(context),
                          ),
                          title: const Text('清除缓存数据'),
                          subtitle: const Text('清除图片、音乐和歌词缓存文件'),
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

  /// 统一的二次确认弹窗：标题 + 纯文本说明 + 取消 / 确定。
  Future<bool> _confirm(String title, String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
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
    return confirmed ?? false;
  }

  void _clearCache() async {
    final confirm = await _confirm('清除缓存', '确定要清除所有缓存吗？这将包括图片、音乐与歌词缓存数据。');

    if (confirm) {
      try {
        await imageCacheManager.emptyCache();
        await musicCacheManager.emptyCache();
        // 歌词多一层内存缓存（LyricsService 的 payload/sources/失败冷却），
        // 只清磁盘的话当前会话仍会用旧载荷，必须整体走服务清空。
        await ref.read(lyricsServiceProvider).clearCache();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('缓存清除成功')));
          // 刷新缓存大小显示
          _loadCacheSize();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('缓存清除失败: $e')));
        }
      }
    }
  }

  /// 清空歌词缓存（磁盘 + 内存），用于歌词搜不到 / 搜错时强制重搜。
  ///
  /// 走 [LyricsService.clearCache] 而不是直接 emptyCache：内存层清掉后
  /// 服务会通知 UI 重建，当前曲目立刻重新搜索，入口点下去能马上看到效果。
  Future<void> _clearLyricsCache() async {
    final confirm = await _confirm(
      '清空歌词缓存',
      '将删除已缓存的歌词与候选来源记录（不含已下载的离线音频），'
          '当前曲目会立即重新联网搜索。',
    );
    if (!confirm) return;

    setState(() => _lyricsBusy = true);
    try {
      // 先复位手动选的歌词源：它是上一轮搜索的产物（`${source.name}:$id`），
      // 缓存清空后候选要重新搜，旧 id 大概率已失效 —— 不复位就会拿着失效 id
      // 去取歌词，表现为「清完缓存歌词反而不见了」。复位后走自动选源。
      ref.read(selectedLyricSourceProvider.notifier).clear();
      await ref.read(lyricsServiceProvider).clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('歌词缓存已清空')));
        await _loadCacheSize();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清空歌词缓存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _lyricsBusy = false);
    }
  }

  /// 切换离线目录（桌面端 + Android）。
  ///
  /// Android 上 file_picker 会拉起 SAF 让用户选目录，选完服务会**实写探测**
  /// 一次；写不进去就抛 [StorageRootUnavailableException] 并保留原目录。
  Future<void> _changeOfflineDir() async {
    setState(() => _offlineBusy = true);
    try {
      final picked = await ref
          .read(offlineCacheServiceProvider)
          .chooseBaseDirectory();
      if (!mounted) return;
      if (picked != null) {
        // 切换目录会清掉"文件已不在"的悬挂记录，列表要跟着重算。
        ref.invalidate(offlineTracksProvider);
        await _loadOfflineSummary();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('离线目录已切换到 $picked')));
        }
      }
    } on StorageRootUnavailableException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('切换离线目录失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _offlineBusy = false);
    }
  }

  /// 回到平台默认（应用私有）离线目录。
  ///
  /// 只清掉"文件已不在"的悬挂记录，不搬移任何文件 —— 与切目录同一套语义。
  Future<void> _resetOfflineDir() async {
    setState(() => _offlineBusy = true);
    try {
      await ref.read(offlineCacheServiceProvider).resetBaseDirectory();
      ref.invalidate(offlineTracksProvider);
      await _loadOfflineSummary();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已恢复默认离线目录')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复默认目录失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _offlineBusy = false);
    }
  }

  /// 清空离线缓存（文件 + 数据库记录）。
  Future<void> _clearOffline() async {
    if (_offlineCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有离线缓存')));
      return;
    }
    final confirm = await _confirm(
      '清空离线缓存',
      '将删除已下载的 $_offlineCount 首曲子（$_offlineSize）及其记录，该操作不可恢复。',
    );
    if (!confirm) return;

    setState(() => _offlineBusy = true);
    try {
      await ref.read(offlineTracksProvider.notifier).clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('离线缓存已清空')));
        await _loadOfflineSummary();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清空失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _offlineBusy = false);
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
              const Text('• 文件系统缓存（含歌词缓存）'),
              const Text('• 离线缓存（已下载的音频文件）'),
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
        await ref.read(playlistServiceProvider).clearAllUserData();

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('cookies');
        await prefs.remove('login_time');
        await prefs.remove('recommendations_cache');
        await prefs.remove('guess_you_like_cache');

        await musicCacheManager.emptyCache();
        await imageCacheManager.emptyCache();
        // 只清磁盘层即可：这里马上要重启进程，内存层随进程一起没了。
        await lyricsCacheManager.emptyCache();
        // 离线缓存是用户主动下载的文件，清理时一并删掉（上面已明示）。
        await ref.read(offlineCacheServiceProvider).clearAll();

        await Restart.restartApp(mode: RestartMode.process);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('清除数据失败: $e')));
        }
      }
    }
  }
}
