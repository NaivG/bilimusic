import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/network/passport_client.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/auth/logout_session.dart';
import 'package:bilimusic/features/auth/models/user_info.dart';
import 'package:bilimusic/features/auth/ui/force_logout_dialog.dart';
import 'package:bilimusic/features/auth/user_manager.dart';
import 'package:bilimusic/features/lan_sync/ui/sync_page.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/roam/roam_providers.dart';
import 'package:bilimusic/features/roam/ui/roam_info_dialog.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/overlay/bm_sheet.dart';
import 'package:bilimusic/shared/ui/overlay/bm_toast.dart';
import 'package:bilimusic/shared/ui/sections/bm_page_header.dart';
import 'package:bilimusic/shared/ui/sections/bm_section_header.dart';
import 'package:bilimusic/shared/ui/settings/bm_settings_group.dart';
import 'package:bilimusic/shared/ui/status/bm_empty.dart';
import 'package:bilimusic/shared/ui/surfaces/bm_card.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';

/// 我的：用户卡 + 统计 + 创建的歌单 + 音乐库 / 更多入口。
///
/// 横竖屏共用本页：横屏通栏，歌单网格 3 列；不提供设置入口
/// （设置走 Dock / rail）。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final UserManager _userManager;

  @override
  void initState() {
    super.initState();
    _userManager = ref.read(userManagerProvider);
    _userManager.addListener(_onUserChanged);
    if (!_userManager.isFresh) {
      _userManager.getUserInfo();
    }
  }

  @override
  void dispose() {
    _userManager.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final userManager = ref.watch(userManagerProvider);
    final settings = ref.watch(settingsProvider);
    final favorites = ref.watch(favoritesProvider);
    final history = ref.watch(playHistoryProvider);
    final playlists = ref.watch(userPlaylistsProvider);
    final isLoggedIn = userManager.isLoggedIn;
    final userInfo = userManager.userInfo;

    final isLandscape = LandscapeBreakpoints.shouldUseLandscapeLayout(context);
    final pageInset = isLandscape
        ? BmTokens.contentInset
        : BmTokens.pageInsetWide;
    final cardInset = isLandscape ? BmTokens.contentInset : BmTokens.s4;
    final topInset = isLandscape ? BmTokens.contentInsetTop : BmTokens.s4;

    return Scaffold(
      // 透明让壳层的流体背景透出。
      backgroundColor: context.bmColors.bg.withValues(alpha: 0),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          // 给竖屏浮动的迷你播放器 / Dock 让位；横屏该值即底部安全区。
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BmPageHeader(
                title: '我的',
                padding: EdgeInsets.fromLTRB(pageInset, topInset, pageInset, 0),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  cardInset,
                  BmTokens.s2,
                  cardInset,
                  0,
                ),
                child: isLoggedIn
                    ? _buildUserCard(
                        userInfo: userInfo,
                        lanSyncMode: settings.lanSyncMode,
                      )
                    : _buildLoginCard(),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  cardInset,
                  BmTokens.s3,
                  cardInset,
                  0,
                ),
                child: _buildStats(
                  favorites: favorites.length,
                  history: history.length,
                  playlists: playlists.length,
                ),
              ),
              BmSectionHeader(
                title: '创建的歌单',
                padding: EdgeInsets.fromLTRB(
                  pageInset,
                  BmTokens.s5,
                  pageInset,
                  BmTokens.s3,
                ),
                trailing: playlists.isEmpty
                    ? null
                    : _SectionAction(
                        label: '全部 ${playlists.length} 个',
                        onTap: _showPlaylists,
                      ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: cardInset),
                child: playlists.isEmpty
                    ? _buildPlaylistEmpty()
                    : _buildPlaylistGrid(
                        playlists: playlists,
                        isLandscape: isLandscape,
                      ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape
                      ? BmTokens.contentInset - BmTokens.s4
                      : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLibraryGroup(
                      favorites: favorites.length,
                      history: history.length,
                      playlists: playlists.length,
                    ),
                    _buildMoreGroup(
                      isLoggedIn: isLoggedIn,
                      lanSyncMode: settings.lanSyncMode,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BmTokens.s6),
            ],
          ),
        ),
      ),
    );
  }

  // ===== 用户卡 / 统计 =====

  Widget _buildUserCard({
    required UserInfo? userInfo,
    required String lanSyncMode,
  }) {
    final colors = context.bmColors;
    final type = context.bmType;
    final name = (userInfo?.userName ?? '').trim();
    final level = userInfo?.level ?? 0;
    final syncText = switch (lanSyncMode) {
      'private' => '私有同步已开启',
      'public' => '公共同步已开启',
      _ => '未开启同步',
    };
    return BmCard(
      child: BmPressable(
        onTap: _showLogoutDialog,
        borderRadius: BorderRadius.zero,
        semanticLabel: '账号，点击退出登录',
        child: Padding(
          padding: const EdgeInsets.all(BmTokens.s4),
          child: Row(
            children: [
              _ProfileAvatar(url: userInfo?.avatar ?? ''),
              const SizedBox(width: BmTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty ? 'BiliMusic 用户' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.title.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: BmTokens.s1 / 2),
                    Text(
                      'Lv$level · 已登录 · $syncText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BmTokens.s2),
              Icon(
                Icons.chevron_right_rounded,
                size: BmTokens.iconMenu,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    return BmCard(
      child: BmEmptyState(
        compact: true,
        icon: Icons.person_outlined,
        title: '未登录',
        message: '登录后可同步收藏、歌单与最近播放',
        action: FilledButton(
          onPressed: () => ShellPageManager.instance.push(ShellPage.login),
          child: const Text('登录'),
        ),
      ),
    );
  }

  Widget _buildStats({
    required int favorites,
    required int history,
    required int playlists,
  }) {
    return BmCard(
      padding: const EdgeInsets.symmetric(vertical: BmTokens.s4),
      child: Row(
        children: [
          Expanded(
            child: _StatBlock(value: favorites, label: '收藏'),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatBlock(value: history, label: '最近'),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatBlock(value: playlists, label: '歌单'),
          ),
        ],
      ),
    );
  }

  // ===== 创建的歌单 =====

  Widget _buildPlaylistGrid({
    required List<Playlist> playlists,
    required bool isLandscape,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = isLandscape ? 3 : 2;
        final gap = BmTokens.s3;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: playlists.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: BmTokens.s5,
            mainAxisExtent: itemWidth + BmTokens.s8 * 2,
          ),
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return BmMediaCard(
              cover: BmArtImage(url: playlist.safeCoverUrl),
              title: playlist.name,
              subtitle: '${playlist.songCount} 首',
              onTap: () => ShellPageManager.instance.goToPlaylist(
                playlistId: playlist.id,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistEmpty() {
    return BmEmptyState(
      compact: true,
      icon: Icons.queue_music_outlined,
      title: '还没有创建歌单',
      message: '新建一个歌单来整理喜欢的音乐',
      action: FilledButton(
        onPressed: _createNewPlaylist,
        child: const Text('新建歌单'),
      ),
    );
  }

  Future<void> _showPlaylists() {
    return showBmSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final playlists = ref.watch(userPlaylistsProvider);
            final colors = context.bmColors;
            final type = context.bmType;
            return BmSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '我的歌单',
                          style: type.title.copyWith(color: colors.textPrimary),
                        ),
                      ),
                      BmIconButton(
                        icon: Icons.add_rounded,
                        tooltip: '新建歌单',
                        soft: true,
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _createNewPlaylist();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: BmTokens.s2),
                  if (playlists.isEmpty)
                    const BmEmptyState(
                      compact: true,
                      title: '还没有创建歌单',
                      message: '新建一个歌单来整理喜欢的音乐',
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: playlists.length,
                        separatorBuilder: (_, _) => SizedBox(
                          height: BmTokens.hairlineWidth,
                          child: ColoredBox(color: colors.hairline),
                        ),
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return AppContextMenu(
                            menuProvider: (_) => buildPlaylistContextMenu(
                              context: context,
                              playlist: playlist,
                              onRename: () => confirmAndRenamePlaylist(
                                context: context,
                                playlist: playlist,
                                commands: ref.read(
                                  playlistCommandsProvider.notifier,
                                ),
                              ),
                              onDelete: () => confirmAndDeletePlaylist(
                                context: context,
                                playlist: playlist,
                                commands: ref.read(
                                  playlistCommandsProvider.notifier,
                                ),
                              ),
                            ),
                            child: BmSettingsValueRow(
                              title: playlist.name,
                              subtitle: '${playlist.songCount} 首',
                              icon: Icons.queue_music_outlined,
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                ShellPageManager.instance.goToPlaylist(
                                  playlistId: playlist.id,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===== 音乐库 / 更多 =====

  Widget _buildLibraryGroup({
    required int favorites,
    required int history,
    required int playlists,
  }) {
    return BmSettingsGroup(
      title: '音乐库',
      children: [
        BmSettingsValueRow(
          title: '播放历史',
          subtitle: '$history 首',
          icon: Icons.history_outlined,
          onTap: () => ShellPageManager.instance.goToPlaylist(
            playlistId: 'history',
            songs: ref.read(playHistoryProvider),
          ),
        ),
        BmSettingsValueRow(
          title: '我的收藏',
          subtitle: '$favorites 首',
          icon: Icons.favorite_border_outlined,
          onTap: () => ShellPageManager.instance.goToPlaylist(
            playlistId: 'favorites',
            songs: ref.read(favoritesProvider),
          ),
        ),
        BmSettingsValueRow(
          title: '我的歌单',
          subtitle: '$playlists 个歌单',
          icon: Icons.queue_music_outlined,
          onTap: _showPlaylists,
        ),
        BmSettingsValueRow(
          title: '离线缓存',
          subtitle: '查看已下载到本地的音乐',
          icon: Icons.download_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.offline),
        ),
      ],
    );
  }

  Widget _buildMoreGroup({
    required bool isLoggedIn,
    required String lanSyncMode,
  }) {
    final isRoaming = ref.watch(isRoamingProvider);
    final mode = LanSyncMode.fromString(lanSyncMode);
    return BmSettingsGroup(
      title: '更多',
      children: [
        if (isRoaming)
          BmSettingsRow(
            title: '漫游模式',
            subtitle: '正在漫游',
            icon: Icons.explore_outlined,
            trailing: BmIconButton(
              icon: Icons.tune_rounded,
              tooltip: '漫游设置',
              soft: true,
              onPressed: () => showRoamInfoDialog(context, ref),
            ),
          )
        else
          BmSettingsValueRow(
            title: '漫游模式',
            subtitle: '按口味连续发现相似歌曲',
            icon: Icons.explore_outlined,
            onTap: () =>
                ShellPageManager.instance.push(ShellPage.roamOnboarding),
          ),
        BmSettingsValueRow(
          title: '局域网同步',
          subtitle: '发现设备、配对、查看本机 PIN',
          icon: Icons.wifi_tethering_outlined,
          value: modeShortLabel(mode),
          onTap: openLanSyncPage,
        ),
        if (isLoggedIn) ...[
          BmSettingsValueRow(
            title: '我的关注',
            subtitle: '浏览已关注 UP 主的投稿',
            icon: Icons.people_outlined,
            onTap: () => ShellPageManager.instance.push(ShellPage.following),
          ),
          BmSettingsValueRow(
            title: 'Bilibili 收藏夹同步',
            subtitle: '从 Bilibili 收藏夹导入歌单',
            icon: Icons.cloud_download_outlined,
            onTap: () => ShellPageManager.instance.push(ShellPage.favImport),
          ),
        ],
      ],
    );
  }

  // ===== 账号 =====

  Future<void> _showLogoutDialog() async {
    final confirmed = await showBmDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final danger = dialogContext.bmColors.danger;
        return BmDialog(
          title: '退出登录',
          content: const Text('确定要退出登录吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: danger),
              child: const Text('退出登录'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await _logout();
  }

  /// 先请求服务端注销；失败时提供「仅清本地」的强制退出。
  Future<void> _logout() async {
    final passport = PassportClient();
    Object? failure;
    try {
      await passport.logout();
    } catch (e) {
      failure = e;
    } finally {
      passport.close();
    }

    if (failure != null) {
      debugPrint('退出登录失败: $failure');
      await _offerForceLogout(failure);
      return;
    }

    await _clearSessionLocally();
    if (mounted) {
      showBmToast(context, '已退出登录', status: BmToastStatus.success);
    }
  }

  Future<void> _offerForceLogout(Object error) async {
    if (!mounted) return;
    final confirmed = await showForceLogoutDialog(context, error: error);
    if (!confirmed || !mounted) return;

    await _clearSessionLocally();
    if (mounted) {
      showBmToast(context, '已在本地强制退出登录');
    }
  }

  Future<void> _clearSessionLocally() => clearLocalLoginState(
    passportStore: ref.read(passportStoreProvider),
    userManager: ref.read(userManagerProvider),
  );

  Future<void> _createNewPlaylist() async {
    final controller = TextEditingController();
    final name = await showBmDialog<String>(
      context: context,
      builder: (dialogContext) => BmDialog(
        title: '创建歌单',
        content: BmField(
          controller: controller,
          hintText: '请输入歌单名称',
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) {
              Navigator.of(dialogContext).pop(trimmed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) {
                Navigator.of(dialogContext).pop(trimmed);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    await ref.read(playlistServiceProvider).createPlaylist(name: name);
    if (!mounted) return;
    showBmToast(context, '歌单创建成功', status: BmToastStatus.success);
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.url});

  final String url;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final fallback = Icon(
      Icons.person_outlined,
      size: BmTokens.s8,
      color: colors.accentDeep,
    );
    return Container(
      width: _size,
      height: _size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.accentSoft,
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: url.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: url,
              httpHeaders: NetworkConfig.biliHeaders,
              cacheManager: imageCacheManager,
              fit: BoxFit.cover,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: BmTypography.numeric(
            type.title.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: BmTokens.s1 / 2),
        Text(label, style: type.micro.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: BmTokens.hairlineWidth,
      height: BmTokens.s6,
      color: context.bmColors.hairline,
    );
  }
}

class _SectionAction extends StatelessWidget {
  const _SectionAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r10All,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s2,
          vertical: BmTokens.s1,
        ),
        child: Text(
          label,
          style: context.bmType.caption.copyWith(
            color: context.bmColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
