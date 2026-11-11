import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/domain/lan_sync_mode.dart';
import 'package:bilimusic/features/lan_sync/ui/sync_page.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/features/settings/ui/widgets/settings_option_sheet.dart';
import 'package:bilimusic/features/settings/ui/widgets/theme_picker.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/gallery/bm_gallery_page.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/sections/bm_page_header.dart';
import 'package:bilimusic/shared/ui/settings/bm_settings_group.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:bilimusic/shared/utils/title_meta_filter.dart';

/// 设置页：页头 + 分组白卡，共八组。
///
/// 分区顺序固定为通知 → 播放 → 音频 → 外观 → 歌词 → 设备与同步 →
/// 数据 → 关于；横屏壳直接复用本页（[showAppBar] 传 false）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 应用版本；关于弹窗与页头 eyebrow 共用同一处来源。
  static const String _appVersion = '1.11.0';

  static const List<BmSettingsOption<String>> _qualityOptions =
      <BmSettingsOption<String>>[
        BmSettingsOption(value: '30251', label: 'Hi-Res 无损', subtitle: '需要大会员'),
        BmSettingsOption(value: '30250', label: '杜比全景声', subtitle: '需要大会员'),
        BmSettingsOption(value: '30280', label: '192K HQ'),
        BmSettingsOption(value: '30232', label: '132K SQ'),
        BmSettingsOption(value: '30216', label: '64K AAC-HE'),
      ];

  static const List<BmSettingsOption<String>> _appearanceOptions =
      <BmSettingsOption<String>>[
        BmSettingsOption(value: 'system', label: '跟随系统'),
        BmSettingsOption(value: 'light', label: '浅色'),
        BmSettingsOption(value: 'dark', label: '深色'),
      ];

  static const List<BmSettingsOption<String>> _closeBehaviorOptions =
      <BmSettingsOption<String>>[
        BmSettingsOption(
          value: SettingsManager.CLOSE_BEHAVIOR_PROMPT,
          label: '弹出提示',
        ),
        BmSettingsOption(
          value: SettingsManager.CLOSE_BEHAVIOR_MINIMIZE_TRAY,
          label: '最小化至托盘',
        ),
        BmSettingsOption(
          value: SettingsManager.CLOSE_BEHAVIOR_EXIT,
          label: '直接退出',
        ),
      ];

  static const List<BmSettingsOption<String>> _lanSyncOptions =
      <BmSettingsOption<String>>[
        BmSettingsOption(value: 'off', label: '关闭', subtitle: '不广播也不发现'),
        BmSettingsOption(value: 'private', label: '私有', subtitle: '配对后双向同步'),
        BmSettingsOption(value: 'public', label: '公共', subtitle: '仅暴露正在播放'),
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
          _buildAudioGroup(context, ref, settings),
          _buildAppearanceGroup(context, ref, settings),
          _buildLyricsGroup(settings, ref.read(settingsProvider.notifier)),
          _buildDeviceGroup(context, ref, settings),
          _buildDataGroup(),
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
        BmSettingsRow(
          title: '标题元数据过滤（实验性）',
          subtitle: '过滤 B 站标题中的元信息，点按查看示例',
          icon: Icons.filter_alt_outlined,
          onTap: () => _showTitleFilterPreview(context),
          trailing: BmSwitch(
            value: settings.titleMetaFilterEnabled,
            onChanged: notifier.setTitleMetaFilterEnabled,
            semanticLabel: '标题元数据过滤',
          ),
        ),
      ],
    );
  }

  Widget _buildAudioGroup(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    final notifier = ref.read(settingsProvider.notifier);
    final manager = ref.read(settingsManagerProvider);
    return BmSettingsGroup(
      title: '音频',
      children: [
        BmSettingsValueRow(
          title: '播放音质',
          subtitle: '不可用时自动选最高可用音质',
          icon: Icons.high_quality_outlined,
          value: manager.getAudioQualityText(settings.audioQuality),
          onTap: () async {
            final value = await showSettingsOptionSheet<String>(
              context: context,
              title: '播放音质',
              options: _qualityOptions,
              selected: settings.audioQuality,
            );
            if (value != null) await notifier.setAudioQuality(value);
          },
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

  Widget _buildAppearanceGroup(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    final colors = context.bmColors;
    final notifier = ref.read(settingsProvider.notifier);
    final manager = ref.read(settingsManagerProvider);
    final descriptor = ThemeRegistry.resolve(settings.theme);
    return BmSettingsGroup(
      title: '外观',
      children: [
        BmSettingsValueRow(
          title: '外观',
          icon: Icons.brightness_6_outlined,
          value: manager.getAppearanceText(settings.appearance),
          onTap: () async {
            final value = await showSettingsOptionSheet<String>(
              context: context,
              title: '外观',
              options: _appearanceOptions,
              selected: settings.appearance,
            );
            if (value != null) await notifier.setAppearance(value);
          },
        ),
        BmSettingsRow(
          title: '主题',
          subtitle: descriptor.label,
          icon: Icons.palette_outlined,
          onTap: () => showThemePicker(
            context: context,
            currentThemeId: settings.theme,
            onSelected: (id) => notifier.setTheme(id),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemePaletteDots(descriptor: descriptor),
              const SizedBox(width: BmTokens.s1),
              Icon(
                Icons.chevron_right_rounded,
                size: BmTokens.iconMenu,
                color: colors.textTertiary,
              ),
            ],
          ),
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
          BmSettingsValueRow(
            title: '关闭行为',
            subtitle: '关闭主窗口时的行为',
            icon: Icons.window_outlined,
            value: manager.getCloseBehaviorText(settings.closeBehavior),
            onTap: () async {
              final value = await showSettingsOptionSheet<String>(
                context: context,
                title: '关闭行为',
                options: _closeBehaviorOptions,
                selected: settings.closeBehavior,
              );
              if (value != null) await notifier.setCloseBehavior(value);
            },
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

  Widget _buildDeviceGroup(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    final notifier = ref.read(settingsProvider.notifier);
    final mode = LanSyncMode.fromString(settings.lanSyncMode);
    return BmSettingsGroup(
      title: '设备与同步',
      children: [
        BmSettingsValueRow(
          title: '局域网同步',
          subtitle: _lanSyncModeText(settings.lanSyncMode),
          icon: Icons.wifi_tethering_outlined,
          value: modeShortLabel(mode),
          onTap: () async {
            final value = await showSettingsOptionSheet<String>(
              context: context,
              title: '局域网同步',
              options: _lanSyncOptions,
              selected: settings.lanSyncMode,
            );
            if (value != null) await notifier.setLanSyncMode(value);
          },
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

  Widget _buildDataGroup() {
    return BmSettingsGroup(
      title: '数据',
      children: [
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
            subtitle: 'BiliMusic $_appVersion · AGPL-3.0',
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
    return 'BiliMusic $_appVersion · $device';
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

  Future<void> _showTitleFilterPreview(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    const samples = <String>[
      '【 作者 / MV 】Starlight【中字】',
      '【Hi-Res】夜に駆ける【官方MV】',
      'MV / 打上花火【自翻】',
    ];
    return showBmDialog<void>(
      context: context,
      builder: (dialogContext) => BmDialog(
        title: '标题元数据过滤示例',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '开启后，新从 B 站拉取的标题会清理掉这类元信息：',
              style: type.body.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: BmTokens.s3),
            for (final sample in samples) ...[
              Text(
                sample,
                style: type.label.copyWith(color: colors.textPrimary),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: BmTokens.s2,
                  top: BmTokens.s1 / 2,
                ),
                child: Text(
                  '→ ${TitleMetaFilter.clean(sample).cleaned}',
                  style: type.label.copyWith(color: colors.accentDeep),
                ),
              ),
              const SizedBox(height: BmTokens.s2),
            ],
            Text(
              '音质信息（Hi-Res / 杜比等）不会被误删；'
              '已保存到歌单与历史的标题不回溯修改。',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAboutDialog(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return showBmDialog<void>(
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
              '版本 $_appVersion',
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
