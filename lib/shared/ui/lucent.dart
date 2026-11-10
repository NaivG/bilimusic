/// Theater 设计系统的对外入口。
///
/// - token：几何/颜色/排版，见 `tokens/`
/// - 主题：`BmTheme.build()` 把 6 套主题的 ColorScheme + AppPalette 组装成 ThemeData
/// - Chrome 原语：`chrome/`（BmChromeSurface / BmDock / BmNavRow）
/// - 表面：`surfaces/`（BmCard）
/// - 分区与页头：`sections/`（BmSectionHeader / BmPageHeader）
/// - 设置行：`settings/`（BmSettingsGroup / BmSettingsRow…）
/// - 卡片：`cards/`（BmMediaCard / BmArtImage）
/// - 货架：`shelves/`（BmShelf，仅竖屏）
/// - 状态：`status/`（BmSkeleton / BmEmptyState）
/// - Stage 原语：`stage/`（BmStageBackdrop）
/// - 控件原语：`controls/`（BmIconButton / BmField / BmSwitch / BmChip）
/// - 预览页：`gallery/bm_gallery_page.dart`（设置 → 关于应用 长按进入）
library;

export 'cards/bm_media_card.dart';
export 'chrome/bm_chrome.dart';
export 'controls/bm_controls.dart';
export 'gallery/bm_gallery_page.dart';
export 'sections/bm_page_header.dart';
export 'sections/bm_section_header.dart';
export 'settings/bm_settings_group.dart';
export 'stage/bm_audio_quality_badge.dart';
export 'stage/bm_stage_backdrop.dart';
export 'status/bm_empty.dart';
export 'status/bm_skeleton.dart';
export 'surfaces/bm_card.dart';
export 'tokens/bm_colors.dart';
export 'tokens/bm_tokens.dart';
export 'tokens/bm_typography.dart';
export 'theme/bm_component_themes.dart';
export 'theme/bm_theme.dart';
