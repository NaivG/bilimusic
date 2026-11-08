import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:bilimusic/app/shells/widgets/desktop_window_controls.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 横屏模式标题栏 - 基于ParticleMusic风格
///
/// Chrome 材质：底边 hairline + 可选背景模糊；左侧品牌区，搜索框贴在侧栏
/// 右缘（220），右侧为个人 / 设置 / 窗口控制。
class LandscapeTitleBar extends ConsumerWidget {
  /// 标题栏高度；联想面板贴在它下面。
  static const double height = 75;

  final VoidCallback? onBack;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmit;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onProfileTap;

  const LandscapeTitleBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchSubmit,
    this.onBack,
    this.onSettingsTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final blur = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );

    return SizedBox(
      height: height,
      child: BmChromeSurface(
        edges: const <BmChromeEdge>{BmChromeEdge.bottom},
        blur: blur,
        child: Stack(
          children: [
            // 可拖拽区域 + 双击最大化
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                if (!PlatformHelper.isDesktop) return;
                windowManager.startDragging();
              },
              onDoubleTap: () async {
                if (!PlatformHelper.isDesktop) return;
                final isMaximized = await windowManager.isMaximized();
                if (isMaximized) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              child: const SizedBox.expand(),
            ),
            // 主内容
            Stack(
              children: [
                // 左侧品牌元素
                Positioned(
                  left: BmTokens.s5,
                  top: 0,
                  bottom: 0,
                  child: const _Logo(),
                ),
                // 搜索框 - 位于侧栏右侧，始终带返回按钮
                Positioned(
                  left: 220,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BmTokens.s5,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: colors.hairline,
                          width: BmTokens.hairlineWidth,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BmIconButton(
                          icon: Icons.arrow_back_ios_rounded,
                          tooltip: '返回',
                          onPressed: onBack,
                        ),
                        const SizedBox(width: BmTokens.s2),
                        _TitleSearchField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          hintText: '搜索音乐、视频、用户...',
                          onChanged: onSearchChanged,
                          onSubmitted: onSearchSubmit,
                        ),
                      ],
                    ),
                  ),
                ),
                // 右侧设置和窗口控制
                Positioned(
                  right: BmTokens.s5,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    children: [
                      // 用户按钮
                      if (onProfileTap != null)
                        BmIconButton(
                          icon: Icons.person_outline,
                          tooltip: '我的',
                          onPressed: onProfileTap,
                        ),
                      const SizedBox(width: BmTokens.s1),
                      // 设置按钮
                      if (onSettingsTap != null)
                        BmIconButton(
                          icon: Icons.settings_outlined,
                          tooltip: '设置',
                          onPressed: onSettingsTap,
                        ),
                      // 窗口控制按钮
                      if (PlatformHelper.isDesktop) const BmWindowControls(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 品牌区：图标 + CabinSketch 标题 + Beta 徽标。
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return Row(
      children: [
        // 品牌图标
        Image.asset('assets/ic_launcher.png', width: 36, height: 36),
        const SizedBox(width: BmTokens.s2),
        // 标题文字
        Text(
          'BiliMusic',
          style: type.title.copyWith(fontFamily: 'CabinSketch'),
        ),
        const SizedBox(width: BmTokens.s2),
        // Beta 标识
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s1,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colors.accentSoft,
            borderRadius: BmTokens.r4All,
          ),
          child: Text('Beta', style: type.micro.copyWith(color: colors.accent)),
        ),
      ],
    );
  }
}

/// 标题栏搜索框
class _TitleSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _TitleSearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return BmField(
          controller: controller,
          focusNode: focusNode,
          width: 260,
          hintText: hintText,
          leading: const Icon(Icons.search),
          trailing: value.text.isEmpty
              ? null
              : BmIconButton(
                  icon: Icons.close,
                  tooltip: '清空',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          onChanged: onChanged,
          onSubmitted: (query) {
            final trimmed = query.trim();
            if (trimmed.isNotEmpty) onSubmitted(trimmed);
          },
        );
      },
    );
  }
}
