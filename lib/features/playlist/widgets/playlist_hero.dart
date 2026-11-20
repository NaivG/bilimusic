import 'package:flutter/material.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/domain/playlist_tag.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/controls/bm_chip.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/widgets/app_menu_button.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 歌单头：封面 / 描述 / 控制三块独立零件。
///
/// 封面单独承载 Hero；横屏 Row、竖屏 Column，只切方向。
class PlaylistHero extends StatelessWidget {
  const PlaylistHero({
    super.key,
    required this.playlist,
    this.songs = const [],
    required this.isLandscape,
    this.isLiked = false,
    this.onPlayAll,
    this.onShufflePlay,
    this.onToggleLike,
    this.onAddToPlaylist,
    this.onExportEntries,
    this.onImportEntries,
    this.onOfflineCacheAll,
    this.canImportEntries = true,
  });

  final Playlist playlist;
  final List<Music> songs;
  final bool isLandscape;

  /// 整张歌单已收藏（全部曲目都在「我喜欢的音乐」里）。
  final bool isLiked;

  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onToggleLike;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onExportEntries;
  final VoidCallback? onImportEntries;
  final VoidCallback? onOfflineCacheAll;
  final bool canImportEntries;

  /// 横屏封面与描述之间的间距（设计稿 28，token 没有这一档）。
  static const double _coverGap = 28;

  /// 控制条高度（设计稿 38，token 没有这一档）。
  static const double _controlHeight = 38;

  @override
  Widget build(BuildContext context) {
    final cover = _PlaylistCover(
      playlist: playlist,
      size: isLandscape
          ? BmTokens.playlistCoverLandscape
          : BmTokens.playlistCoverPortrait,
    );
    final description = _PlaylistDescription(playlist: playlist, songs: songs);
    final controls = _PlaylistControls(
      hasSongs: songs.isNotEmpty,
      canShuffle: songs.length > 1,
      isLiked: isLiked,
      onPlayAll: onPlayAll,
      onShufflePlay: onShufflePlay,
      onToggleLike: onToggleLike,
      menuBuilder: _buildMoreMenu,
    );

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          cover,
          const SizedBox(width: _coverGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                description,
                const SizedBox(height: BmTokens.s4),
                controls,
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cover,
        const SizedBox(height: BmTokens.s6),
        description,
        const SizedBox(height: BmTokens.s4),
        controls,
      ],
    );
  }

  Menu _buildMoreMenu(BuildContext context) {
    final noSongs = songs.isEmpty;
    return Menu(
      children: [
        if (onAddToPlaylist != null) ...[
          MenuAction(
            title: '添加到播放列表',
            image: MenuImage.icon(Icons.playlist_add),
            attributes: MenuActionAttributes(disabled: noSongs),
            callback: () => onAddToPlaylist?.call(),
          ),
          MenuSeparator(),
        ],
        MenuAction(
          title: '导出条目',
          image: MenuImage.icon(Icons.file_upload_outlined),
          attributes: MenuActionAttributes(
            disabled: noSongs || onExportEntries == null,
          ),
          callback: () => onExportEntries?.call(),
        ),
        MenuAction(
          title: '导入条目',
          image: MenuImage.icon(Icons.file_download_outlined),
          attributes: MenuActionAttributes(
            disabled: !canImportEntries || onImportEntries == null,
          ),
          callback: () => onImportEntries?.call(),
        ),
        MenuSeparator(),
        MenuAction(
          title: '离线缓存全部',
          image: MenuImage.icon(Icons.download_outlined),
          attributes: MenuActionAttributes(
            disabled: noSongs || onOfflineCacheAll == null,
          ),
          callback: () => onOfflineCacheAll?.call(),
        ),
      ],
    );
  }
}

