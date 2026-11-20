import 'package:flutter/material.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/shared/ui/menu/app_desktop_menu_widget_builder.dart';
import 'package:bilimusic/shared/ui/menu/app_mobile_menu_widget_builder.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';

/// 项目统一的右键 / 长按菜单入口。
///
/// 内部包装 [ContextMenuWidget]，注入 Lucent 的桌面 / 移动两个 builder；
/// 图标基色默认取 [BmColors.textPrimary]，不跟随系统亮暗反色。
///
/// ```dart
/// AppContextMenu(
///   menuProvider: (request) async => Menu(children: <MenuElement>[...]),
///   child: MusicTile(...),
/// )
/// ```
class AppContextMenu extends StatelessWidget {
  const AppContextMenu({
    super.key,
    required this.menuProvider,
    required this.child,
    this.hitTestBehavior = HitTestBehavior.deferToChild,
    this.contextMenuIsAllowed,
    this.tapRegionGroupIds = const <Object>{},
    this.iconTheme,
  });

  final MenuProvider menuProvider;
  final Widget child;
  final HitTestBehavior hitTestBehavior;

  /// 菜单是否允许在该全局坐标弹出；默认总是允许。
  final ContextMenuIsAllowed? contextMenuIsAllowed;

  /// 点击菜单时保持输入焦点的 tap region 组。
  final Set<Object> tapRegionGroupIds;

  /// 菜单图标基色；默认 [BmColors.textPrimary]。
  final IconThemeData? iconTheme;

  @override
  Widget build(BuildContext context) {
    return ContextMenuWidget(
      menuProvider: menuProvider,
      hitTestBehavior: hitTestBehavior,
      contextMenuIsAllowed: contextMenuIsAllowed ?? _alwaysAllowed,
      tapRegionGroupIds: tapRegionGroupIds,
      iconTheme:
          iconTheme ?? IconThemeData(color: context.bmColors.textPrimary),
      desktopMenuWidgetBuilder: const AppDesktopMenuWidgetBuilder(),
      mobileMenuWidgetBuilder: AppMobileMenuWidgetBuilder.instance,
      child: child,
    );
  }
}

bool _alwaysAllowed(Offset _) => true;
