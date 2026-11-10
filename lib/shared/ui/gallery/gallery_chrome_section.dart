import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_page_switcher.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/gallery/gallery_sections.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 分区 9：Chrome + 页面切换预览。
///
/// 铺开贴边栏、浮块、底栏与导航行四类 Chrome 原语；在固定高度的
/// 容器里跑 [BmPageSwitcher] 的 tab / push / pop / replace 四档过渡，方向由
/// 按钮决定。reduce motion 由页面外层 `MediaQuery.disableAnimations` 广播，
/// 本分区不另设开关。
class GalleryChromeSection extends StatefulWidget {
  const GalleryChromeSection({super.key});

  @override
  State<GalleryChromeSection> createState() => _GalleryChromeSectionState();
}

class _GalleryChromeSectionState extends State<GalleryChromeSection> {
  static const List<String> _navLabels = <String>['首页', '发现', '歌单', '设置'];

  bool _blur = true;
  bool _playing = false;
  int _navIndex = 0;

  int _pageNumber = 1;
  BmPageTransitionKind _kind = BmPageTransitionKind.tab;
  int _direction = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GallerySection(
          title: 'Chrome',
          description:
              '贴边栏直角 + 单边 hairline，浮块 14 圆角 + 四边 hairline + shadow；'
              '模糊开启时 chrome + 24 高斯，关闭时 chromeOpaque。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: BmTokens.s2,
                runSpacing: BmTokens.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '模糊',
                    style: type.label.copyWith(color: colors.textSecondary),
                  ),
                  Switch(
                    key: const Key('bm-gallery-chrome-blur'),
                    value: _blur,
                    onChanged: (value) => setState(() => _blur = value),
                  ),
                  Text(
                    _blur ? 'blur: on' : 'blur: off · chromeOpaque',
                    style: type.micro.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: BmTokens.s3),
              _ChromeDemo(
                label: '贴边标题栏 · BmChromeSurface(edges: bottom)',
                child: _buildTitleBar(context),
              ),
              const SizedBox(height: BmTokens.s4),
              _ChromeDemo(
                label: '浮块 · BmChromeSurface(floating: true)',
                child: _buildMiniPlayer(context),
              ),
              const SizedBox(height: BmTokens.s4),
              _ChromeDemo(
                label: '底栏 · BmNavBar（当前选中：${_navLabels[_navIndex]}）',
                child: _buildNavBar(context),
              ),
              const SizedBox(height: BmTokens.s4),
              const _ChromeDemo(
                label: '导航行 · BmNavRow（选中 / 未选中 / trailing 数量）',
                child: _NavRowDemo(),
              ),
            ],
          ),
        ),
        const SizedBox(height: BmTokens.s4),
        GallerySection(
          title: '页面切换',
          description:
              '固定高度容器内演示 tab / push / pop / replace：方向由 direction 决定；'
              'reduce motion 读取外层 MediaQuery，位移与 dim 自动关闭。',
          child: _buildPageSwitcher(context),
        ),
      ],
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return SizedBox(
      height: BmTokens.s8 * 2,
      child: BmChromeSurface(
        blur: _blur,
        edges: const <BmChromeEdge>{BmChromeEdge.bottom},
        padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
        child: Row(
          children: [
            Icon(
              Icons.music_note_rounded,
              size: BmTokens.iconLarge,
              color: colors.accent,
            ),
            const SizedBox(width: BmTokens.s2),
            Text(
              'BiliMusic',
              style: type.bodyStrong.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: BmTokens.s6),
            const Expanded(
              child: BmField(
                hintText: '搜索音乐、视频、用户',
                leading: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(width: BmTokens.s2),
            BmIconButton(
              icon: Icons.settings_outlined,
              tooltip: '设置',
              onPressed: () {},
            ),
            BmIconButton(
              icon: Icons.person_outline_rounded,
              tooltip: '账号',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return SizedBox(
      width: BmTokens.s8 * 13,
      child: BmChromeSurface(
        floating: true,
        blur: _blur,
        child: SizedBox(
          height: BmTokens.s8 * 2 + BmTokens.s1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
            child: Row(
              children: [
                Container(
                  width: BmTokens.controlLg,
                  height: BmTokens.controlLg,
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BmTokens.r10All,
                    border: Border.all(
                      color: colors.hairline,
                      width: BmTokens.hairlineWidth,
                    ),
                  ),
                  child: Icon(
                    Icons.album_rounded,
                    size: BmTokens.icon,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(width: BmTokens.s3),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '夜航星',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '不才',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                BmIconButton(
                  icon: _playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  tooltip: _playing ? '暂停' : '播放',
                  color: colors.accent,
                  iconSize: BmTokens.iconLarge,
                  hitSize: BmTokens.touchScreen,
                  onPressed: () => setState(() => _playing = !_playing),
                ),
                BmIconButton(
                  icon: Icons.playlist_play_rounded,
                  tooltip: '播放列表',
                  iconSize: BmTokens.iconLarge,
                  hitSize: BmTokens.touchScreen,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    return SizedBox(
      width: BmTokens.s8 * 12,
      child: BmDock(
        items: const <BmDockItem>[
          BmDockItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: '首页',
          ),
          BmDockItem(
            icon: Icons.explore_outlined,
            activeIcon: Icons.explore_rounded,
            label: '发现',
          ),
          BmDockItem(
            icon: Icons.library_music_outlined,
            activeIcon: Icons.library_music_rounded,
            label: '歌单',
          ),
          BmDockItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: '设置',
          ),
        ],
        selectedIndex: _navIndex,
        blur: _blur,
        onSelected: (index) => setState(() => _navIndex = index),
      ),
    );
  }

  Widget _buildPageSwitcher(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: BmTokens.s8 * 7,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BmTokens.r14All,
            border: Border.all(
              color: colors.hairline,
              width: BmTokens.hairlineWidth,
            ),
          ),
          child: BmPageSwitcher(
            pageKey: ValueKey<String>('bm-gallery-page-$_pageNumber'),
            kind: _kind,
            direction: _direction,
            child: _SwitcherPage(
              pageNumber: _pageNumber,
              kind: _kind,
              direction: _direction,
            ),
          ),
        ),
        const SizedBox(height: BmTokens.s3),
        Wrap(
          spacing: BmTokens.s2,
          runSpacing: BmTokens.s2,
          children: [
            FilledButton(
              onPressed: () => _switchPage(BmPageTransitionKind.tab, -1),
              child: const Text('Tab 左'),
            ),
            FilledButton(
              onPressed: () => _switchPage(BmPageTransitionKind.tab, 1),
              child: const Text('Tab 右'),
            ),
            OutlinedButton(
              onPressed: () => _switchPage(BmPageTransitionKind.push, 1),
              child: const Text('Push'),
            ),
            OutlinedButton(
              onPressed: () => _switchPage(BmPageTransitionKind.pop, -1),
              child: const Text('Pop'),
            ),
            OutlinedButton(
              onPressed: () => _switchPage(BmPageTransitionKind.replace, 1),
              child: const Text('Replace'),
            ),
          ],
        ),
        const SizedBox(height: BmTokens.s2),
        Text(
          reduceMotion
              ? 'reduce motion 已开启：只保留短淡入，不做位移与压暗'
              : 'tab 240ms 双淡 · push / pop 300ms 弹簧 · replace 180ms 纯淡',
          style: type.micro.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  /// 自增 pageKey，并记录本次过渡的 kind / direction。
  void _switchPage(BmPageTransitionKind kind, int direction) {
    setState(() {
      _pageNumber += 1;
      _kind = kind;
      _direction = direction;
    });
  }
}

/// 演示页：显示页码与本次切换的 kind / direction。
class _SwitcherPage extends StatelessWidget {
  const _SwitcherPage({
    required this.pageNumber,
    required this.kind,
    required this.direction,
  });

  final int pageNumber;
  final BmPageTransitionKind kind;
  final int direction;

  String get _kindLabel => switch (kind) {
    BmPageTransitionKind.tab => 'tab 同层切换',
    BmPageTransitionKind.push => 'push 进入下一层',
    BmPageTransitionKind.pop => 'pop 返回上一层',
    BmPageTransitionKind.replace => 'replace 原地替换',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return ColoredBox(
      color: pageNumber.isEven ? colors.surfaceRaised : colors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: BmTokens.iconLarge,
              color: colors.accent,
            ),
            const SizedBox(height: BmTokens.s2),
            Text(
              '第 $pageNumber 页',
              style: type.title.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: BmTokens.s1),
            Text(
              '$_kindLabel · direction ${direction > 0 ? '+1' : '-1'}',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// BmNavRow 的三种形态：选中 / 未选中 / 带 trailing 数量。
class _NavRowDemo extends StatelessWidget {
  const _NavRowDemo();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return SizedBox(
      width: BmTokens.s8 * 10,
      child: Column(
        children: [
          BmNavRow(
            icon: Icons.library_music_outlined,
            activeIcon: Icons.library_music_rounded,
            title: '我的歌单',
            selected: true,
            onTap: () {},
          ),
          BmNavRow(icon: Icons.history_rounded, title: '最近播放', onTap: () {}),
          BmNavRow(
            icon: Icons.favorite_border_rounded,
            activeIcon: Icons.favorite_rounded,
            title: '我喜欢的音乐',
            trailing: Text(
              '128',
              style: BmTypography.numeric(
                type.caption.copyWith(color: colors.textTertiary),
              ),
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// Chrome demo 的统一外壳：小标签 + 内容。
class _ChromeDemo extends StatelessWidget {
  const _ChromeDemo({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: type.micro.copyWith(color: colors.textSecondary)),
        const SizedBox(height: BmTokens.s2),
        child,
      ],
    );
  }
}
