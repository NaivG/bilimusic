/// Lucent 设计系统的对外入口。
///
/// - token：几何/颜色/排版，见 `tokens/`
/// - 主题：`BmTheme.build()` 把 6 套主题的 ColorScheme + AppPalette 组装成 ThemeData
/// - Chrome 原语：`chrome/`（BmChromeSurface / BmNavBar / BmNavRow）
/// - Stage 原语：`stage/`（BmStageBackdrop）
/// - 控件原语：`controls/`（BmIconButton / BmField）
/// - 预览页：`gallery/bm_gallery_page.dart`（设置 → 关于应用 长按进入）
library;

export 'chrome/bm_chrome.dart';
export 'controls/bm_controls.dart';
export 'stage/bm_stage_backdrop.dart';
export 'gallery/bm_gallery_page.dart';
export 'tokens/bm_colors.dart';
export 'tokens/bm_tokens.dart';
export 'tokens/bm_typography.dart';
export 'theme/bm_component_themes.dart';
export 'theme/bm_theme.dart';
