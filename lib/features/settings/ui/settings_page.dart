import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/lan_sync/ui/sync_page.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/features/onboarding/ui/open_onboarding.dart';
import 'package:bilimusic/features/settings/ui/widgets/theme_picker.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/gallery/bm_gallery_page.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/overlay/bm_select_menu.dart';
import 'package:bilimusic/shared/ui/sections/bm_page_header.dart';
import 'package:bilimusic/shared/ui/settings/bm_settings_group.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/app_version.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 设置页：页头 + 分组白卡，共八组。
///
/// 分区顺序固定为通知 → 播放 → 音频 → 外观 → 歌词 → 设备与同步 →
/// 数据 → 关于；横屏壳直接复用本页（[showAppBar] 传 false）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const List<BmSelectOption<String>> _qualityOptions =
      <BmSelectOption<String>>[
        BmSelectOption(value: '30251', label: 'Hi-Res 无损', subtitle: '需要大会员'),
        BmSelectOption(value: '30250', label: '杜比全景声', subtitle: '需要大会员'),
        BmSelectOption(value: '30280', label: '192K HQ'),
        BmSelectOption(value: '30232', label: '132K SQ'),
        BmSelectOption(value: '30216', label: '64K AAC-HE'),
      ];

  static const List<BmSelectOption<String>> _appearanceOptions =
      <BmSelectOption<String>>[
        BmSelectOption(value: 'system', label: '跟随系统'),
        BmSelectOption(value: 'light', label: '浅色'),
        BmSelectOption(value: 'dark', label: '深色'),
      ];

  static const List<BmSelectOption<String>>
  _closeBehaviorOptions = <BmSelectOption<String>>[
    BmSelectOption(value: SettingsManager.CLOSE_BEHAVIOR_PROMPT, label: '弹出提示'),
    BmSelectOption(
      value: SettingsManager.CLOSE_BEHAVIOR_MINIMIZE_TRAY,
      label: '最小化至托盘',
    ),
    BmSelectOption(value: SettingsManager.CLOSE_BEHAVIOR_EXIT, label: '直接退出'),
  ];

  static const List<BmSelectOption<String>> _lanSyncOptions =
      <BmSelectOption<String>>[
        BmSelectOption(value: 'off', label: '关闭', subtitle: '不广播也不发现'),
        BmSelectOption(value: 'private', label: '私有', subtitle: '配对后双向同步'),
        BmSelectOption(value: 'public', label: '公共', subtitle: '仅暴露正在播放'),
      ];

  /// 缓存上限可选档位（MB）。实际字节预算与淘汰在 core 的 CacheBudget 里，
  /// 这里只负责把用户选的档位传给 SettingsManager。
  static const List<int> _cacheLimitMbOptions = <int>[
    128,
    256,
    512,
    1024,
    2048,
    4096,
  ];

  /// 两个缓存上限下拉共用的选项表（label 与行尾 valueLabel 同源格式化）。
  static final List<BmSelectOption<int>> _cacheLimitOptions =
      <BmSelectOption<int>>[
        for (final mb in _cacheLimitMbOptions)
          BmSelectOption<int>(value: mb, label: _formatCacheLimitMb(mb)),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final isLandscape = LandscapeBreakpoints.shouldUseLandscapeLayout(context);
    final inset = isLandscape ? BmTokens.contentInset : BmTokens.pageInsetWide;
    final topInset = isLandscape ? BmTokens.contentInsetTop : BmTokens.s4;

    return Scaffold(
      // 透明让壳层的流体背景透出。
      backgroundColor: context.bmColors.bg.withValues(alpha: 0),
      body: SafeArea(
        top: !isLandscape,
        bottom: false,
        left: false,
        right: false,
        child: SingleChildScrollView(
          // 给竖屏浮动的迷你播放器 / Dock 让位；横屏该值即底部安全区。
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BmPageHeader(
                title: '设置',
                subtitle: _eyebrow(settings),
                padding: EdgeInsets.fromLTRB(inset, topInset, inset, 0),
              ),
              _buildGroupColumn(context, ref, settings, isLandscape),
              const SizedBox(height: BmTokens.s6),
            ],
          ),
        ),
      ),
    );
  }

  /// 横屏把分组卡内缩到与页头一致的 30，竖屏保持 16。
  Widget _buildGroupColumn(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
    bool isLandscape,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? BmTokens.contentInset - BmTokens.s4 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNotificationGroup(
            settings,
            ref.read(settingsProvider.notifier),
          ),
          _buildPlaybackGroup(
            context,
            settings,
            ref.read(settingsProvider.notifier),
          ),
          _buildAudioGroup(ref, settings),
          _buildAppearanceGroup(ref, settings),
          _buildLyricsGroup(settings, ref.read(settingsProvider.notifier)),
          _buildDeviceGroup(ref, settings),
          _buildDataGroup(settings, ref.read(settingsProvider.notifier)),
          _buildAboutGroup(context),
        ],
      ),
    );
  }

  Widget _buildNotificationGroup(
    SettingsState settings,
    SettingsNotifier notifier,
  ) {
    return BmSettingsGroup(
      title: '通知',
      children: [
        BmSettingsSwitchRow(
          title: '推送媒体通知',
          subtitle: '锁屏与通知栏的播放控制',
          icon: Icons.notifications_outlined,
          value: settings.notificationsEnabled,
          onChanged: notifier.setNotificationsEnabled,
        ),
      ],
    );
  }

  Widget _buildPlaybackGroup(
    BuildContext context,
    SettingsState settings,
    SettingsNotifier notifier,
  ) {
    return BmSettingsGroup(
      title: '播放',
      footer: '交叉淡入淡出仅对自动切歌生效；手动切歌不会触发。',
      children: [
        BmSettingsSwitchRow(
          title: '自动播放下一首',
          icon: Icons.play_arrow_outlined,
          value: settings.autoPlayNext,
          onChanged: notifier.setAutoPlayNext,
        ),
        BmSettingsSwitchRow(
          title: '交叉淡入淡出',
          subtitle: '歌曲自动切换时平滑过渡（仅自动切歌生效）',
          icon: Icons.graphic_eq_outlined,
          value: settings.crossfadeEnabled,
          onChanged: notifier.setCrossfadeEnabled,
        ),
        if (settings.crossfadeEnabled) ...[
          BmSettingsSwitchRow(
            title: '自动过渡（跟随歌曲时长）',
            subtitle: '过渡时长取歌曲时长的 3%（1–10 秒）',
            icon: Icons.auto_awesome_outlined,
            value: settings.crossfadeAuto,
            onChanged: notifier.setCrossfadeAuto,
          ),
          if (!settings.crossfadeAuto)
            BmSettingsSliderRow(
              title: '淡入淡出时长',
              icon: Icons.timer_outlined,
              value: settings.crossfadeDuration.toDouble(),
              min: 1000,
              max: 10000,
              divisions: 9,
              valueLabel: '${settings.crossfadeDuration ~/ 1000} 秒',
              onChanged: (value) =>
                  notifier.setCrossfadeDuration(value.toInt()),
            ),
          BmSettingsSliderRow(
            title: '提前加载时间',
            icon: Icons.download_outlined,
            value: settings.preloadSeconds.toDouble(),
            min: 5,
            max: 30,
            divisions: 25,
            valueLabel: '${settings.preloadSeconds} 秒',
            onChanged: (value) => notifier.setPreloadSeconds(value.toInt()),
          ),
        ],
        BmSettingsSwitchRow(
          title: '标题元数据过滤',
          subtitle: '新拉取的标题按规则清理元信息，关闭时原样保留',
          icon: Icons.auto_fix_high_outlined,
          value: settings.titleMetaFilterEnabled,
          onChanged: notifier.setTitleMetaFilterEnabled,
        ),
        if (settings.titleMetaFilterEnabled)
          BmSettingsRow(
            title: '标题过滤规则',
            subtitle: '正则表达式过滤 · 内置多种规则',
            icon: Icons.filter_alt_outlined,
            onTap: () =>
                ShellPageManager.instance.push(ShellPage.titleFilterRules),
            trailing: Text(
              '${settings.titleFilterRules.length} 条自定义',
              style: BmTypography.numeric(
                context.bmType.caption.copyWith(
                  color: context.bmColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioGroup(WidgetRef ref, SettingsState settings) {
    final notifier = ref.read(settingsProvider.notifier);
    return BmSettingsGroup(
      title: '音频',
      children: [
        BmSettingsSelectRow<String>(
          title: '播放音质',
          subtitle: '不可用时自动选最高可用音质',
          icon: Icons.high_quality_outlined,
          options: _qualityOptions,
          selected: settings.audioQuality,
          onChanged: notifier.setAudioQuality,
          menuWidth: 260,
        ),
        BmSettingsValueRow(
          title: '音效与均衡器',
          subtitle: '均衡器、音效、DSP 等音频处理',
          icon: Icons.equalizer_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.audioDsp),
        ),
        BmSettingsValueRow(
          title: '音频输出',
          subtitle: '延迟、独占模式、采样率与输出设备',
          icon: Icons.speaker_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.audioOutput),
        ),
      ],
    );
  }

  Widget _buildAppearanceGroup(WidgetRef ref, SettingsState settings) {
    final notifier = ref.read(settingsProvider.notifier);
    final descriptor = ThemeRegistry.resolve(settings.theme);
    return BmSettingsGroup(
      title: '外观',
      children: [
        BmSettingsSelectRow<String>(
          title: '外观',
          icon: Icons.brightness_6_outlined,
          options: _appearanceOptions,
          selected: settings.appearance,
          onChanged: notifier.setAppearance,
          menuWidth: 200,
        ),
        BmSettingsSelectRow<String>(
          title: '主题',
          subtitle: descriptor.subtitle,
          icon: Icons.palette_outlined,
          valueLeading: ThemePaletteDots(descriptor: descriptor),
          valueLabel: descriptor.label,
          options: themeSelectOptions(),
          // descriptor 归一值。
          selected: descriptor.id,
          onChanged: notifier.setTheme,
          menuWidth: 300,
        ),
        BmSettingsSwitchRow(
          title: '流体背景效果',
          subtitle: '为页面启用模糊背景',
          icon: Icons.auto_awesome_outlined,
          value: settings.fluidBackground,
          onChanged: notifier.setFluidBackground,
        ),
        BmSettingsSwitchRow(
          title: '毛玻璃效果',
          subtitle: '为迷你播放器栏启用毛玻璃效果',
          icon: Icons.blur_on_outlined,
          value: settings.blurEffect,
          onChanged: notifier.setBlurEffect,
        ),
        BmSettingsSwitchRow(
          title: '始终显示迷你播放器（竖屏）',
          subtitle: '在其他页面也显示；向下滚动时自动隐藏',
          icon: Icons.smart_display_outlined,
          value: settings.alwaysShowMiniPlayer,
          onChanged: notifier.setAlwaysShowMiniPlayer,
        ),
        if (PlatformHelper.isDesktop)
          BmSettingsSelectRow<String>(
            title: '关闭行为',
            subtitle: '关闭主窗口时的行为',
            icon: Icons.window_outlined,
            options: _closeBehaviorOptions,
            selected: settings.closeBehavior,
            onChanged: notifier.setCloseBehavior,
            menuWidth: 220,
          ),
      ],
    );
  }

  Widget _buildLyricsGroup(SettingsState settings, SettingsNotifier notifier) {
    return BmSettingsGroup(
      title: '歌词',
      children: [
        BmSettingsSwitchRow(
          title: '显示歌词',
          subtitle: '在播放页展开歌词视图',
          icon: Icons.lyrics_outlined,
          value: settings.showLyrics,
          onChanged: notifier.setShowLyrics,
        ),
      ],
    );
  }

  Widget _buildDeviceGroup(WidgetRef ref, SettingsState settings) {
    final notifier = ref.read(settingsProvider.notifier);
    return BmSettingsGroup(
      title: '设备与同步',
      children: [
        BmSettingsSelectRow<String>(
          title: '局域网同步',
          subtitle: _lanSyncModeText(settings.lanSyncMode),
          icon: Icons.wifi_tethering_outlined,
          options: _lanSyncOptions,
          selected: settings.lanSyncMode,
          onChanged: notifier.setLanSyncMode,
          menuWidth: 300,
        ),
        BmSettingsValueRow(
          title: '设备管理',
          subtitle: '发现设备、配对、查看本机 PIN',
          icon: Icons.devices_outlined,
          onTap: openLanSyncPage,
        ),
      ],
    );
  }

  Widget _buildDataGroup(SettingsState settings, SettingsNotifier notifier) {
    return BmSettingsGroup(
      title: '数据',
      children: [
        BmSettingsSelectRow<int>(
          title: '音乐缓存上限',
          subtitle: '播放时临时缓存音频，超出后按最久未用淘汰',
          icon: Icons.library_music_outlined,
          options: _cacheLimitOptions,
          selected: settings.musicCacheLimitMb,
          valueLabel: _formatCacheLimitMb(settings.musicCacheLimitMb),
          onChanged: notifier.setMusicCacheLimitMb,
          menuWidth: 200,
        ),
        BmSettingsSelectRow<int>(
          title: '图片缓存上限',
          subtitle: '封面与头图缓存，超出后按最久未用淘汰',
          icon: Icons.image_outlined,
          options: _cacheLimitOptions,
          selected: settings.imageCacheLimitMb,
          valueLabel: _formatCacheLimitMb(settings.imageCacheLimitMb),
          onChanged: notifier.setImageCacheLimitMb,
          menuWidth: 200,
        ),
        BmSettingsValueRow(
          title: '离线缓存',
          subtitle: '查看已下载到本地的音乐、占用空间与删除',
          icon: Icons.download_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.offline),
        ),
        BmSettingsValueRow(
          title: '音乐画像',
          subtitle: '口味关键词、推荐依据与手动重建',
          icon: Icons.insights_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.tasteProfile),
        ),
        BmSettingsValueRow(
          title: '数据管理',
          subtitle: '查看详细数据、缓存信息与数据操作',
          icon: Icons.storage_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.dataManagement),
        ),
      ],
    );
  }

  Widget _buildAboutGroup(BuildContext context) {
    final colors = context.bmColors;
    return BmSettingsGroup(
      title: '关于',
      children: [
        GestureDetector(
          onLongPress: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BmGalleryPage()),
            );
          },
          child: BmSettingsValueRow(
            title: '关于应用',
            subtitle: 'BiliMusic $appVersion · AGPL-3.0',
            icon: Icons.info_outlined,
            onTap: () => _showAboutDialog(context),
          ),
        ),
        BmSettingsValueRow(
          title: '更新日志',
          subtitle: '查看版本更新记录',
          icon: Icons.update_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.changelog),
        ),
        BmSettingsValueRow(
          title: '隐私政策',
          subtitle: '播放记录与设置只保存在本机',
          icon: Icons.privacy_tip_outlined,
          onTap: () => _showPrivacyPolicy(context),
        ),
        BmSettingsValueRow(
          title: '查看 Cookie',
          subtitle: '查看当前保存的 Cookie 信息',
          icon: Icons.cookie_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.cookie),
        ),
        BmSettingsRow(
          title: '查看 Github 仓库',
          subtitle: 'NaivG/BiliMusic',
          icon: Icons.code_outlined,
          onTap: () {
            final url = Uri.parse('https://github.com/NaivG/BiliMusic');
            launchUrl(url, mode: LaunchMode.externalApplication);
          },
          trailing: Icon(
            Icons.open_in_new_rounded,
            size: BmTokens.iconMenu,
            color: colors.textTertiary,
          ),
        ),
        BmSettingsValueRow(
          title: '音频诊断',
          subtitle: '播放引擎 / 媒体会话 / 音频焦点现场',
          icon: Icons.monitor_heart_outlined,
          onTap: () => ShellPageManager.instance.push(ShellPage.audioBackend),
        ),
      ],
    );
  }

  String _eyebrow(SettingsState settings) {
    final customName = settings.lanSyncDeviceName.trim();
    final device = customName.isEmpty ? _platformName() : customName;
    return 'BiliMusic $appVersion · $device';
  }

  static String _platformName() {
    return switch (PlatformHelper.currentPlatform) {
      PlatformType.android => 'Android',
      PlatformType.ios => 'iOS',
      PlatformType.windows => 'Windows',
      PlatformType.linux => 'Linux',
      PlatformType.macos => 'macOS',
      PlatformType.unknown => '本机',
    };
  }

  static String _lanSyncModeText(String mode) {
    return switch (mode) {
      'off' => '关闭：不广播也不发现',
      'private' => '私有：配对后双向同步（推荐）',
      'public' => '公共：仅对局域网暴露正在播放',
      _ => '关闭',
    };
  }

  /// 缓存上限的显示：1024 的整数倍显示 GB，其余显示 MB。
  static String _formatCacheLimitMb(int mb) =>
      mb % 1024 == 0 ? '${mb ~/ 1024} GB' : '$mb MB';

  /// 「关于应用」对话框。
  Future<void> _showAboutDialog(BuildContext context) async {
    final colors = context.bmColors;
    final type = context.bmType;
    final openGuide = await showBmDialog<bool>(
      context: context,
      builder: (dialogContext) => BmDialog(
        title: '关于应用',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BmTokens.r20All,
              child: Image.asset(
                'assets/ic_launcher.png',
                width: 84,
                height: 84,
              ),
            ),
            const SizedBox(height: BmTokens.s3),
            Text(
              'BiliMusic',
              style: type.title.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: BmTokens.s1 / 2),
            Text(
              '版本 $appVersion',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: BmTokens.s3),
            Text(
              '另一个基于 Flutter 开发的 Bilibili 音乐播放器应用',
              textAlign: TextAlign.center,
              style: type.body.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: BmTokens.s2),
            Text(
              '© 2025-2026 NaivG.',
              style: type.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
        actions: [
          BmDialogAction(
            label: '查看引导',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
          BmDialogAction(
            label: '关闭',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      ),
    );
    if (openGuide != true || !context.mounted) return;
    await openOnboarding(context);
  }

  Future<void> _showPrivacyPolicy(BuildContext context) {
    return showBmDialog<void>(
      context: context,
      builder: (dialogContext) => BmDialog(
        title: '隐私政策',
        content: const Text(
          '我们非常重视您的隐私保护。本应用不会收集上传您的个人隐私信息，'
          '所有数据仅存储在本地设备上。\n\n'
          '我们可能使用的信息包括：\n'
          '1. 播放历史记录\n'
          '2. 收藏列表\n'
          '3. 用户设置\n\n'
          '这些信息仅用于提供更好的用户体验，不会上传到任何服务器。\n\n'
          '如果您有任何疑问，请通过 Github Issues 联系我们。',
        ),
        actions: [
          BmDialogAction(
            label: '确定',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }
}
