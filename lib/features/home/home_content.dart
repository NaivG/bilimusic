import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/auth/user_providers.dart';
import 'package:bilimusic/features/home/logic/recommendation_manager.dart';
import 'package:bilimusic/features/home/widgets/greeting_card.dart';
import 'package:bilimusic/features/home/widgets/home_hero.dart';
import 'package:bilimusic/features/home/widgets/playlist_card.dart';
import 'package:bilimusic/features/home/widgets/track_row.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/sections/bm_page_header.dart';
import 'package:bilimusic/shared/ui/sections/bm_section_header.dart';
import 'package:bilimusic/shared/ui/shelves/bm_shelf.dart';
import 'package:bilimusic/shared/ui/status/bm_empty.dart';
import 'package:bilimusic/shared/ui/status/bm_skeleton.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 首页内容。
///
/// 竖屏：页头 + 问候带 + 继续聆听大卡 + 为你推荐 / 歌单货架 + 官方推荐列表。
/// 横屏（[wide]）：页头 + 272 hero + 4 / 3 列网格 + 官方推荐 / 历史双列列表，
/// 不出现任何横向滚动。
class HomeContent extends ConsumerStatefulWidget {
  /// 竖屏是否绘制内置页头（日期 + 问候 + 右侧动作）；
  /// 横屏始终绘制，问候属于内容区。
  final bool showAppBar;

  /// 覆盖页头大标题，默认是时段问候。
  final String? appBarTitle;

  /// 横屏排版：272 hero + 4 列网格，禁止任何横向滚动。
  final bool wide;

  const HomeContent({
    super.key,
    this.showAppBar = false,
    this.appBarTitle,
    this.wide = false,
  });

  @override
  ConsumerState<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<HomeContent> {
  /// 「为你推荐」货架条数。
  static const int _personalShelfCount = 8;

  List<Music> _recommended = const [];
  List<Music> _guessYouLike = const [];
  late final RecommendationManager _recommendationManager;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _recommendationManager = ref.read(recommendationManagerProvider);
    _loadRecommendations();
  }

  // ---------------------------------------------------------------- 数据

  /// 「为你推荐」：个性化结果优先，尚未生成时回退官方推荐。
  List<Music> get _personalSongs =>
      _guessYouLike.isNotEmpty ? _guessYouLike : _recommended;

  /// 「官方推荐」：官方结果里剔掉「为你推荐」已经展示过的曲目，避免两处重复。
  List<Music> get _officialSongs {
    if (_recommended.isEmpty) return const [];
    final shown = _personalSongs
        .take(_personalShelfCount)
        .map((music) => music.id)
        .toSet();
    return _recommended.where((music) => !shown.contains(music.id)).toList();
  }

  /// 每日推荐的曲目池。
  List<Music> get _dailyRecommendedSongs => _personalSongs;

  Future<void> _loadRecommendations() async {
    setState(() => _loading = true);
    await _recommendationManager.loadRecommendations();
    if (!mounted) return;
    setState(() {
      _recommended = _recommendationManager.recommendedList;
      _loading = false;
    });
    await _updateGuessYouLike();
  }

  Future<void> _refreshOfficial() async {
    setState(() => _loading = true);
    await _recommendationManager.refreshRecommendations();
    if (!mounted) return;
    setState(() {
      _recommended = _recommendationManager.recommendedList;
      _loading = false;
    });
  }

  Future<void> _updateGuessYouLike() async {
    // 画像先保证够新（内部 24h 节流），失败不挡猜你喜欢更新
    TasteProfile? taste;
    try {
      taste = await ref.read(tasteProfileServiceProvider).ensureFresh();
    } catch (e) {
      debugPrint('[HomeContent] 画像更新失败，本次不重排: $e');
    }
    await _recommendationManager.updateGuessYouLike(
      ref.read(playHistoryProvider),
      playlistService: ref.read(playlistServiceProvider),
      tasteProfile: taste,
    );
    if (!mounted) return;
    setState(() {
      _guessYouLike = _recommendationManager.guessYouLikeList;
    });
  }

  Playlist _buildDailyRecommendedPlaylist() {
    final base = DefaultPlaylists.recommended;
    final songs = _dailyRecommendedSongs;
    return Playlist(
      id: base.id,
      name: base.name,
      description: base.description,
      coverUrl: songs.isNotEmpty ? songs.first.safeCoverUrl : '',
      songCount: songs.length,
      source: base.source,
      isDefault: base.isDefault,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      songs: songs,
    );
  }

