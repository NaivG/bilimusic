import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/gallery/gallery_sections.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/overlay/bm_overlays.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 分区 8：菜单 + 浮层预览。
///
/// 菜单浮层里静态铺开普通 / selected / destructive / disabled / 子菜单
/// 五种行形态；浮层按钮分别打开对话框、底部单与 success / error 两个
/// Toast，另放一枚静态 Toast 预览（不依赖 ScaffoldMessenger 宿主主题）。
class GalleryOverlaySection extends StatefulWidget {
  const GalleryOverlaySection({super.key});

  @override
  State<GalleryOverlaySection> createState() => _GalleryOverlaySectionState();
}

class _GalleryOverlaySectionState extends State<GalleryOverlaySection> {
  /// 入场只在挂载时播一次；换 key 重挂 [BmMenuSurface] 即可重播。
  int _entranceRound = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return GallerySection(
      title: '浮层',
      description:
          '菜单行高 32 / 浮层内边距 6；120ms scale 入场；'
          'hover 与键盘 focus 合流进同一套状态层。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: BmTokens.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '菜单（BmMenuSurface + BmMenuRow）',
                style: type.label.copyWith(color: colors.textPrimary),
              ),
              TextButton(
                onPressed: () => setState(() => _entranceRound++),
                child: const Text('重播入场'),
              ),
            ],
          ),
          const SizedBox(height: BmTokens.s2),
          _OverlayDemo(
            label: '普通 / selected / destructive / disabled / 子菜单',
            width: BmTokens.s8 * 10,
            child: _buildMenu(),
          ),
          const SizedBox(height: BmTokens.s4),
          const Divider(),
          const SizedBox(height: BmTokens.s3),
          Text(
            '浮层（showBmDialog / showBmSheet / showBmToast）',
            style: type.label.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: BmTokens.s2),
          Wrap(
            spacing: BmTokens.s2,
            runSpacing: BmTokens.s2,
            children: [
              FilledButton(
                onPressed: () => _showDialog(context),
                child: const Text('打开对话框'),
              ),
              OutlinedButton(
                onPressed: () => _showSheet(context),
                child: const Text('打开底部单'),
              ),
              OutlinedButton(
                onPressed: () => showBmToast(
                  context,
                  'BmToast：操作成功',
                  status: BmToastStatus.success,
                ),
                child: const Text('Toast · 成功'),
              ),
              OutlinedButton(
                onPressed: () => showBmToast(
                  context,
                  'BmToast：操作失败',
                  status: BmToastStatus.error,
                ),
                child: const Text('Toast · 错误'),
              ),
            ],
          ),
          const SizedBox(height: BmTokens.s3),
          _OverlayDemo(
            label: 'BmToast 静态预览（success）',
            width: BmTokens.s8 * 10,
            child: SizedBox(
              width: BmTokens.s8 * 9,
              child: const BmToast(
                message: 'Toast：保存成功',
                status: BmToastStatus.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    return BmMenuSurface(
      key: ValueKey('bm-gallery-menu-$_entranceRound'),
      entrance: BmMenuEntranceKind.scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BmMenuRow(
            title: '播放下一首',
            leading: const Icon(Icons.skip_next_rounded),
            shortcut: 'Ctrl+→',
            onTap: () {},
          ),
          BmMenuRow(
            title: '循环模式：列表',
            leading: const Icon(Icons.repeat_rounded),
            trailing: const Icon(Icons.check_rounded),
            selected: true,
            onTap: () {},
          ),
          BmMenuRow(
            title: '从歌单移除',
            leading: const Icon(Icons.delete_outline_rounded),
            destructive: true,
            onTap: () {},
          ),
          BmMenuRow(
            title: '需要登录',
            leading: const Icon(Icons.lock_outline_rounded),
            enabled: false,
          ),
          BmMenuRow(
            title: '添加到歌单',
            leading: const Icon(Icons.playlist_add_rounded),
            showChevron: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  void _showDialog(BuildContext context) {
    showBmDialog<void>(
      context: context,
      builder: (dialogContext) => BmDialog(
        title: 'Lucent 对话框',
        content: const Text(
          '面板 fade + scale 0.94→1：进场 180ms、退场 120ms；'
          '遮罩取当前预览主题的 scrim。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showBmSheet<void>(
      context: context,
      builder: (sheetContext) => BmSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BmMenuRow(
              title: '关闭',
              leading: const Icon(Icons.close_rounded),
              height: BmTokens.touchScreen,
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            BmMenuRow(
              title: '复制歌曲链接',
              leading: const Icon(Icons.link_rounded),
              height: BmTokens.touchScreen,
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 浮层 demo 的统一外壳：标签 + 内容，背景与描边读 token。
class _OverlayDemo extends StatelessWidget {
  const _OverlayDemo({
    required this.label,
    required this.child,
    this.width = BmTokens.s8 * 8,
  });

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      width: width,
      padding: const EdgeInsets.all(BmTokens.s3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: type.micro.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: BmTokens.s2),
          child,
        ],
      ),
    );
  }
}
