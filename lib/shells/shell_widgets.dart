import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/providers/settings_provider.dart';
import 'package:bilimusic/components/common/background_blur_widget.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/pages/playlist_page.dart';
import 'package:bilimusic/pages/search/search_overlay.dart';
import 'package:bilimusic/pages/search/search_results_overlay.dart';
import 'package:bilimusic/pages/profile_page.dart';
import 'package:bilimusic/pages/settings_page.dart';
import 'package:bilimusic/pages/detail_page.dart';
import 'package:bilimusic/pages/changelog_page.dart';
import 'package:bilimusic/pages/cookie_page.dart';
import 'package:bilimusic/pages/data_management_page.dart';
import 'package:bilimusic/pages/data_migration_page.dart';
import 'package:bilimusic/pages/login_page.dart';
import 'package:bilimusic/pages/fav_import_page.dart';
import 'package:bilimusic/pages/roam_onboarding/roam_onboarding_page.dart';
import 'package:bilimusic/pages/sync_page.dart';

/// 竖屏与横屏两个壳共享的页面渲染逻辑。
///
/// 两个壳的差异点（home 是包不包 AppBar）通过
/// 参数注入；剩余的 11 个 ShellPage 走完全相同的渲染管线，
/// 新加页面只需在这里加一行。
Widget buildShellPageContent({
  required ShellPage page,
  required ShellPageManager pageManager,
  required Widget homePage,
}) {
  switch (page) {
    case ShellPage.home:
      return homePage;
    case ShellPage.search:
      return const SearchOverlay();
    case ShellPage.searchResults:
      final query = pageManager.getArgs<String>('query') ?? '';
      return SearchResultsOverlay(query: query);
    case ShellPage.profile:
      return const ProfilePage();
    case ShellPage.settings:
      return const SettingsPage();
    case ShellPage.detail:
      return const DetailPage();
    case ShellPage.playlist:
      final playlistId = pageManager.getArgs<String>('playlistId');
      final songs = pageManager.getArgs<List<Music>>('songs');
      final playlistName = pageManager.getArgs<String>('playlistName');
      return PlaylistPage(
        playlistId: playlistId,
        songs: songs,
        playlistName: playlistName,
      );
    case ShellPage.changelog:
      return const ChangelogPage();
    case ShellPage.cookie:
      return const CookiePage();
    case ShellPage.dataManagement:
      return const DataManagementPage();
    case ShellPage.dataMigration:
      return const DataMigrationPage();
    case ShellPage.favImport:
      return const FavImportPage();
    case ShellPage.login:
      return LoginPage();
    case ShellPage.roamOnboarding:
      return const RoamOnboardingPage();
    case ShellPage.lanSync:
      return const LanSyncPage();
  }
}

/// 共享的背景层：fluidBackground 关闭时退化为当前 surface 色块；
/// 开启时显示跟随当前播放曲目封面的模糊层。
Widget buildShellBackground(BuildContext context, WidgetRef ref) {
  if (ref.watch(settingsProvider).fluidBackground == false) {
    return Container(color: Theme.of(context).colorScheme.surface);
  }
  final currentMusic = ref.watch(currentMusicProvider);
  return AnimatedSwitcher(
    switchInCurve: Curves.linearToEaseOut,
    switchOutCurve: Curves.easeInToLinear,
    duration: const Duration(milliseconds: 400),
    child: BackgroundBlurWidget(
      key: ValueKey(currentMusic?.coverUrl),
      coverUrl: currentMusic?.coverUrl,
    ),
  );
}

/// 详情页独立动画层。
///
/// 从外层 AnimatedSwitcher 抽出来作为一个独立层，跟底层常规页面切换完全解耦。
/// 入场：从底部上滑 + 缩放 + 淡入；离场：下滑 + 缩放 + 淡出（镜像入场）。
Widget buildShellDetailLayer({required ShellPage currentPage}) {
  final showDetail = currentPage == ShellPage.detail;
  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 350),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) {
      final isOutgoing = animation.status == AnimationStatus.reverse;
      if (isOutgoing) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(0, 1),
            ).animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 0.92).animate(animation),
              child: child,
            ),
          ),
        );
      }
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(animation),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
            child: child,
          ),
        ),
      );
    },
    child: KeyedSubtree(
      key: ValueKey(showDetail),
      child: showDetail ? const DetailPage() : const SizedBox.shrink(),
    ),
  );
}

/// 共享的页面切换容器：300ms 淡入 + 横向轻微 slide。
/// 详见 [ShellPageManager.basePage]：当栈顶是 detail 时，调用方应该把
/// KeyedSubtree 的 key 设为 `ShellPageManager.basePage`，使 detail 进入/离开
/// 不会触发底层的过渡动画。
Widget shellPageSwitcher({required Key key, required Widget child}) {
  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 300),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
      );
    },
    child: KeyedSubtree(key: key, child: child),
  );
}