/// 封面零件：Hero 是叶子，尺寸由调用方给，不裁切、不叠背景。
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.playlist, required this.size});

  final Playlist playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final systemIcon = playlist.systemPlaylistIcon;
    const radius = BorderRadius.all(Radius.circular(BmTokens.coverRadius));

    return Hero(
      tag: 'playlist_cover_${playlist.id}',
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.shadowStrong,
                blurRadius: BmTokens.s5 * 2,
                offset: const Offset(0, BmTokens.s4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: systemIcon == null
                ? BmArtImage(url: playlist.safeCoverUrl)
                : ColoredBox(
                    color: colors.accentSoft,
                    child: Center(
                      child: Icon(
                        systemIcon,
                        size: size * 0.4,
                        color: colors.accentDeep,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 描述零件：kicker / 标题 / 单行 meta / 标签 / 描述。
class _PlaylistDescription extends StatelessWidget {
  const _PlaylistDescription({required this.playlist, required this.songs});

  final Playlist playlist;
  final List<Music> songs;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final count = songs.isNotEmpty ? songs.length : playlist.songCount;
    final total = songs.isNotEmpty
        ? Duration(
            seconds: songs.fold<int>(
              0,
              (sum, music) => sum + _secondsOf(music),
            ),
          )
        : playlist.totalDuration;
    final minutes = total.inMinutes;

    final meta = <String>[
      '$count 首',
      if (minutes > 0) '$minutes 分钟',
    ].join(' · ');

    final tags = playlist.tagIds.isEmpty
        ? const <PlaylistTag>[]
        : playlist.tags;
    final description = playlist.description?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          playlist.id == 'recommended' ? '每日推荐 · PLAYLIST' : 'PLAYLIST',
          style: type.micro.copyWith(
            color: colors.accentDeep,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: BmTokens.s1),
        Text(
          playlist.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: type.title.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: BmTokens.s1),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.caption.copyWith(color: colors.textSecondary),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: BmTokens.s2),
          Wrap(
            spacing: BmTokens.s1 + 1,
            runSpacing: BmTokens.s1,
            children: <Widget>[
              for (final tag in tags)
                BmTag(label: tag.nameCn.isNotEmpty ? tag.nameCn : tag.name),
            ],
          ),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: BmTokens.s2),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }

  static int _secondsOf(Music music) {
    if (music.duration != null) return music.duration!.inSeconds;
    if (music.pages.isNotEmpty) {
      return music.pages.first.durationValue.inSeconds;
    }
    return 0;
  }
}

/// 控制零件：播放全部 / 随机播放 / 收藏 / 更多。
class _PlaylistControls extends StatelessWidget {
  const _PlaylistControls({
    required this.hasSongs,
    required this.canShuffle,
    required this.isLiked,
    required this.menuBuilder,
    this.onPlayAll,
    this.onShufflePlay,
    this.onToggleLike,
  });

  final bool hasSongs;
  final bool canShuffle;
  final bool isLiked;
  final Menu Function(BuildContext context) menuBuilder;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onToggleLike;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Wrap(
      spacing: BmTokens.s2,
      runSpacing: BmTokens.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _HeroPill(
          icon: Icons.play_arrow_rounded,
          label: '播放全部',
          filled: true,
          onTap: hasSongs ? onPlayAll : null,
        ),
        _HeroPill(
          icon: Icons.shuffle_rounded,
          label: '随机播放',
          filled: false,
          onTap: canShuffle ? onShufflePlay : null,
        ),
        _HeroCircleButton(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          tooltip: isLiked ? '取消收藏' : '收藏',
          color: isLiked ? colors.danger : colors.textSecondary,
          onTap: hasSongs ? onToggleLike : null,
        ),
        _HeroMenuButton(menuBuilder: menuBuilder),
      ],
    );
  }
}

/// accent 实底 / ghost 描边的 38 高胶囊。
class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.label,
    required this.filled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final foreground = filled ? colors.onAccent : colors.textPrimary;
    final labelStyle = filled ? type.label : type.caption;

    return BmPressable(
      onTap: onTap,
      enabled: onTap != null,
      borderRadius: BmTokens.rPillAll,
      semanticLabel: label,
      child: Container(
        height: PlaylistHero._controlHeight,
        padding: EdgeInsets.symmetric(
          horizontal: filled ? BmTokens.s5 - 2 : BmTokens.s4 - 2,
        ),
        decoration: BoxDecoration(
          color: filled ? colors.accent : colors.surfaceRaised,
          borderRadius: BmTokens.rPillAll,
          border: filled
              ? null
              : Border.all(
                  color: colors.lineStrong,
                  width: BmTokens.hairlineWidth,
                ),
          boxShadow: filled
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.accentBorder,
                    blurRadius: BmTokens.s5,
                    offset: const Offset(0, BmTokens.s2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: BmTokens.iconInline, color: foreground),
            const SizedBox(width: BmTokens.s1 + 2),
            Text(
              label,
              style: labelStyle.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 38 直径的圆形描边按钮（收藏）。
class _HeroCircleButton extends StatelessWidget {
  const _HeroCircleButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Tooltip(
      message: tooltip,
      child: BmPressable(
        onTap: onTap,
        enabled: onTap != null,
        borderRadius: BmTokens.rPillAll,
        semanticLabel: tooltip,
        child: Container(
          width: PlaylistHero._controlHeight,
          height: PlaylistHero._controlHeight,
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.lineStrong,
              width: BmTokens.hairlineWidth,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: BmTokens.iconMenu, color: color),
        ),
      ),
    );
  }
}

/// 38 直径的圆形「更多」：内部仍是共享 [AppMenuButton]。
class _HeroMenuButton extends StatelessWidget {
  const _HeroMenuButton({required this.menuBuilder});

  final Menu Function(BuildContext context) menuBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      width: PlaylistHero._controlHeight,
      height: PlaylistHero._controlHeight,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.lineStrong,
          width: BmTokens.hairlineWidth,
        ),
      ),
      alignment: Alignment.center,
      child: AppMenuButton(
        tooltip: '更多',
        icon: Icons.more_horiz_rounded,
        iconSize: BmTokens.iconMenu,
        color: colors.textSecondary,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: PlaylistHero._controlHeight,
          height: PlaylistHero._controlHeight,
        ),
        menuBuilder: menuBuilder,
      ),
    );
  }
}
