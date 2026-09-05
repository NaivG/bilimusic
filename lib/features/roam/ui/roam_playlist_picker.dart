import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/providers/playlist_providers.dart';

/// 共享漫游歌单选择器。
///
/// 提供：
/// - 顶部 banner（介绍 + 警告）
/// - 歌单列表（favorites + 用户自建）
/// - 空状态
///
/// 可用于：
/// - bottom sheet 包装（roam_section 现有路径）
/// - 全屏页面 inline（onboarding 步骤 A）
///
/// 通过 [onPlaylistSelected] 回调让调用方决定选中后的行为，避免本组件直接耦合
/// 到 PlayerCoordinator。
class RoamPlaylistPicker extends ConsumerWidget {
  const RoamPlaylistPicker({
    super.key,
    this.showTitle = true,
    this.scrollController,
    required this.onPlaylistSelected,
  });

  /// 是否显示 "选择漫游种子歌单" 标题。
  ///
  /// 全屏页面有自己的页头，可关闭；bottom sheet 内需要打开。
  final bool showTitle;

  /// 滚动控制器，用于接入 DraggableScrollableSheet 的拖拽行为。
  ///
  /// 全屏页面可以传 null（ListView 自己处理滚动）。
  final ScrollController? scrollController;

  /// 用户点选歌单后的回调。
  final void Function(String playlistId, String playlistName, int songCount)
  onPlaylistSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final userPlaylists = ref.watch(userPlaylistsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择漫游种子歌单',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        const RoamBanner(),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            controller: scrollController,
            children: [
              if (favorites.isNotEmpty)
                _PlaylistTile(
                  playlistId: 'favorites',
                  name: DefaultPlaylists.favorites.name,
                  songCount: favorites.length,
                  onTap: onPlaylistSelected,
                  icon: Icons.favorite,
                  iconColor: Colors.red,
                ),
              for (final p in userPlaylists)
                _PlaylistTile(
                  playlistId: p.id,
                  name: p.name,
                  songCount: p.songCount,
                  onTap: onPlaylistSelected,
                  icon: Icons.queue_music,
                  iconColor: Colors.blue,
                ),
              if (favorites.isEmpty && userPlaylists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      '暂无可用歌单\n请先收藏歌曲或创建歌单',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

/// 介绍 + 警告横幅：提醒 "将清空当前队列"。
class RoamBanner extends StatelessWidget {
  const RoamBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.amber[800], size: 20),
              const SizedBox(width: 8),
              Text(
                '全新功能：漫游模式',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '基于所选歌单无限发现相似音乐。',
            style: TextStyle(fontSize: 13, color: Colors.amber[900]),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange[700],
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '⚠ 进入后将清空当前播放队列',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlistId,
    required this.name,
    required this.songCount,
    required this.onTap,
    required this.icon,
    required this.iconColor,
  });

  final String playlistId;
  final String name;
  final int songCount;
  final void Function(String playlistId, String playlistName, int songCount)
  onTap;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: songCount > 0,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        name,
        style: TextStyle(color: songCount > 0 ? null : Colors.grey),
      ),
      subtitle: Text(songCount > 0 ? '$songCount 首歌曲' : '空歌单'),
      trailing: songCount > 0
          ? const Icon(Icons.arrow_forward_ios, size: 14)
          : null,
      onTap: songCount > 0 ? () => onTap(playlistId, name, songCount) : null,
    );
  }
}
