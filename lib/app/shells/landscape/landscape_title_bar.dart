import 'package:flutter/material.dart';
import 'package:bilimusic/features/player/pip/pip_service.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:window_manager/window_manager.dart';

/// 横屏模式标题栏 - 基于ParticleMusic风格
class LandscapeTitleBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final iconColor = colorScheme.onSurfaceVariant;
    final searchFieldColor = palette.searchField;

    return SizedBox(
      height: height,
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
            child: Container(),
          ),
          // 主内容
          Stack(
            children: [
              // 左侧品牌元素
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: _buildLogo(colorScheme),
              ),
              // 搜索框 - 位于侧栏右侧，始终带返回按钮
              Positioned(
                left: 220,
                top: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    border: BoxBorder.fromLTRB(
                      left: BorderSide(
                        color: colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        color: iconColor,
                        onPressed: onBack,
                        icon: const Icon(
                          Icons.arrow_back_ios_rounded,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TitleSearchField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        hintText: '搜索音乐、视频、用户...',
                        iconColor: iconColor,
                        searchFieldColor: searchFieldColor,
                        textColor: colorScheme.onSurface,
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmit,
                      ),
                    ],
                  ),
                ),
              ),
              // 右侧设置和窗口控制
              Positioned(
                right: 30,
                top: 0,
                bottom: 0,
                child: Row(
                  children: [
                    // 用户按钮
                    if (onProfileTap != null)
                      IconButton(
                        color: iconColor,
                        onPressed: onProfileTap,
                        icon: const Icon(Icons.person_outline, size: 22),
                      ),
                    const SizedBox(width: 4),
                    // 设置按钮
                    if (onSettingsTap != null)
                      IconButton(
                        color: iconColor,
                        onPressed: onSettingsTap,
                        icon: const Icon(Icons.settings_outlined, size: 22),
                      ),
                    // 窗口控制按钮
                    if (PlatformHelper.isDesktop) const _WindowControls(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(ColorScheme colorScheme) {
    return Row(
      children: [
        // 品牌图标
        Image.asset("assets/ic_launcher.png", width: 36, height: 36),
        const SizedBox(width: 8),
        // 标题文字
        Text(
          'BiliMusic',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 24,
            color: colorScheme.onSurface,
            fontFamily: 'CabinSketch',
          ),
        ),
        const SizedBox(width: 8),
        // Beta标识
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.cyan.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Beta',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
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
  final Color iconColor;
  final Color searchFieldColor;
  final Color textColor;

  const _TitleSearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
    required this.iconColor,
    required this.searchFieldColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 40,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: TextStyle(fontSize: 14, color: textColor),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontSize: 14,
                color: textColor.withValues(alpha: 0.5),
              ),
              contentPadding: EdgeInsets.zero,
              prefixIcon: Icon(
                Icons.search,
                color: iconColor.withValues(alpha: 0.65),
                size: 18,
              ),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: iconColor.withValues(alpha: 0.65),
                      ),
                    )
                  : null,
              filled: true,
              fillColor: searchFieldColor,
              hoverColor: Colors.transparent,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (query) {
              final trimmed = query.trim();
              if (trimmed.isNotEmpty) onSubmitted(trimmed);
            },
            onChanged: onChanged,
          );
        },
      ),
    );
  }
}

/// 窗口控制按钮
class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.picture_in_picture_alt, size: 20),
          color: iconColor,
          onPressed: () => PipService().toggle(),
        ),
        IconButton(
          icon: const Icon(Icons.minimize_rounded, size: 20),
          color: iconColor,
          onPressed: () => windowManager.minimize(),
        ),
        IconButton(
          icon: const Icon(Icons.crop_square_rounded, size: 20),
          color: iconColor,
          onPressed: () async {
            final isMaximized = await windowManager.isMaximized();
            if (isMaximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          color: iconColor,
          onPressed: () => windowManager.close(),
          hoverColor: Colors.red.withValues(alpha: 0.1),
        ),
      ],
    );
  }
}
