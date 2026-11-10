import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:bilimusic/app/shells/widgets/desktop_window_controls.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/controls/bm_field.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 横屏标题栏（设计稿 `.topbar`）。
///
/// 高 58（900–1199 为 52）；只放返回、面包屑、搜索与窗口控制。
/// 品牌 / 头像 / 设置只在图标轨出现。
class LandscapeTitleBar extends ConsumerWidget {
  /// 面包屑末段：当前页面名。
  final String pageTitle;

  final VoidCallback? onBack;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmit;

  const LandscapeTitleBar({
    super.key,
    required this.pageTitle,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchSubmit,
    this.onBack,
  });

  /// 面包屑宽度：搜索框左缘之前扣掉左右留白、返回键与间距。
  static const double _crumbWidth =
      BmTokens.searchFieldLeft -
      BmTokens.s5 -
      BmTokens.touchScreen -
      BmTokens.s2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;
    final blur = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );

    return SizedBox(
      height: LandscapeBreakpoints.topbarHeight(context),
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
            // 返回 + 面包屑
            Positioned(
              left: BmTokens.s5,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BmIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: '返回',
                    size: BmIconButtonSize.sm,
                    hitSize: BmTokens.touchScreen,
                    onPressed: onBack,
                  ),
                  const SizedBox(width: BmTokens.s2),
                  SizedBox(
                    width: _crumbWidth,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'BiliMusic / ',
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: pageTitle,
                            style: type.caption.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 搜索框：workspace 坐标左缘 188、宽 340、高 40
            Positioned(
              left: BmTokens.searchFieldLeft,
              top: 0,
              bottom: 0,
              child: Center(
                child: _TitleSearchField(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  onChanged: onSearchChanged,
                  onSubmitted: onSearchSubmit,
                ),
              ),
            ),
            // 窗口控制
            if (PlatformHelper.isDesktop)
              Positioned(
                right: BmTokens.s5,
                top: 0,
                bottom: 0,
                child: const Center(child: BmWindowControls()),
              ),
          ],
        ),
      ),
    );
  }
}

/// 标题栏搜索框：清空按钮随输入内容出现。
class _TitleSearchField extends StatelessWidget {
  const _TitleSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return BmField(
          controller: controller,
          focusNode: focusNode,
          width: BmTokens.searchFieldWidth,
          hintText: '搜索音乐、视频、用户...',
          leading: const Icon(Icons.search_rounded),
          trailing: value.text.isEmpty
              ? null
              : BmIconButton(
                  icon: Icons.close_rounded,
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
