import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/lan_sync/lan_sync_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/controls/bm_field.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/overlay/bm_toast.dart';
import 'package:bilimusic/shared/ui/status/bm_empty.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';

/// 资料库抽屉里的分类页签。
enum _LibraryTab {
  playlists('歌单'),
  albums('专辑'),
  artists('UP 主');

  const _LibraryTab(this.label);

  final String label;
}

/// 横屏左侧资料库抽屉（设计稿 `.library-drawer`）。
///
/// 只挂在内容区 Stack 里：`left: 0`、`top/bottom: 0`，宽 320，圆角 0。
/// 标题 / 筛选 / 三个页签 / 歌单行 / 新建歌单 / 底部同步信息。
class LandscapeLibraryDrawer extends ConsumerStatefulWidget {
  const LandscapeLibraryDrawer({
    super.key,
    required this.onClose,
    required this.selectedPlaylistId,
    required this.onOpenPlaylist,
    required this.onManageSync,
  });

  final VoidCallback onClose;

  /// 当前栈顶歌单 id，用来高亮对应行。
  final String? selectedPlaylistId;

  final void Function(String playlistId, String playlistName) onOpenPlaylist;

  /// 底部「管理」：进入局域网同步页。
  final VoidCallback onManageSync;

  /// 设计稿 `.lib-row`：行高 54、封面 38。
  static const double _coverSize = 38;

  @override
  ConsumerState<LandscapeLibraryDrawer> createState() =>
      _LandscapeLibraryDrawerState();
}

