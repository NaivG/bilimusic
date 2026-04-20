import 'package:flutter/material.dart';
import 'package:bilimusic/utils/color_infra.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:window_manager/window_manager.dart';

/// 横屏模式标题栏 - 基于ParticleMusic风格
class LandscapeTitleBar extends StatelessWidget {
  final VoidCallback? onBack;
  final String? pendingQuery;
  final Function(String query)? onSearchSubmit;
  final VoidCallback? onSettingsTap;

  const LandscapeTitleBar({
    super.key,
    this.onBack,
    this.pendingQuery,
    this.onSearchSubmit,
    this.onSettingsTap,
  });

  Row _buildLogo() {
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
            color: highlightTextColor,
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

  /// 构建返回按钮
  Widget _buildBackButton() {
    return IconButton(
      color: iconColor,
      onPressed: onBack,
      icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, _) {
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
                  Positioned(left: 20, top: 0, bottom: 0, child: _buildLogo()),
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
                              color: iconColor.withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildBackButton(),
                            const SizedBox(width: 8),
                            _TitleSearchField(
                              hintText: '搜索音乐、视频、用户...',
                              pendingQuery: pendingQuery,
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
      },
    );
  }
}

/// 标题栏搜索框
class _TitleSearchField extends StatefulWidget {
  final String hintText;
  final String? pendingQuery;
  final Function(String query) onSubmitted;

  const _TitleSearchField({
    required this.hintText,
    this.pendingQuery,
    required this.onSubmitted,
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
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: widget.hintText,
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
            suffixIcon: _textController.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _textController.clear();
                      setState(() {});
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          icon: Icons.minimize,
          onTap: () => windowManager.minimize(),
        ),
        _WindowButton(
          icon: Icons.crop_square,
          onTap: () async {
            final isMaximized = await windowManager.isMaximized();
            if (isMaximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          icon: Icons.close,
          onTap: () => windowManager.close(),
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          color: _isHovered
              ? (widget.isClose ? Colors.red : iconColor.withValues(alpha: 0.1))
              : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered && widget.isClose
                  ? Colors.white
                  : iconColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
