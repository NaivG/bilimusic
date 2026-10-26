import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// super_context_menu 没有公开「在指定位置打开菜单」的 API；这里直接复用它的
// 桌面菜单会话。
// PS: 这是个绿皮科技，能用就行
// ignore: implementation_imports
import 'package:super_context_menu/src/scaffold/desktop/menu_session.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/shared/theme/app_tokens.dart';

/// 点击触发的「更多」菜单按钮。
///
/// 桌面端直接复用 [ContextMenuSession] 渲染菜单浮层，外观与右键菜单一致；
/// 移动端改用底部操作单，避免桌面尺寸的菜单项在触屏上过小。
class AppMenuButton extends StatefulWidget {
  final Menu Function(BuildContext context) menuBuilder;
  final IconData icon;
  final String tooltip;
  final double iconSize;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;
  final BoxConstraints? constraints;

  const AppMenuButton({
    super.key,
    required this.menuBuilder,
    this.icon = Icons.more_horiz,
    this.tooltip = '更多',
    this.iconSize = 18,
    this.color,
    this.padding,
    this.visualDensity,
    this.constraints,
  });

  @override
  State<AppMenuButton> createState() => _AppMenuButtonState();
}

class _AppMenuButtonState extends State<AppMenuButton> {
  final GlobalKey _buttonKey = GlobalKey();

  void _openMenu() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Offset.zero
        : box.localToGlobal(Offset(0, box.size.height + 4));

    showAppMenu(context, menu: widget.menuBuilder(context), position: origin);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _buttonKey,
      onPressed: _openMenu,
      icon: Icon(widget.icon),
      iconSize: widget.iconSize,
      color: widget.color,
      tooltip: widget.tooltip,
      padding: widget.padding,
      visualDensity: widget.visualDensity,
      constraints: widget.constraints,
    );
  }
}

/// 弹出菜单。桌面端走和右键菜单同一套浮层，触屏端点开底部操作单。
Future<void> showAppMenu(
  BuildContext context, {
  required Menu menu,
  required Offset position,
}) async {
  if (_usesBottomSheet) {
    await _showMenuSheet(context, menu);
    return;
  }

  ContextMenuSession(
    context: context,
    menuWidgetBuilder: DefaultDesktopMenuWidgetBuilder(),
    onInitialPointerUp: const _EmptyListenable(),
    menu: menu,
    position: position,
    iconTheme: _desktopIconTheme(context),
    onDone: (_) {},
    tapRegionGroupIds: const <Object>{},
  );
}

/// 判断当前平台是否更适合用底部操作单。
bool get _usesBottomSheet {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// 与 `DesktopContextMenuWidget` 保持一致的图标颜色。
IconThemeData _desktopIconTheme(BuildContext context) {
  final brightness = MediaQuery.platformBrightnessOf(context);
  return const IconThemeData.fallback().copyWith(
    color: brightness == Brightness.light
        ? const Color(0xFF090909)
        : const Color(0xFFF0F0F0),
  );
}

class _EmptyListenable implements Listenable {
  const _EmptyListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

Future<void> _showMenuSheet(BuildContext context, Menu menu) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => _MenuSheet(menu: menu),
  );
}

class _MenuSheet extends StatefulWidget {
  final Menu menu;

  const _MenuSheet({required this.menu});

  @override
  State<_MenuSheet> createState() => _MenuSheetState();
}

class _MenuSheetState extends State<_MenuSheet> {
  late final List<Menu> _stack = [widget.menu];

  void _back() {
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: scheme.surfaceContainerHigh,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.radiusLg),
            ),
            side: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(scheme),
              if (_stack.length > 1) _buildSubmenuHeader(context),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  children: [
                    for (final element in _stack.last.children)
                      ..._buildElement(context, element),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildSubmenuHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _back,
            icon: const Icon(Icons.chevron_left),
            tooltip: '返回',
          ),
          Expanded(
            child: Text(
              _stack.last.title ?? '更多',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Iterable<Widget> _buildElement(
    BuildContext context,
    MenuElement element,
  ) sync* {
    final scheme = Theme.of(context).colorScheme;

    if (element is MenuSeparator) {
      yield Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Divider(height: 1, color: scheme.outlineVariant),
      );
      return;
    }

    if (element is MenuAction) {
      final disabled = element.attributes.disabled;
      final destructive = element.attributes.destructive;
      final textColor = disabled
          ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
          : destructive
          ? scheme.error
          : scheme.onSurface;
      final iconColor = disabled
          ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
          : destructive
          ? scheme.error
          : scheme.onSurfaceVariant;
      final iconTheme = IconThemeData(size: 22, color: iconColor);

      yield ListTile(
        enabled: !disabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: element.image?.asWidget(iconTheme),
        title: Text(
          element.title ?? '',
          style: TextStyle(fontSize: 15, color: textColor),
        ),
        onTap: disabled
            ? null
            : () {
                Navigator.of(context).pop();
                element.callback();
              },
      );
      return;
    }

    if (element is Menu) {
      final iconTheme = IconThemeData(size: 22, color: scheme.onSurfaceVariant);
      yield ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: element.image?.asWidget(iconTheme),
        title: Text(
          element.title ?? '',
          style: TextStyle(fontSize: 15, color: scheme.onSurface),
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        onTap: () => setState(() => _stack.add(element)),
      );
      return;
    }
  }
}
