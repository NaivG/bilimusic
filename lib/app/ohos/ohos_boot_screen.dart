import 'dart:io';

import 'package:flutter/material.dart';

/// OHOS 启动壳当前状态。
@immutable
class OhosBootState {
  final String status;
  final String? error;

  const OhosBootState({required this.status, this.error});
}

/// 启动壳状态：`main()` 在 OHOS 分支里更新，页面只负责显示。
///
/// 首帧先由这个壳画出来，插件初始化再在后台继续；成功之后
/// `_bootstrapApp()` 会 `runApp` 真正的 `MyApp` 覆盖它。
final ValueNotifier<OhosBootState> ohosBootState = ValueNotifier(
  const OhosBootState(status: '正在准备 HarmonyOS 启动环境…'),
);

/// OHOS 首帧启动壳。
///
/// 不依赖 Riverpod、数据库、音频或任何插件——这些正是接下来要逐项接的。
class OhosBootScreen extends StatelessWidget {
  const OhosBootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7BB8FF),
        useMaterial3: true,
      ),
      home: const _OhosBootPage(),
    );
  }
}

class _OhosBootPage extends StatelessWidget {
  const _OhosBootPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/ic_launcher.png', width: 72),
                  const SizedBox(height: 20),
                  Text(
                    'BiliMusic',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'HarmonyOS / OpenHarmony 启动壳',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ValueListenableBuilder<OhosBootState>(
                    valueListenable: ohosBootState,
                    builder: (context, state, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.status,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: SelectableText(
                                state.error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SelectableText(
                            'os=${Platform.operatingSystem}  '
                            'dart=${Platform.version.split(' ').first}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '首帧已交给 Flutter 渲染。存储、数据库、通知与播放后端'
                    '（libmpv，见 packages/mpv_audio_kit_ohos）均已接入；'
                    'libmpv 加载失败时播放退回占位模式。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
