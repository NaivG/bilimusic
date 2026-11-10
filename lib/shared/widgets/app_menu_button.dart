import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// super_context_menu 没有公开「在指定位置打开菜单」的 API，这里直接复用它的
// 桌面菜单会话。
// ignore: implementation_imports
import 'package:super_context_menu/src/scaffold/desktop/menu_session.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/menu/app_desktop_menu_widget_builder.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:bilimusic/shared/ui/overlay/bm_overlays.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

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
    menuWidgetBuilder: const AppDesktopMenuWidgetBuilder(),
    onInitialPointerUp: const _EmptyListenable(),
    menu: menu,
    position: position,
    iconTheme: IconThemeData(color: context.bmColors.textPrimary),
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

class _EmptyListenable implements Listenable {
  const _EmptyListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

Future<void> _showMenuSheet(BuildContext context, Menu menu) async {
  await showBmSheet<void>(
    context: context,
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
    return BmSheet(
      padding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s2,
        vertical: BmTokens.s1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_stack.length > 1) _buildSubmenuHeader(context),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final element in _stack.last.children)
                  ..._buildElement(context, element),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmenuHeader(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Row(
      children: [
        _SheetIconButton(
          icon: Icons.chevron_left,
          semanticLabel: '返回',
          onTap: _back,
        ),
        Expanded(
          child: Text(
            _stack.last.title ?? '更多',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: type.bodyStrong.copyWith(color: colors.textPrimary),
          ),
        ),
        _SheetIconButton(
          icon: Icons.close,
          semanticLabel: '关闭',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Iterable<Widget> _buildElement(
    BuildContext context,
    MenuElement element,
  ) sync* {
    final colors = context.bmColors;

    if (element is MenuSeparator) {
      yield Divider(
        height: BmTokens.s2,
        thickness: 0.5,
        indent: BmTokens.s2,
        endIndent: BmTokens.s2,
        color: colors.hairline,
      );
      return;
    }

    if (element is MenuAction) {
      final disabled = element.attributes.disabled;
      final destructive = element.attributes.destructive;
      final iconTheme = IconThemeData(
        size: BmTokens.iconMenu,
        color: destructive ? colors.danger : colors.textSecondary,
      );

      yield BmMenuRow(
        title: element.title ?? '',
        leading: element.image?.asWidget(iconTheme),
        height: BmTokens.touchScreen,
        enabled: !disabled,
        destructive: destructive,
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
      final iconTheme = IconThemeData(
        size: BmTokens.iconMenu,
        color: colors.textSecondary,
      );
      yield BmMenuRow(
        title: element.title ?? '',
        leading: element.image?.asWidget(iconTheme),
        height: BmTokens.touchScreen,
        showChevron: true,
        onTap: () => setState(() => _stack.add(element)),
      );
    }
  }
}

/// 底部单里的图标按钮：44 触摸区 + 20 图标。
class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r10All,
      semanticLabel: semanticLabel,
      child: SizedBox.square(
        dimension: BmTokens.touchScreen,
        child: Icon(
          icon,
          size: BmTokens.icon,
          color: context.bmColors.textSecondary,
        ),
      ),
    );
  }
}