class _LandscapeLibraryDrawerState
    extends ConsumerState<LandscapeLibraryDrawer> {
  final TextEditingController _filterController = TextEditingController();
  _LibraryTab _tab = _LibraryTab.playlists;

  @override
  void initState() {
    super.initState();
    _filterController.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _filterController.removeListener(_onFilterChanged);
    _filterController.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final blur = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );
    final playlists = ref.watch(userPlaylistsProvider);
    final connectedCount = ref.watch(connectedPeersProvider).length;

    return SizedBox(
      width: BmTokens.libraryDrawerWidth,
      child: BmChromeSurface(
        edges: const <BmChromeEdge>{BmChromeEdge.right},
        blur: blur,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(BmTokens.s4, 18, BmTokens.s4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, playlists.length),
              const SizedBox(height: BmTokens.s3),
              Expanded(child: _buildScrollBody(context, playlists)),
              const SizedBox(height: BmTokens.s3),
              _buildFooter(context, type, colors, connectedCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    final colors = context.bmColors;
    final type = context.bmType;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '资料库',
                style: type.title.copyWith(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                'LIBRARY · $count 个歌单',
                style: type.micro.copyWith(
                  color: colors.textTertiary,
                  letterSpacing: 0.8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        BmIconButton(
          icon: Icons.close_rounded,
          tooltip: '关闭',
          size: BmIconButtonSize.lg,
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  /// 抽屉筛选框：设计稿 `.lib-search` 高 34，这里用更紧凑的一行输入框。
  Widget _buildFilterField(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return SizedBox(
      height: 34,
      child: TextField(
        controller: _filterController,
        style: type.caption.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surfaceSunken,
          hintText: '筛选歌单、专辑、UP 主',
          hintStyle: type.micro.copyWith(color: colors.textTertiary),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s3,
            vertical: BmTokens.s2,
          ),
          prefixIcon: const Icon(Icons.search_rounded),
          prefixIconConstraints: const BoxConstraints(
            minWidth: BmTokens.controlMd,
            minHeight: BmTokens.controlMd,
          ),
          border: const OutlineInputBorder(
            borderRadius: BmTokens.r9All,
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        BmTokens.s1 / 2,
        0,
        BmTokens.s1 / 2,
        8,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          for (final tab in _LibraryTab.values)
            Padding(
              padding: const EdgeInsets.only(right: BmTokens.s3 + 2),
              child: BmPressable(
                onTap: () => setState(() => _tab = tab),
                borderRadius: BmTokens.r4All,
                semanticLabel: tab.label,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 5),
                  decoration: _tab == tab
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colors.accent, width: 2),
                          ),
                        )
                      : null,
                  child: Text(
                    tab.label,
                    style: type.micro.copyWith(
                      color: _tab == tab
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontWeight: _tab == tab
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 抽屉中段：筛选 / 页签 / 歌单行 / 新建。
  ///
  /// 整段纵向滚动，矮窗口下（手机横屏）也不会把固定头部和底部挤爆。
  Widget _buildScrollBody(BuildContext context, List<Playlist> playlists) {
    final slivers = <Widget>[
      SliverToBoxAdapter(child: _buildFilterField(context)),
      const SliverToBoxAdapter(child: SizedBox(height: BmTokens.s3)),
      SliverToBoxAdapter(child: _buildTabs(context)),
      const SliverToBoxAdapter(child: SizedBox(height: BmTokens.s1)),
    ];

    if (_tab != _LibraryTab.playlists) {
      // TODO: 专辑 / UP 主分类尚未接入数据源。
      slivers.add(
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 150,
            child: BmEmptyState(
              compact: true,
              icon: Icons.category_outlined,
              title: '暂无内容',
            ),
          ),
        ),
      );
    } else {
      final query = _filterController.text.trim().toLowerCase();
      final visible = query.isEmpty
          ? playlists
          : playlists
                .where(
                  (p) =>
                      p.name.toLowerCase().contains(query) ||
                      (p.description?.toLowerCase().contains(query) ?? false),
                )
                .toList();

      if (visible.isEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: BmEmptyState(
                compact: true,
                icon: Icons.queue_music_rounded,
                title: query.isEmpty ? '还没有歌单' : '没有匹配的歌单',
                message: query.isEmpty ? '点下方新建一个' : null,
              ),
            ),
          ),
        );
      } else {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildPlaylistRow(visible[index]),
              childCount: visible.length,
            ),
          ),
        );
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: BmTokens.s2)));
    slivers.add(SliverToBoxAdapter(child: _buildNewPlaylistButton(context)));

    return CustomScrollView(slivers: slivers);
  }

  Widget _buildPlaylistRow(Playlist playlist) {
    final colors = context.bmColors;
    final type = context.bmType;
    final commands = ref.read(playlistCommandsProvider.notifier);
    final selected = widget.selectedPlaylistId == playlist.id;

    final row = BmPressable(
      onTap: () => widget.onOpenPlaylist(playlist.id, playlist.name),
      selected: selected,
      selectedColor: colors.accentSoft,
      borderRadius: BmTokens.r9All,
      semanticLabel: playlist.name,
      child: Container(
        height: BmTokens.drawerRow,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.hairline,
              width: BmTokens.hairlineWidth,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: LandscapeLibraryDrawer._coverSize,
              height: LandscapeLibraryDrawer._coverSize,
              child: ClipRRect(
                borderRadius: BmTokens.r9All,
                child: BmArtImage(
                  url: playlist.safeCoverUrl.isEmpty
                      ? null
                      : playlist.safeCoverUrl,
                  cacheKey: playlist.id,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.label.copyWith(
                      color: selected ? colors.accentDeep : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _subtitle(playlist),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: BmTokens.s1),
            Icon(
              Icons.chevron_right_rounded,
              size: BmTokens.iconInline,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );

    return AppContextMenu(
      menuProvider: (request) => buildPlaylistContextMenu(
        context: context,
        playlist: playlist,
        onRename: () => confirmAndRenamePlaylist(
          context: context,
          playlist: playlist,
          commands: commands,
        ),
        onDelete: () => confirmAndDeletePlaylist(
          context: context,
          playlist: playlist,
          commands: commands,
        ),
      ),
      child: row,
    );
  }

  String _subtitle(Playlist playlist) {
    final count = '${playlist.songCount} 首';
    if (playlist.totalDuration <= Duration.zero) return count;
    return '$count · ${formatDuration(playlist.totalDuration)}';
  }

  Widget _buildNewPlaylistButton(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return BmPressable(
      onTap: _createPlaylist,
      borderRadius: BmTokens.r9All,
      semanticLabel: '新建歌单',
      child: CustomPaint(
        painter: _DashedBorderPainter(color: colors.lineStrong),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                size: BmTokens.iconMenu,
                color: colors.accentDeep,
              ),
              const SizedBox(width: BmTokens.s1),
              Text(
                '新建歌单',
                style: type.micro.copyWith(color: colors.accentDeep),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    BmTypographySet type,
    BmColors colors,
    int connectedCount,
  ) {
    final syncLabel = connectedCount > 0
        ? '$connectedCount 台设备 · 私有同步'
        : '私有同步 · 未连接';

    return Container(
      padding: const EdgeInsets.only(top: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              syncLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.micro.copyWith(color: colors.textTertiary),
            ),
          ),
          BmPressable(
            onTap: widget.onManageSync,
            borderRadius: BmTokens.r4All,
            semanticLabel: '管理同步',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '管理',
                  style: type.micro.copyWith(color: colors.textSecondary),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: BmTokens.iconInline,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist() async {
    final name = await showBmDialog<String>(
      context: context,
      builder: (dialogContext) => const _CreatePlaylistDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;

    try {
      await ref.read(playlistServiceProvider).createPlaylist(name: name);
      if (!mounted) return;
      showBmToast(context, '已创建歌单「$name」', status: BmToastStatus.success);
    } catch (error) {
      if (!mounted) return;
      showBmToast(context, '创建歌单失败：$error', status: BmToastStatus.error);
    }
  }
}

/// 新建歌单对话框：自己持有输入控制器，随路由一起释放。
class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return BmDialog(
      title: '新建歌单',
      content: BmField(
        controller: _controller,
        hintText: '歌单名称',
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}

/// 虚线圆角边框：新建歌单按钮用。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = BmTokens.hairlineWidth;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(BmTokens.r9),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