  // ---------------------------------------------------------------- 动作

  void _openSearchEntry() {
    ref.read(searchSuggestProvider.notifier).clear();
    ShellPageManager.instance.push(ShellPage.searchEntry);
  }

  void _openProfile() => ShellPageManager.instance.goToTab(2);

  void _openRoamOnboarding() =>
      ShellPageManager.instance.push(ShellPage.roamOnboarding);

  void _openPlaylist(String playlistId, List<Music>? songs, String? name) {
    ShellPageManager.instance.goToPlaylist(
      playlistId: playlistId,
      // 传空列表会让歌单页不再回源查询，宁可传 null
      songs: songs == null || songs.isEmpty ? null : songs,
      playlistName: name,
    );
  }

  void _playSomething() {
    final songs = _dailyRecommendedSongs;
    if (songs.isEmpty) return;
    final index = DateTime.now().microsecondsSinceEpoch % songs.length;
    _playMusic(songs[index]);
  }

  void _playMusic(Music music) {
    // cid 缺失时 playMusic 内部会经 ApiService.ensureCid 补齐
    ref.read(playbackCommandsProvider.notifier).playMusic(music);
  }

  Future<void> _togglePlay() async {
    final commands = ref.read(playbackCommandsProvider.notifier);
    final current = ref.read(currentMusicProvider);
    if (current == null) {
      final songs = _dailyRecommendedSongs;
      if (songs.isEmpty) return;
      await commands.playMusic(songs.first);
      return;
    }
    final playing = ref.read(playerStateProvider) is PlayerPlaying;
    if (playing) {
      await commands.pause();
    } else {
      await commands.resume();
    }
  }

  /// 点舞台卡：正在播的就是这首时进详情，否则直接播它。
  void _onHeroTap(Music music) {
    final current = ref.read(currentMusicProvider);
    if (current != null && current.sameTrackAs(music)) {
      ShellPageManager.instance.push(ShellPage.detail);
      return;
    }
    _playMusic(music);
  }

  // ---------------------------------------------------------------- 构建

