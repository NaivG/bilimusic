import 'package:flutter/material.dart';

/// Theater 几何 / 尺寸 token。
///
/// 与主题无关：6 套主题 × 深浅共用同一份 const，随主题变化的只有
/// [BmColors]。组件统一通过 `context.bm` 读取；主题未注入时回退
/// [BmTokens.standard]，保证测试与早期 build 阶段不抛异常。
@immutable
class BmTokens extends ThemeExtension<BmTokens> {
  const BmTokens();

  static const BmTokens standard = BmTokens();

  // ===== Radius =====
  static const double r4 = 4;
  static const double r9 = 9;
  static const double r10 = 10;
  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r18 = 18;
  static const double r20 = 20;
  static const double r26 = 26;
  static const double r28 = 28;
  static const double rPill = 999;

  static const BorderRadius r4All = BorderRadius.all(Radius.circular(r4));
  static const BorderRadius r9All = BorderRadius.all(Radius.circular(r9));
  static const BorderRadius r10All = BorderRadius.all(Radius.circular(r10));
  static const BorderRadius r12All = BorderRadius.all(Radius.circular(r12));
  static const BorderRadius r14All = BorderRadius.all(Radius.circular(r14));
  static const BorderRadius r16All = BorderRadius.all(Radius.circular(r16));
  static const BorderRadius r18All = BorderRadius.all(Radius.circular(r18));
  static const BorderRadius r20All = BorderRadius.all(Radius.circular(r20));
  static const BorderRadius r26All = BorderRadius.all(Radius.circular(r26));
  static const BorderRadius r28All = BorderRadius.all(Radius.circular(r28));
  static const BorderRadius rPillAll = BorderRadius.all(Radius.circular(rPill));

  // ===== Spacing（7 档）=====
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // ===== 行高 =====
  static const double rowCompact = 40;
  static const double row = 48;
  static const double rowTall = 56;

  /// 设置行（设计稿 `.srow` min-height）。
  static const double settingRow = 56;

  /// 竖屏曲目行。
  static const double trackRow = 58;

  /// 横屏曲目行。
  static const double trackRowCompact = 56;

  /// 队列 / 资料库抽屉行。
  static const double drawerRow = 54;

  // ===== 控件高 =====
  static const double controlSm = 28;
  static const double controlMd = 34;
  static const double controlLg = 40;

  // ===== 图标（只允许这几档）=====
  static const double iconInline = 14;
  static const double iconMenu = 16;
  static const double icon = 20;
  static const double iconLarge = 24;

  /// 设置行 / 列表行的图标底座边长。
  static const double iconTile = 32;

  /// 底座内图标边长。
  static const double iconTileGlyph = 18;

  /// 底座圆角。
  static const BorderRadius iconTileRadius = r9All;

  // ===== 开关（设计稿 52×32，thumb 28，行程 20）=====
  static const double switchWidth = 52;
  static const double switchHeight = 32;
  static const double switchThumb = 28;
  static const double switchTravel = 20;

  // ===== 页面 =====
  /// 竖屏内容左右边距。
  static const double pageInset = 20;

  /// 竖屏页头左右边距（设计稿 `.page-head` padding 22）。
  static const double pageInsetWide = 22;

  /// 横屏内容区左右边距（设计稿 `.content` padding 24/30/34）。
  static const double contentInset = 30;

  /// 横屏内容区上边距。
  static const double contentInsetTop = 24;

  /// 横屏内容区下边距。
  static const double contentInsetBottom = 34;

  // ===== 卡片 / 封面 =====
  /// 设置组、面板卡。
  static const double cardRadius = 14;

  /// 曲目白卡。
  static const double mediaCardRadius = 16;

  /// 歌单封面。
  static const double coverRadius = 16;

  /// 专辑封面缩略图。
  static const BorderRadius albumArtRadius = r9All;

  // ===== 竖屏壳：浮动 Dock =====
  static const double dockHeight = 60;
  static const double dockInset = 12;
  static const double dockBottom = 18;
  static const double dockItemHeight = 46;

