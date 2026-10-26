import 'package:flutter/material.dart';
import 'package:bilimusic/shared/widgets/window_drag_area.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 自动适配的 AppBar
/// 在桌面平台整条标题栏可拖动窗口（见 [WindowDragArea]）
class AutoAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// 横屏模式下隐藏 [leading]。
  ///
  /// 横屏外壳的标题栏已经提供返回按钮，内页不再重复显示。
  final bool hideLeadingInLandscape;
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
  final bool? forceMaterialTransparency;

  const AutoAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.hideLeadingInLandscape = false,
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
    this.forceMaterialTransparency,
  });

  @override
  Widget build(BuildContext context) {
    final hideLeading =
        hideLeadingInLandscape &&
        LandscapeBreakpoints.shouldUseLandscapeLayout(context);

    final appBar = AppBar(
      key: key,
      leading: hideLeading ? null : leading,
      automaticallyImplyLeading: hideLeading
          ? false
          : automaticallyImplyLeading,
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
      forceMaterialTransparency: forceMaterialTransparency ?? false,
    );

    // 桌面端：整条标题栏（含无标题时的空白区）都能拖动窗口
    return WindowDragArea(child: appBar);
  }

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );

  /// 快速生成带有返回按钮和标题的 AppBar。
  ///
  /// 横屏外壳的标题栏已有返回按钮，此时内页不再显示；
  /// 竖屏下仅当页面栈可以返回时才显示。
  static AutoAppBar generateAppBar({
    required BuildContext context,
    required String title,
    bool showBackButton = true,
    List<Widget>? actions,
    Widget? leading,
    PreferredSizeWidget? bottom,
    double? elevation,
    Color? backgroundColor,
    Color? foregroundColor,
    double? toolbarHeight,
    bool? centerTitle,
  }) {
    final showBack =
        showBackButton &&
        ShellPageManager.instance.canPop &&
        !LandscapeBreakpoints.shouldUseLandscapeLayout(context);

    return AutoAppBar(
      leading:
          leading ??
          (showBack
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                  onPressed: () => ShellPageManager.instance.pop(),
                )
              : null),
      automaticallyImplyLeading: false,
      hideLeadingInLandscape: true,
      title: Text(title),
      actions: actions,
      bottom: bottom,
      elevation: elevation,
      backgroundColor: backgroundColor ?? Colors.transparent,
      foregroundColor: foregroundColor,
      toolbarHeight: toolbarHeight,
      centerTitle: centerTitle,
      forceMaterialTransparency: true,
    );
  }
}
