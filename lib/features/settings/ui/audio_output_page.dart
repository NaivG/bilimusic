import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 音频输出（设置 → 音频）。
///
/// 占位页：当前承载「音频输出模式」（自设置页迁入）；输出设备选择、
/// 独占模式等选项规划中，落地后继续在此页扩展。
class AudioOutputPage extends ConsumerStatefulWidget {
  const AudioOutputPage({super.key});

  @override
  ConsumerState<AudioOutputPage> createState() => _AudioOutputPageState();
}

class _AudioOutputPageState extends ConsumerState<AudioOutputPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final primary = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '音频输出'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          ListTile(
            leading: Icon(Icons.volume_up, color: primary),
            title: const Text('音频输出模式'),
            subtitle: Text(
              '${ref.read(settingsManagerProvider).getAudioOutputModeText(settings.audioOutputMode)} · 仅 Android 可调',
            ),
            enabled: PlatformHelper.isAndroid,
            trailing: DropdownButton<String>(
              value: settings.audioOutputMode,
              items: const [
                DropdownMenuItem(value: 'aaudio', child: Text('AAudio (推荐)')),
                DropdownMenuItem(
                  value: 'audiotrack',
                  child: Text('AudioTrack'),
                ),
              ],
              onChanged: notifier.setAudioOutputMode,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '更多音频输出选项（输出设备、音频路由等）规划中，敬请期待。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
