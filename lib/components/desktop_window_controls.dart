import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bilimusic/utils/platform_helper.dart';

/// 桌面端窗口控制栏：可拖动 + 窗口按钮
class DesktopWindowControls extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final double height;

  const DesktopWindowControls({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    // 非桌面平台返回空容器
    if (!PlatformHelper.isDesktop) {
      return SizedBox(height: height);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a1a1a) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: Row(
                children: [
                  if (leading != null) leading!,
                  if (title != null)
                    Expanded(child: title!)
                  else
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Text(
                          'BiliMusic',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (actions != null) ...actions!,
                ],
              ),
            ),
          ),
          _WindowButtons(isDark: isDark),
        ],
      ),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  final bool isDark;
  final VoidCallback? onClose;

  const _WindowButtons({required this.isDark, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: Icons.minimize,
          isDark: isDark,
          onTap: () => windowManager.minimize(),
          hoverColor: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        _WindowButton(
          icon: Icons.crop_square,
          isDark: isDark,
          onTap: () => windowManager.maximize(),
          hoverColor: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        _WindowButton(
          icon: Icons.close,
          isDark: isDark,
          onTap: () {
            onClose?.call();
            windowManager.close();
          },
          hoverColor: Colors.red,
          iconHoverColor: Colors.white,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final Color hoverColor;
  final Color? iconHoverColor;

  const _WindowButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
    required this.hoverColor,
    this.iconHoverColor,
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
          height: double.infinity,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered && widget.iconHoverColor != null
                  ? widget.iconHoverColor!
                  : (widget.isDark ? Colors.grey[400]! : Colors.grey[700]!),
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面端窗口导航栏（含 Logo + 导航项）
class DesktopNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onNavTap;
  final VoidCallback? onClose;

  const DesktopNavBar({
    super.key,
    required this.selectedIndex,
    required this.onNavTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // 非桌面平台返回空导航栏
    if (!PlatformHelper.isDesktop) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final navItems = [
      _NavItem(Icons.home_outlined, Icons.home, '首页', 0),
      _NavItem(Icons.search_outlined, Icons.search, '搜索', 1),
      _NavItem(Icons.person_outlined, Icons.person, '我的', 2),
      _NavItem(Icons.settings_outlined, Icons.settings, '设置', 3),
    ];

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a1a1a) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'BiliMusic',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.grey[800]!,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: navItems.map((item) {
                final isActive = selectedIndex == item.index;
                return _NavTile(
                  icon: isActive ? item.activeIcon : item.icon,
                  label: item.label,
                  isActive: isActive,
                  isDark: isDark,
                  onTap: () => onNavTap(item.index),
                );
              }).toList(),
            ),
          ),
          _WindowButtons(isDark: isDark, onClose: onClose),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;

  _NavItem(this.icon, this.activeIcon, this.label, this.index);
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? theme.colorScheme.primary
                      : (isDark ? Colors.grey[400]! : Colors.grey[700]!),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? theme.colorScheme.primary
                        : (isDark ? Colors.grey[400]! : Colors.grey[700]!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
