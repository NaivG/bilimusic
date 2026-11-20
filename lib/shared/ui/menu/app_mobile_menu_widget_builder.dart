import 'package:flutter/material.dart';

// super_context_menu 的 scaffold 类型没有从 barrel 导出；与
// lib/shared/widgets/app_menu_button.dart 一样直接引内部实现。
// ignore: implementation_imports
import 'package:super_context_menu/src/scaffold/mobile/menu_widget_builder.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// Lucent 移动端菜单 builder。
///
/// 覆盖 `super_context_menu` 的 9 个构建方法：外层阴影容器、内层 floating 面、
/// 列表容器、header、菜单行、inactive veil、遮罩与预览容器全部读 Lucent token。
/// 行统一用 44 高的 [BmMenuRow]，按下态映射到 `selected`。
class AppMobileMenuWidgetBuilder extends MobileMenuWidgetBuilder {
  const AppMobileMenuWidgetBuilder();

  /// 全局唯一实例，注入 [ContextMenuWidget] 用。
  static const AppMobileMenuWidgetBuilder instance =
      AppMobileMenuWidgetBuilder();

  @override
  Widget buildMenuContainer(
    BuildContext context,
    MobileMenuInfo menuInfo,
    Widget child,
  ) {
    final colors = context.bmColors;
    return AnimatedContainer(
      duration: motionDuration(context, menuInfo.transitionDuration),
      decoration: BoxDecoration(
        borderRadius: BmTokens.r14All,
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            offset: const Offset(0, BmTokens.s1),
            blurRadius: BmTokens.s4,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BmTokens.r14All, child: child),
    );
  }

  @override
  Widget buildMenuContainerInner(
    BuildContext context,
    MobileMenuInfo menuInfo,
    Widget child,
  ) {
    final colors = context.bmColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.floating,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      padding: const EdgeInsets.all(BmTokens.menuInset),
      child: child,
    );
  }

  @override
  Widget buildMenu(
    BuildContext context,
    MobileMenuInfo menuInfo,
    Widget child,
  ) {
    return child;
  }

  @override
  Widget buildMenuItemsContainer(
    BuildContext context,
    MobileMenuInfo menuInfo,
    Widget child,
  ) {
    return Scrollbar(child: child);
  }

  @override
  Widget buildMenuHeader(
    BuildContext context,
    MobileMenuInfo menuInfo,
    MobileMenuButtonState state,
  ) {
    // 折叠中的父菜单与所有子菜单都给返回箭头；根菜单只显示标题。
    final showBack = menuInfo.isCollapsed || !menuInfo.isRoot;
    return BmMenuRow(
      title: menuInfo.menu.title ?? '',
      leading: showBack ? const Icon(Icons.arrow_back) : null,
      height: BmTokens.touchScreen,
      selected: state.pressed,
    );
  }

  @override
  Widget buildInactiveMenuVeil(BuildContext context, MobileMenuInfo menuInfo) {
    final colors = context.bmColors;
    // depth 0 是活动菜单，不遮；叠得越深遮罩越重。
    final alpha = BmAlpha.scrim * menuInfo.depth.clamp(0, 3) / 3;
    return AnimatedContainer(
      duration: motionDuration(context, BmMotion.medium),
      color: colors.scrim.withValues(alpha: alpha),
    );
  }

  @override
  Widget buildMenuItem(
    BuildContext context,
    MobileMenuInfo menuInfo,
    MobileMenuButtonState state,
    MenuElement element,
  ) {
    final colors = context.bmColors;
    if (element is MenuSeparator) {
      return Container(
        height: 0.5,
        margin: const EdgeInsets.symmetric(
          horizontal: BmTokens.s2,
          vertical: BmTokens.s1,
        ),
        color: colors.hairline,
      );
    }

    final action = element is MenuAction ? element : null;
    final disabled = action?.attributes.disabled ?? false;
    final destructive = action?.attributes.destructive ?? false;
    final leading = element.image?.asWidget(
      menuInfo.iconTheme.copyWith(
        size: BmTokens.iconMenu,
        color: destructive ? colors.danger : colors.textSecondary,
      ),
    );

    Widget? trailing;
    if (element is DeferredMenuElement) {
      trailing = SizedBox(
        width: BmTokens.icon,
        height: BmTokens.icon,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.textSecondary,
        ),
      );
    } else if (action != null) {
      final icon = _stateIcon(action.state);
      if (icon != null) trailing = Icon(icon);
    }

    return BmMenuRow(
      title: element.title ?? '',
      leading: leading,
      trailing: trailing,
      showChevron: element is Menu,
      height: BmTokens.touchScreen,
      enabled: !disabled,
      selected: state.pressed,
      destructive: destructive,
    );
  }

  @override
  Widget buildOverlayBackground(BuildContext context, double opacity) {
    return Opacity(
      opacity: opacity,
      child: Container(color: context.bmColors.scrim),
    );
  }

  @override
  Widget buildMenuPreviewContainer(BuildContext context, Widget child) {
    final colors = context.bmColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.floating,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            offset: const Offset(0, BmTokens.s1),
            blurRadius: BmTokens.s4,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BmTokens.r14All, child: child),
    );
  }
}

/// [MenuActionState] → 状态图标；无状态返回 null。
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
