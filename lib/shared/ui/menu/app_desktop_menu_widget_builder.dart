import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// super_context_menu 的 scaffold 类型没有从 barrel 导出；与
// lib/shared/widgets/app_menu_button.dart 一样直接引内部实现。
// ignore: implementation_imports
import 'package:super_context_menu/src/scaffold/desktop/menu_widget_builder.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// Lucent 桌面菜单 builder。
///
/// 接管 `super_context_menu` 的浮层外观：容器走 [BmMenuSurface]（含 120ms
/// scale 入场），行走 [BmMenuRow]，分隔线与勾选图标全部读 Lucent token。
///
/// [AppContextMenu] 已默认注入；单独使用 [ContextMenuWidget] 时可传
/// `const AppDesktopMenuWidgetBuilder()`。
class AppDesktopMenuWidgetBuilder implements DesktopMenuWidgetBuilder {
  const AppDesktopMenuWidgetBuilder({this.maxWidth = 450});

  /// 浮层最大宽度。
  final double maxWidth;

  @override
  Widget buildMenuContainer(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    Widget child,
  ) {
    // 根菜单从锚点缩放；子菜单只做 8px 位移，父菜单不跟着动。
    final isRoot = menuInfo.isRoot;
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    return BmMenuSurface(
      maxWidth: maxWidth,
      entrance: isRoot ? BmMenuEntranceKind.scale : BmMenuEntranceKind.submenu,
      alignment: isRoot
          ? (isLtr ? Alignment.topLeft : Alignment.topRight)
          : (isLtr ? Alignment.centerLeft : Alignment.centerRight),
      child: child,
    );
  }

  @override
  Widget buildSeparator(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    MenuSeparator separator,
  ) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(
        horizontal: BmTokens.s2,
        vertical: BmTokens.s1,
      ),
      color: context.bmColors.hairline,
    );
  }

  @override
  Widget buildMenuItem(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    Key innerKey,
    DesktopMenuButtonState state,
    MenuElement element,
  ) {
    final colors = context.bmColors;
    final action = element is MenuAction ? element : null;
    final disabled = action?.attributes.disabled ?? false;
    final destructive = action?.attributes.destructive ?? false;
    final stateIcon = action == null ? null : _stateIcon(action.state);
    final hasCheckedItems = menuInfo.resolvedChildren.any(
      (child) => child is MenuAction && child.state != MenuActionState.none,
    );
    final iconTheme = menuInfo.iconTheme.copyWith(
      size: BmTokens.iconMenu,
      color: destructive ? colors.danger : colors.textSecondary,
    );
    final image = element.image?.asWidget(iconTheme);

    Widget? leading;
    if (element is DeferredMenuElement) {
      leading = SizedBox(
        width: BmTokens.iconMenu,
        height: BmTokens.iconMenu,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.textSecondary,
        ),
      );
    } else if (stateIcon != null || image != null || hasCheckedItems) {
      leading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stateIcon != null)
            Icon(stateIcon)
          else if (hasCheckedItems)
            const SizedBox(width: BmTokens.iconMenu),
          if (image != null) ...[
            if (stateIcon != null || hasCheckedItems)
              const SizedBox(width: BmTokens.s1),
            image,
          ],
        ],
      );
    }

    final activator = action?.activator;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.menuInset),
      child: Container(
        // 子菜单定位用的 render box，挂在行容器上（与默认实现一致）。
        key: innerKey,
        child: BmMenuRow(
          title: element.title ?? '',
          leading: leading,
          shortcut: activator == null ? null : _activatorLabel(activator),
          showChevron: element is Menu,
          enabled: !disabled,
          selected: state.selected,
          destructive: destructive,
        ),
      ),
    );
  }
}

/// [MenuActionState] → 16 尺寸状态图标；无状态返回 null。
IconData? _stateIcon(MenuActionState state) {
  switch (state) {
    case MenuActionState.none:
    case MenuActionState.checkOff:
      return null;
    case MenuActionState.checkOn:
      return Icons.check;
    case MenuActionState.checkMixed:
      return Icons.remove;
    case MenuActionState.radioOn:
      return Icons.radio_button_on;
    case MenuActionState.radioOff:
      return Icons.radio_button_off;
  }
}

/// [SingleActivator] → `Ctrl+Shift+K` 这类可读文案。
String _activatorLabel(SingleActivator activator) {
  return <String>[
    if (activator.control) 'Ctrl',
    if (activator.alt) 'Alt',
    if (activator.meta)
      defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Meta',
    if (activator.shift) 'Shift',
    activator.trigger.keyLabel,
  ].join('+');
}
