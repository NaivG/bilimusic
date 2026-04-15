import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:bilimusic/utils/platform_helper.dart';

/// 自动适配的 AppBar
/// 在桌面平台使用 MoveWindow 包裹，支持窗口拖动
class AutoAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;
  final double? elevation;
  final double? scrolledUnderElevation;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconThemeData? iconTheme;
  final IconThemeData? actionsIconTheme;
  final bool? excludeHeaderSemantics;
  final TextStyle? titleTextStyle;
  final TextStyle? toolbarTextStyle;
  final double? toolbarHeight;
  final double? leadingWidth;
  final Color? surfaceTintColor;
  final bool? primary;
  final bool? centerTitle;
  final double? titleSpacing;
  final double? toolbarOpacity;
  final double? bottomOpacity;

  const AutoAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.flexibleSpace,
    this.bottom,
    this.elevation,
    this.scrolledUnderElevation,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.actionsIconTheme,
    this.excludeHeaderSemantics,
    this.titleTextStyle,
    this.toolbarTextStyle,
    this.toolbarHeight,
    this.leadingWidth,
    this.surfaceTintColor,
    this.primary = true,
    this.centerTitle,
    this.titleSpacing,
    this.toolbarOpacity,
    this.bottomOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      key: key,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: title,
      actions: actions,
      flexibleSpace: flexibleSpace,
      bottom: bottom,
      elevation: elevation,
      scrolledUnderElevation: scrolledUnderElevation,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      iconTheme: iconTheme,
      actionsIconTheme: actionsIconTheme,
      excludeHeaderSemantics: excludeHeaderSemantics ?? false,
      titleTextStyle: titleTextStyle,
      toolbarTextStyle: toolbarTextStyle,
      toolbarHeight: toolbarHeight,
      leadingWidth: leadingWidth,
      surfaceTintColor: surfaceTintColor,
      primary: primary ?? true,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      toolbarOpacity: toolbarOpacity ?? 1.0,
      bottomOpacity: bottomOpacity ?? 1.0,
    );

    if (!PlatformHelper.isDesktop) {
      return appBar;
    }

    return MoveWindow(child: appBar);
  }

  @override
  Size get preferredSize => Size.fromHeight(
    toolbarHeight ?? kToolbarHeight + (bottom?.preferredSize.height ?? 0),
  );
}