  /// 悬停 / 选中时导航项长到的高度；Dock 内上下各留 2。
  static const double dockItemHeightActive = 56;
  static const double dockItemWidth = 88;
  static const double dockItemRadius = dockItemHeightActive / 2;
  static const BorderRadius dockItemRadiusAll = BorderRadius.all(
    Radius.circular(dockItemRadius),
  );
  static const BorderRadius dockRadius = BorderRadius.all(
    Radius.circular(dockHeight / 2),
  );

  // ===== 竖屏壳：迷你播放器 =====
  static const double miniPlayerHeight = 52;
  static const double miniPlayerCover = 36;
  static const double miniPlayerInset = 14;
  static const double miniPlayerBottom = 84;
  static const BorderRadius miniPlayerRadius = r26All;
  static const BorderRadius miniCoverRadius = r9All;

  /// 页面滚动内容在竖屏壳底部要给 Dock + 迷你条让出的高度。
  static const double portraitBottomBudget =
      miniPlayerBottom + miniPlayerHeight + 22;

  /// 只有迷你条、没有 Dock 时的底部预算。
  static const double miniPlayerOnlyBottomBudget =
      dockBottom + miniPlayerHeight + s6;

  // ===== 横屏壳 =====
  static const double railWidth = 76;
  static const double railLogo = 38;
  static const double railItem = 44;
  static const double railItemGap = 6;
  static const BorderRadius railItemRadius = r12All;

  static const double topbarHeight = 58;
  static const double searchFieldWidth = 340;
  static const double searchFieldLeft = 188;

  static const double libraryDrawerWidth = 320;
  static const double queuePanelWidth = 420;

  // ===== 媒体卡 =====
  static const double shelfCoverLarge = 155;
  static const double shelfCoverSmall = 108;

  /// 首页「继续聆听」卡高度；宽度由页面内容宽决定（横竖屏同一套版式）。
  static const double homeHeroPortrait = 282;
  static const double homeHeroLandscape = 272;

  static const double playlistCoverPortrait = 176;
  static const double playlistCoverLandscape = 196;

  /// 分类 / 标签胶囊高。
  static const double chipHeight = 21;

  // ===== Chrome 浮层（菜单 / 对话框 / Sheet）=====
  /// 菜单行高（设计文档 §4.6）。
  static const double menuRow = 32;

  /// 菜单浮层内边距（设计文档 §4.6）。
  static const double menuInset = 6;

  // ===== Chrome 材质（设计文档 §4.9 / §4.11）=====
  /// 0.5px hairline 宽。
  static const double hairlineWidth = 0.5;

  /// Chrome 表面模糊 sigma。
  static const double chromeBlurSigma = 24;

  /// Stage 封面虚化纹理 sigma。
  static const double stageCoverBlurSigma = 64;

  /// 竖屏导航项图标。
  static const double navIcon = 21;

  /// 旧贴边底栏高（已被浮动 Dock 取代，保留给尚未迁移的调用点）。
  static const double navBarHeight = 56;

  /// 侧栏 / 导航行高。
  static const double navRowHeight = 44;

  /// 侧栏选中条宽（横屏 rail 不再画条，保留给旧调用点）。
  static const double navIndicatorWidth = 3;

  // ===== 触摸区下限 =====
  static const double touchDesktop = 40;
  static const double touchScreen = 44;

  // ===== 常用内边距 =====
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: pageInset,
  );
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: s4,
    vertical: s2,
  );

  /// 横屏内容区边距。
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(
    contentInset,
    contentInsetTop,
    contentInset,
    contentInsetBottom,
  );

  /// 取当前主题注入的 token；未注入时回退 [standard]。
  static BmTokens of(BuildContext context) =>
      Theme.of(context).extension<BmTokens>() ?? standard;

  @override
  BmTokens copyWith() => this;

  @override
  BmTokens lerp(ThemeExtension<BmTokens>? other, double t) => this;
}

extension BmTokensContext on BuildContext {
  BmTokens get bm => BmTokens.of(this);
}
