import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/up_profile.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';

/// 歌手页（UP 页）的页头。
///
/// 布局：左侧圆形头像（右下角压一枚认证徽标）+ 右侧昵称 / 投稿数 / 描述 / 操作按钮。
/// 内容少，只有横排一套，不像 playlist 那样再分竖排版本。
class ArtistHeader extends StatelessWidget {
  /// 头像直径
  static const double avatarSize = 96;

  final UpProfile up;

  /// 投稿总数；接口没给到时传 0，此时不显示数量行
  final int submissionCount;

  /// 正在攒队列（播放全部 / 随机播放 期间按钮不可点）
  final bool isBusy;

  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;

  const ArtistHeader({
    super.key,
    required this.up,
    this.submissionCount = 0,
    this.isBusy = false,
    this.onPlayAll,
    this.onShufflePlay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(context),
          const SizedBox(width: 24),
          Expanded(child: _buildInfoAndActions(context)),
        ],
      ),
    );
  }

  /// 圆形遮罩的头像 + 挂在右下角上层的认证徽标。
  Widget _buildAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        children: [
          Positioned.fill(child: ClipOval(child: _buildAvatarImage(context))),
          if (up.isVerified)
            Positioned(
              right: 0,
              bottom: 0,
              // 垫一圈底色，把徽标从头像里「抠」出来
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.verified, size: 20, color: Colors.blue[400]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final fallback = Container(
      color: palette.surfaceHover,
      child: Icon(
        Icons.person,
        size: avatarSize * 0.5,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    if (up.face.isEmpty) return fallback;

    return CachedNetworkImage(
      imageUrl: up.face,
      httpHeaders: NetworkConfig.biliHeaders,
      fit: BoxFit.cover,
      cacheManager: imageCacheManager,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }

  Widget _buildInfoAndActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'UP 主',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          up.displayName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (submissionCount > 0) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '$submissionCount 个投稿',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          up.description,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 20),
        _buildPillButtons(context),
      ],
    );
  }

  Widget _buildPillButtons(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final hintColor = isBusy
        ? colorScheme.onSurfaceVariant
        : colorScheme.primary;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        SizedBox(
          height: 36,
          child: ElevatedButton.icon(
            onPressed: isBusy ? null : onPlayAll,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('播放全部', style: TextStyle(fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              disabledBackgroundColor: palette.surfaceHover,
              disabledForegroundColor: colorScheme.onSurfaceVariant,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              elevation: 0,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: isBusy ? null : onShufflePlay,
            icon: Icon(Icons.shuffle, size: 18, color: hintColor),
            label: Text(
              '随机播放',
              style: TextStyle(fontSize: 14, color: hintColor),
            ),
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              side: BorderSide(
                color: isBusy
                    ? colorScheme.outline
                    : colorScheme.primary.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ),
      ],
    );
  }
}
