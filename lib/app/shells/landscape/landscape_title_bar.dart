import 'package:flutter/material.dart';
import 'package:bilimusic/services/pip_service.dart';
import 'package:bilimusic/theme/app_palette.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:window_manager/window_manager.dart';

/// 横屏模式标题栏 - 基于ParticleMusic风格
class LandscapeTitleBar extends StatelessWidget {
  final VoidCallback? onBack;
  final String? pendingQuery;
  final Function(String query)? onSearchSubmit;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onProfileTap;

  const LandscapeTitleBar({
    super.key,
    this.onBack,
    this.pendingQuery,
    this.onSearchSubmit,
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
      height: 75,
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
              if (onSearchSubmit != null)
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
                          hintText: '搜索音乐、视频、用户...',
                          pendingQuery: pendingQuery,
                          iconColor: iconColor,
                          searchFieldColor: searchFieldColor,
                          textColor: colorScheme.onSurface,
                          onSubmitted: onSearchSubmit!,
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
class _TitleSearchField extends StatefulWidget {
  final String hintText;
  final String? pendingQuery;
  final Function(String query) onSubmitted;
  final Color iconColor;
  final Color searchFieldColor;
  final Color textColor;

  const _TitleSearchField({
    required this.hintText,
    this.pendingQuery,
    required this.onSubmitted,
    required this.iconColor,
    required this.searchFieldColor,
    required this.textColor,
  });

  @override
  State<_TitleSearchField> createState() => _TitleSearchFieldState();
}

class _TitleSearchFieldState extends State<_TitleSearchField> {
  late TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.pendingQuery ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 40,
      child: TapRegion(
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          style: TextStyle(fontSize: 14, color: widget.textColor),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              fontSize: 14,
              color: widget.textColor.withValues(alpha: 0.5),
            ),
            contentPadding: EdgeInsets.zero,
            prefixIcon: Icon(
              Icons.search,
              color: widget.iconColor.withValues(alpha: 0.65),
              size: 18,
            ),
            suffixIcon: _textController.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _textController.clear();
                      setState(() {});
                    },
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: widget.iconColor.withValues(alpha: 0.65),
                    ),
                  )
                : null,
            filled: true,
            fillColor: widget.searchFieldColor,
            hoverColor: Colors.transparent,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (query) {
            if (query.isNotEmpty) {
              widget.onSubmitted(query);
            }
          },
          onChanged: (_) => setState(() {}),
        ),
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