  bool _isWide(BuildContext context) {
    if (widget.wide) return true;
    final size = MediaQuery.sizeOf(context);
    return size.width >= LandscapeBreakpoints.largeTabletMin &&
        size.width > size.height;
  }

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    final colors = context.bmColors;
    return Scaffold(
      // 透传壳层的舞台背景（模糊封面）
      backgroundColor: colors.bg.withValues(alpha: 0),
      body: SafeArea(
        top: !wide,
        bottom: false,
        child: wide ? _buildWide(context) : _buildPortrait(context),
      ),
    );
  }

  Widget _buildPortrait(BuildContext context) {
    final now = DateTime.now();
    final current = ref.watch(currentMusicProvider);
    final heroMusic = current ?? _firstOrNull(_personalSongs);

    return ListView(
      // 底部留白给竖屏壳的浮动迷你条 / Dock，内容可以滚到它们下面。
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      children: [
        if (widget.showAppBar) _buildHeader(context, wide: false, now: now),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.pageInsetWide,
          ),
          child: GreetingCard(
            onShuffle: _personalSongs.isNotEmpty ? _playSomething : null,
            onStartRoam: _openRoamOnboarding,
          ),
        ),
        if (heroMusic != null) ...[
          const SizedBox(height: BmTokens.s4),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BmTokens.pageInsetWide,
            ),
            child: HomeHeroCard(
              music: heroMusic,
              eyebrow: current == null ? '从推荐继续' : '继续聆听',
              onTap: () => _onHeroTap(heroMusic),
              onTogglePlay: _togglePlay,
            ),
          ),
        ],
        _buildSectionHeader(
          '为你推荐',
          wide: false,
          onMore: () => _openPlaylist('recommended', _personalSongs, '为你推荐'),
        ),
        _buildRecommendShelf(context),
        _buildSectionHeader('歌单', wide: false),
        _buildPlaylistShelf(context),
        _buildSectionHeader(
          '官方推荐',
          wide: false,
          trailing: _SectionAction(
            label: '换一批',
            onTap: _loading ? null : _refreshOfficial,
          ),
        ),
        _buildOfficialList(context, wide: false),
        const SizedBox(height: BmTokens.s6),
      ],
    );
  }

  Widget _buildWide(BuildContext context) {
    final now = DateTime.now();
    final current = ref.watch(currentMusicProvider);
    final heroMusic = current ?? _firstOrNull(_personalSongs);
    final history = ref.watch(playHistoryProvider).take(12).toList();

    return ListView(
      padding: BmTokens.contentPadding,
      children: [
        _buildHeader(context, wide: true, now: now),
        const SizedBox(height: BmTokens.s5),
        if (heroMusic != null)
          HomeHeroCard(
            music: heroMusic,
            wide: true,
            eyebrow: current == null ? '从推荐继续' : '继续聆听',
            onTap: () => _onHeroTap(heroMusic),
            onTogglePlay: _togglePlay,
          ),
        _buildSectionHeader(
          '为你推荐',
          wide: true,
          onMore: () => _openPlaylist('recommended', _personalSongs, '为你推荐'),
        ),
        _buildAlbumGrid(context),
        _buildSectionHeader('歌单', wide: true),
        _buildPlaylistGrid(context),
        _buildSectionHeader(
          '官方推荐',
          wide: true,
          trailing: _SectionAction(
            label: '换一批',
            onTap: _loading ? null : _refreshOfficial,
          ),
        ),
        _buildOfficialList(context, wide: true),
        _buildSectionHeader(
          '历史记录',
          wide: true,
          onMore: history.isEmpty
              ? null
              : () => _openPlaylist('history', history, '历史记录'),
        ),
        _buildTwoColumnList(
          context,
          songs: history,
          emptyTitle: '还没有播放记录',
          emptyIcon: Icons.history_rounded,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 页头

  Widget _buildHeader(
    BuildContext context, {
    required bool wide,
    required DateTime now,
  }) {
    final userState = ref.watch(userStateProvider);
    final title =
        widget.appBarTitle ??
        greetingText(now.hour, userState.userInfo?.userName);

    return BmPageHeader(
      eyebrow: greetingDateLabel(now),
      title: title,
      padding: wide
          ? const EdgeInsets.only(bottom: BmTokens.s2)
          : const EdgeInsets.fromLTRB(
              BmTokens.pageInsetWide,
              BmTokens.s4,
              BmTokens.pageInsetWide,
              BmTokens.s3,
            ),
      actions: wide
          ? [
              _HeaderGhost(
                icon: Icons.explore_outlined,
                label: '开始漫游',
                onTap: _openRoamOnboarding,
              ),
              if (_personalSongs.isNotEmpty)
                _HeaderGhost(
                  icon: Icons.shuffle_rounded,
                  label: '随便听听',
                  onTap: _playSomething,
                ),
            ]
          : [
              BmIconButton(
                icon: Icons.search_rounded,
                size: BmIconButtonSize.lg,
                soft: true,
                tooltip: '搜索',
                onPressed: _openSearchEntry,
              ),
              _AvatarButton(
                avatarUrl: userState.userInfo?.avatar,
                onTap: _openProfile,
              ),
            ],
    );
  }

  Widget _buildSectionHeader(
    String title, {
    required bool wide,
    VoidCallback? onMore,
    Widget? trailing,
  }) {
    return BmSectionHeader(
      title: title,
      onMore: onMore,
      trailing: trailing,
      padding: wide
          ? const EdgeInsets.only(top: BmTokens.s6, bottom: BmTokens.s3)
          : const EdgeInsets.fromLTRB(
              BmTokens.pageInsetWide,
              BmTokens.s6,
              BmTokens.pageInsetWide,
              BmTokens.s3,
            ),
    );
  }

  // ---------------------------------------------------------------- 竖屏货架

  Widget _buildRecommendShelf(BuildContext context) {
    final songs = _personalSongs.take(_personalShelfCount).toList();
    if (songs.isEmpty) {
      if (_loading) return _shelfSkeleton(BmTokens.shelfCoverLarge);
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: BmTokens.pageInsetWide),
        child: BmEmptyState(
          compact: true,
          icon: Icons.music_off_outlined,
          title: '还没攒够推荐',
          message: '多听几首，这里会按你的口味铺开',
        ),
      );
    }
    return BmShelf(
      itemWidth: BmTokens.shelfCoverLarge,
      height: BmShelf.heightFor(BmTokens.shelfCoverLarge),
      children: [
        for (final music in songs)
          BmMediaCard(
            cover: BmArtImage(url: music.safeCoverUrl, cacheKey: music.id),
            title: music.title,
            subtitle: music.artist.displayName,
            onTap: () => _playMusic(music),
          ),
      ],
    );
  }

  Widget _buildPlaylistShelf(BuildContext context) {
    return BmShelf(
      itemWidth: BmTokens.shelfCoverSmall,
      height: BmShelf.heightFor(BmTokens.shelfCoverSmall),
      children: _playlistCards(),
    );
  }

  Widget _shelfSkeleton(double itemWidth) {
    return BmShelf(
      itemWidth: itemWidth,
      height: BmShelf.heightFor(itemWidth),
      children: [
        for (var i = 0; i < 3; i++)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BmSkeleton(
                width: itemWidth,
                height: itemWidth,
                radius: BmTokens.albumArtRadius,
              ),
              const SizedBox(height: BmTokens.s2),
              BmSkeleton(width: itemWidth * 0.8, height: BmTokens.s3),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- 歌单卡

  Widget _playlistCard(Playlist playlist, int count) {
    final songs = playlist.songs;
    return PlaylistCard(
      playlist: playlist,
      subtitle: '$count 首',
      onTap: () => _openPlaylist(
        playlist.id,
        songs.isEmpty ? null : songs,
        playlist.name,
      ),
    );
  }

  List<Widget> _playlistCards() {
    final favorites = ref.watch(favoritesProvider);
    final history = ref.watch(playHistoryProvider);
    final daily = _buildDailyRecommendedPlaylist();
    final cards = <Widget>[
      _playlistCard(
        DefaultPlaylists.favorites..songs = favorites,
        favorites.length,
      ),
      _playlistCard(DefaultPlaylists.history..songs = history, history.length),
      _playlistCard(daily, daily.songCount),
    ];
    for (final playlist in ref.watch(userPlaylistsProvider).take(3)) {
      cards.add(_playlistCard(playlist, playlist.songCount));
    }
    return cards;
  }

  // ---------------------------------------------------------------- 官方推荐 / 历史

  Widget _buildOfficialList(BuildContext context, {required bool wide}) {
    final songs = (_officialSongs.take(wide ? 12 : 6)).toList();
    if (songs.isEmpty) {
      if (_loading) return _skeletonList(wide: wide);
      return const BmEmptyState(
        compact: true,
        icon: Icons.music_off_outlined,
        title: '暂无官方推荐',
      );
    }
    if (wide) {
      return _buildTwoColumnList(
        context,
        songs: songs,
        emptyTitle: '暂无官方推荐',
        emptyIcon: Icons.music_off_outlined,
      );
    }
    return Padding(
      // 行内自身有 6 的内边距，这里补齐到与分区标题对齐的 22
      padding: const EdgeInsets.symmetric(
        horizontal: BmTokens.pageInsetWide - (BmTokens.s1 + BmTokens.s1 / 2),
      ),
      child: Column(
        children: [
          for (var i = 0; i < songs.length; i++) ...[
            HomeTrackRow(music: songs[i], onTap: () => _playMusic(songs[i])),
            if (i != songs.length - 1)
              Divider(
                height: BmTokens.hairlineWidth,
                thickness: BmTokens.hairlineWidth,
                color: context.bmColors.hairline,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTwoColumnList(
    BuildContext context, {
    required List<Music> songs,
    required String emptyTitle,
    required IconData emptyIcon,
  }) {
    if (songs.isEmpty) {
      if (_loading) return _skeletonList(wide: true);
      return BmEmptyState(compact: true, title: emptyTitle, icon: emptyIcon);
    }
    return Column(
      children: [
        for (var i = 0; i < songs.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: BmTokens.s2),
            child: Row(
              children: [
                Expanded(
                  child: HomeTrackRow(
                    music: songs[i],
                    compact: true,
                    onTap: () => _playMusic(songs[i]),
                  ),
                ),
                const SizedBox(width: BmTokens.s6),
                Expanded(
                  child: i + 1 < songs.length
                      ? HomeTrackRow(
                          music: songs[i + 1],
                          compact: true,
                          onTap: () => _playMusic(songs[i + 1]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _skeletonList({required bool wide}) {
    return Padding(
      padding: wide
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: BmTokens.pageInsetWide),
      child: BmSkeleton.list(),
    );
  }

  // ---------------------------------------------------------------- 横屏网格

  Widget _buildAlbumGrid(BuildContext context) {
    final songs = _personalSongs.take(12).toList();
    if (songs.isEmpty) {
      if (_loading) return _gridSkeleton(context);
      return const BmEmptyState(
        compact: true,
        icon: Icons.music_off_outlined,
        title: '还没攒够推荐',
      );
    }
    return _responsiveGrid(
      context,
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final music = songs[index];
        return BmMediaCard(
          cover: BmArtImage(url: music.safeCoverUrl, cacheKey: music.id),
          title: music.title,
          subtitle: music.artist.displayName,
          onTap: () => _playMusic(music),
        );
      },
    );
  }

  Widget _buildPlaylistGrid(BuildContext context) {
    final cards = _playlistCards().take(4).toList();
    return _responsiveGrid(
      context,
      itemCount: cards.length,
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _gridSkeleton(BuildContext context) {
    final columns = _columnCount(context);
    return _responsiveGrid(
      context,
      itemCount: columns,
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: BmSkeleton(radius: BmTokens.albumArtRadius),
          ),
          const SizedBox(height: BmTokens.s2),
          const BmSkeleton(width: 120, height: BmTokens.s3),
        ],
      ),
    );
  }

  /// 4 列（≥1200）/ 3 列（900–1199）。
  int _columnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= LandscapeBreakpoints.desktopMin ? 4 : 3;
  }

  Widget _responsiveGrid(
    BuildContext context, {
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    final columns = _columnCount(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const double gap = BmTokens.s4 + BmTokens.s1 / 2;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        final itemHeight =
            itemWidth + _mediaCardTextBudget(context) + BmTokens.s1;
        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: itemWidth / itemHeight,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }

  /// [BmMediaCard] 封面以下的文字预算：8 间距 + 两行标题 + 1 间距 + 副标题。
  ///
  /// 行高按当前文字缩放算，避免大字号下网格卡片纵向溢出。
  double _mediaCardTextBudget(BuildContext context) {
    final type = context.bmType;
    final scaler = MediaQuery.textScalerOf(context);
    final titleLine = scaler.scale(type.label.fontSize!) * type.label.height!;
    final subtitleLine =
        scaler.scale(type.caption.fontSize!) * type.caption.height!;
    return BmTokens.s2 + titleLine * 2 + 1 + subtitleLine;
  }

  static Music? _firstOrNull(List<Music> songs) =>
      songs.isEmpty ? null : songs.first;
}

/// 页头右侧的描边胶囊按钮（横屏「开始漫游 / 随便听听」）。
class _HeaderGhost extends StatelessWidget {
  const _HeaderGhost({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.rPillAll,
      semanticLabel: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BmTokens.rPillAll,
          border: Border.all(
            color: colors.lineStrong,
            width: BmTokens.hairlineWidth,
          ),
        ),
        child: SizedBox(
          height: BmTokens.controlMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: BmTokens.iconMenu, color: colors.accentDeep),
                const SizedBox(width: BmTokens.s1),
                Text(
                  label,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 分区标题右侧的文字动作（「换一批」）。
class _SectionAction extends StatelessWidget {
  const _SectionAction({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r10All,
      enabled: onTap != null,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s2,
          vertical: BmTokens.s1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: BmTokens.s1 / 2),
            Icon(
              Icons.refresh_rounded,
              size: BmTokens.iconMenu,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 页头头像：32 圆，未登录时落一个人形图标。
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.avatarUrl, required this.onTap});

  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final url = avatarUrl;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.rPillAll,
      semanticLabel: '我的',
      child: Container(
        width: BmTokens.s8,
        height: BmTokens.s8,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.bgDeep,
          border: Border.all(
            color: colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
        ),
        alignment: Alignment.center,
        child: url == null || url.isEmpty
            ? Icon(
                Icons.person_rounded,
                size: BmTokens.iconTileGlyph,
                color: colors.textSecondary,
              )
            : BmArtImage(url: url),
      ),
    );
  }
}
