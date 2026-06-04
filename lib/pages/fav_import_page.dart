import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/models/bili_fav_folder.dart';
import 'package:bilimusic/models/fav_import_record.dart';
import 'package:bilimusic/managers/fav_sync_manager.dart';
import 'package:bilimusic/components/import_progress_dialog.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';

/// Bilibili 收藏夹导入页面
/// 列出用户的 Bilibili 收藏夹，支持导入到本地歌单
class FavImportPage extends StatefulWidget {
  const FavImportPage({super.key});

  @override
  State<FavImportPage> createState() => _FavImportPageState();
}

class _FavImportPageState extends State<FavImportPage> {
  final FavSyncManager _syncManager = sl.favSyncManager;

  List<BiliFavFolder> _createdFolders = [];
  List<BiliFavFolder> _collectedFolders = [];
  bool _isFetching = false;
  String? _errorMessage;
  Set<int> _selectedMediaIds = {};

  @override
  void initState() {
    super.initState();
    _syncManager.addListener(_onSyncChanged);
    _fetchFolders();
  }

  @override
  void dispose() {
    _syncManager.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchFolders() async {
    setState(() {
      _isFetching = true;
      _errorMessage = null;
    });

    try {
      final userInfo = sl.userManager.userInfo;
      if (userInfo == null) {
        setState(() {
          _isFetching = false;
          _errorMessage = '请先登录后再导入收藏夹';
        });
        return;
      }

      final upMid = int.tryParse(userInfo.uid) ?? 0;
      if (upMid == 0) {
        setState(() {
          _isFetching = false;
          _errorMessage = '无法获取用户信息，请重新登录';
        });
        return;
      }

      final result = await _syncManager.fetchAllFolders(upMid);

      if (!mounted) return;
      setState(() {
        _createdFolders = result['created'] ?? [];
        _collectedFolders = result['collected'] ?? [];
        _isFetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetching = false;
        _errorMessage = '获取收藏夹失败: $e';
      });
    }
  }

  void _toggleSelect(int mediaId) {
    setState(() {
      if (_selectedMediaIds.contains(mediaId)) {
        _selectedMediaIds.remove(mediaId);
      } else {
        _selectedMediaIds.add(mediaId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedMediaIds = {
        ..._createdFolders.map((f) => f.mediaId),
        ..._collectedFolders.map((f) => f.mediaId),
      };
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedMediaIds.clear();
    });
  }

  Future<void> _importSelected() async {
    final folders = [
      ..._createdFolders.where((f) => _selectedMediaIds.contains(f.mediaId)),
      ..._collectedFolders.where((f) => _selectedMediaIds.contains(f.mediaId)),
    ];

    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要导入的收藏夹')),
      );
      return;
    }

    int totalSuccess = 0;
    int totalFailed = 0;

    for (final folder in folders) {
      if (_syncManager.isImported(folder.mediaId)) {
        continue; // 已导入的跳过
      }

      final result = await showDialog<ImportResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ImportProgressDialog(
          folderName: folder.title,
          importTask: (onProgress) async {
            final r = await _syncManager.importFolderAsNewPlaylist(
              folder,
              onProgress: onProgress,
            );
            return r;
          },
        ),
      );

      if (result != null) {
        totalSuccess += result.successCount;
        totalFailed += result.failedCount;
      }
    }

    if (!mounted) return;
    _deselectAll();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '完成！成功导入 $totalSuccess 首'
          '${totalFailed > 0 ? '，跳过 $totalFailed 首失效内容' : ''}',
        ),
      ),
    );
  }

  Future<void> _importSingle(BiliFavFolder folder) async {
    if (_syncManager.isImported(folder.mediaId)) {
      _showAlreadyImportedSnackbar(folder);
      return;
    }

    await showDialog<ImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportProgressDialog(
        folderName: folder.title,
        importTask: (onProgress) async {
          final r = await _syncManager.importFolderAsNewPlaylist(
            folder,
            onProgress: onProgress,
          );
          return r;
        },
      ),
    );

    if (!mounted) return;
    setState(() {}); // 刷新状态标签
  }

  void _showAlreadyImportedSnackbar(BiliFavFolder folder) {
    final record = _syncManager.findRecord(folder.mediaId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '「${folder.title}」已导入'
          '${record != null ? '（${record.importedCount} 首）' : ''}',
        ),
        action: SnackBarAction(
          label: '重新同步',
          onPressed: () async {
            await showDialog<ImportResult>(
              context: context,
              barrierDismissible: false,
              builder: (context) => ImportProgressDialog(
                folderName: folder.title,
                importTask: (onProgress) async {
                  final r = await _syncManager.syncSingleFolder(folder);
                  return r;
                },
              ),
            );
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilibili 收藏夹导入'),
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
          // 批量操作栏
          if (_createdFolders.isNotEmpty || _collectedFolders.isNotEmpty)
            _buildActionBar(),

          // 主要内容
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _selectedMediaIds.isNotEmpty ? _deselectAll : _selectAll,
            icon: Icon(
              _selectedMediaIds.isNotEmpty
                  ? Icons.deselect
                  : Icons.select_all,
              size: 18,
            ),
            label: Text(_selectedMediaIds.isNotEmpty ? '取消全选' : '全选'),
          ),
          const Spacer(),
          if (_selectedMediaIds.isNotEmpty)
            FilledButton.icon(
              onPressed: _importSelected,
              icon: const Icon(Icons.download, size: 18),
              label: Text('导入选中 (${_selectedMediaIds.length})'),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isFetching) {
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
              onPressed: _fetchFolders,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_createdFolders.isEmpty && _collectedFolders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('暂无收藏夹', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text(
              '去 Bilibili 收藏一些视频再来吧',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchFolders,
      child: ListView(
        children: [
          if (_createdFolders.isNotEmpty) ...[
            _buildSectionHeader('创建的收藏夹', _createdFolders.length),
            ..._createdFolders.map(_buildFolderTile),
          ],
          if (_collectedFolders.isNotEmpty) ...[
            _buildSectionHeader('收藏的收藏夹', _collectedFolders.length),
            ..._collectedFolders.map(_buildFolderTile),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(BiliFavFolder folder) {
    final isSel = _selectedMediaIds.contains(folder.mediaId);
    final record = _syncManager.findRecord(folder.mediaId);
    final isImported = record != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleSelect(folder.mediaId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              // 复选框
              Checkbox(
                value: isSel,
                onChanged: (_) => _toggleSelect(folder.mediaId),
              ),

              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey.withValues(alpha: 0.2),
                  child: folder.cover.isNotEmpty
                      ? null // 实际生产环境用 CachedNetworkImage
                      : Icon(Icons.bookmark, color: Colors.grey[400]),
                ),
              ),
              const SizedBox(width: 12),

              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${folder.mediaCount} 个内容',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

              // 状态标签
              if (record != null)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: record.status == ImportStatus.synced
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    record.status == ImportStatus.synced
                        ? '已导入'
                        : '有更新',
                    style: TextStyle(
                      fontSize: 11,
                      color: record.status == ImportStatus.synced
                          ? Colors.green[700]
                          : Colors.orange[700],
                    ),
                  ),
                ),

              // 导入按钮
              IconButton(
                icon: Icon(
                  isImported ? Icons.sync : Icons.download,
                  size: 20,
                ),
                tooltip: isImported ? '重新同步' : '导入',
                onPressed: () => _importSingle(folder),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
