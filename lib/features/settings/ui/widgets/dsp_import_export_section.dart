import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/features/player/effects_providers.dart';
import 'package:bilimusic/features/settings/logic/dsp_import_export.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// audio_dsp_page 末尾的「导入 / 导出」区。
///
/// 风格沿用主页面 [_FxModule] 的容器：浅色面、圆角、同样的 padding。
class DspImportExportSection extends ConsumerStatefulWidget {
  const DspImportExportSection({super.key});

  @override
  ConsumerState<DspImportExportSection> createState() =>
      _DspImportExportSectionState();
}

class _DspImportExportSectionState
    extends ConsumerState<DspImportExportSection> {
  /// 各模块「正在导出 / 正在导入」的标记。键 = module.key，值 = 正在做的动作。
  final Map<String, _DspIoKind> _busy = {};

  bool _busyAll = false;

  @override
  Widget build(BuildContext context) {
    final effects = ref.watch(audioEffectsProvider);
    final scheme = Theme.of(context).colorScheme;
    final primary = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : scheme.primary;
    // 与 audio_dsp_page 头部同款：浅色主表面 + 圆角，给整体页面统一节奏。
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: Icons.import_export_rounded,
            title: '导入与导出',
            scheme: scheme,
            primary: primary,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              '整套 DSP 配置可导出为 JSON 文件；也可只导出某个模块的'
              '片段，便于在设备间或与他人分享。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ),
          // ── 整体 ──
          _row(
            label: '整体',
            status: _allStatus(effects),
            primary: primary,
            scheme: scheme,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _smallButton(
                  label: '导出',
                  icon: Icons.file_upload_outlined,
                  onPressed: _busyAll ? null : () => _exportAll(effects),
                  primary: primary,
                ),
                const SizedBox(width: 8),
                _smallButton(
                  label: '导入',
                  icon: Icons.file_download_outlined,
                  onPressed: _busyAll ? null : () => _importAll(),
                  primary: primary,
                  outlined: true,
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          // ── 单项 ──
          for (var i = 0; i < DspConfigImportExport.modules.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _moduleRow(
              module: DspConfigImportExport.modules[i],
              primary: primary,
              scheme: scheme,
            ),
          ],
          if (_busyAll)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  /// 整体配置当前状态
  String _allStatus(mpv.AudioEffects e) {
    var open = 0;
    if (e.anequalizer?.enabled == true) open++;
    if (e.crossfeed?.enabled == true) open++;
    if (e.acompressor?.enabled == true) open++;
    if (e.asubboost?.enabled == true) open++;
    if (e.aexciter?.enabled == true) open++;
    if (e.aecho?.enabled == true) open++;
    if (e.alimiter?.enabled == true) open++;
    if (e.extrastereo?.enabled == true) open++;
    if (e.surround?.enabled == true) open++;
    return open == 0 ? '全部模块已关闭' : '$open / 9 个模块已开启';
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required ColorScheme scheme,
    required Color primary,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// 整体那一行。
  Widget _row({
    required String label,
    required String status,
    required Widget trailing,
    required Color primary,
    required ColorScheme scheme,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        trailing,
      ],
    );
  }

  /// 单项模块的行。
  Widget _moduleRow({
    required DspModuleExport module,
    required Color primary,
    required ColorScheme scheme,
  }) {
    final theme = Theme.of(context);
    final busy = _busy[module.key];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            module.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
        const Spacer(),
        if (busy != null)
          SizedBox(
            width: 28,
            height: 28,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(primary),
              ),
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _smallButton(
                label: '导出',
                icon: Icons.file_upload_outlined,
                onPressed: () => _exportModule(module),
                primary: primary,
              ),
              const SizedBox(width: 8),
              _smallButton(
                label: '导入',
                icon: Icons.file_download_outlined,
                onPressed: () => _importModule(module),
                primary: primary,
                outlined: true,
              ),
            ],
          ),
      ],
    );
  }

  /// 紧凑版按钮：图标 + 文字，单边框描边可选。
  Widget _smallButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color primary,
    bool outlined = false,
  }) {
    // 不同行宽都给得下：紧凑 padding + 16sp icon、12sp label。
    final style = TextStyle(fontSize: 12, color: primary);
    final iconSize = 16.0;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: outlined
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                side: BorderSide(color: primary.withValues(alpha: 0.35)),
              )
            : null,
        textStyle: style,
        iconAlignment: IconAlignment.start,
      ),
      icon: Icon(icon, size: iconSize, color: primary),
      label: Text(label, style: style),
    );
  }

  // ── 整体：导出 ────────────────────────────────────────────────────────

  Future<void> _exportAll(mpv.AudioEffects effects) async {
    final messenger = ScaffoldMessenger.of(context);
    final prefix = DspConfigImportExport.fileNamePrefixFull();
    setState(() => _busyAll = true);
    try {
      final json = DspConfigImportExport.encodeAll(effects);
      final path = await _saveJson(
        bytes: utf8.encode(json),
        fileName: _fileName(prefix),
      );
      _finish(messenger, path == null ? '已取消导出' : '已导出整包配置\n$path');
    } catch (e) {
      _finish(messenger, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busyAll = false);
    }
  }

  // ── 整体：导入 ────────────────────────────────────────────────────────

  Future<void> _importAll() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyAll = true);
    try {
      final content = await _pickJson();
      if (content == null) {
        _finish(messenger, '已取消导入');
        return;
      }
      final env = DspConfigImportExport.decodeEnvelope(content);
      if (!env.isFull) {
        _finish(
          messenger,
          '这是单模块（${env.module?.label ?? env.module}）的导出文件，'
          '请改用对应模块的「导入」。',
        );
        return;
      }
      // 二次确认：整包导入会覆盖当前所有模块的设置。
      final ok = await _confirmDangerous(
        title: '导入整套 DSP 配置',
        body:
            '将覆盖当前所有 9 个模块的设置。\n\n'
            '导出文件版本：${env.config.length} 个模块配置项。\n\n'
            '确定继续吗？',
        confirmLabel: '覆盖导入',
      );
      if (!ok) {
        _finish(messenger, '已取消导入');
        return;
      }
      final next = DspConfigImportExport.decodeFull(env);
      await ref.read(audioEffectsCommandsProvider.notifier).setEffects(next);
      _finish(messenger, '已导入整套 DSP 配置');
    } on DspConfigFormatException catch (e) {
      _finish(messenger, '文件无法识别：${e.message}');
    } catch (e) {
      _finish(messenger, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busyAll = false);
    }
  }

  // ── 单项：导出 ────────────────────────────────────────────────────────

  Future<void> _exportModule(DspModuleExport module) async {
    final messenger = ScaffoldMessenger.of(context);
    final effects = ref.read(audioEffectsProvider);
    setState(() => _busy[module.key] = _DspIoKind.export);
    try {
      final json = DspConfigImportExport.encodeModule(effects, module);
      final path = await _saveJson(
        bytes: utf8.encode(json),
        fileName: _fileName(DspConfigImportExport.fileNamePrefixModule(module)),
      );
      _finish(
        messenger,
        path == null ? '已取消导出' : '已导出「${module.label}」配置\n$path',
      );
    } catch (e) {
      _finish(messenger, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(module.key));
    }
  }

  // ── 单项：导入 ────────────────────────────────────────────────────────

  Future<void> _importModule(DspModuleExport module) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy[module.key] = _DspIoKind.import);
    try {
      final content = await _pickJson();
      if (content == null) {
        _finish(messenger, '已取消导入');
        return;
      }
      final env = DspConfigImportExport.decodeEnvelope(content);
      if (env.isFull) {
        _finish(messenger, '这是整套配置的导出文件。请改用整包「导入」。');
        return;
      }
      if (env.module?.key != module.key) {
        _finish(
          messenger,
          '此文件属于「${env.module?.label ?? env.module}」，'
          '请改用「${env.module?.label ?? env.module}」行的导入按钮。',
        );
        return;
      }
      final base = ref.read(audioEffectsProvider);
      final next = DspConfigImportExport.applyModule(base, env);
      await ref.read(audioEffectsCommandsProvider.notifier).setEffects(next);
      _finish(messenger, '已导入「${module.label}」配置');
    } on DspConfigFormatException catch (e) {
      _finish(messenger, '文件无法识别：${e.message}');
    } catch (e) {
      _finish(messenger, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(module.key));
    }
  }

  // ── 通用工具 ──────────────────────────────────────────────────────────

  /// 把字节流保存到磁盘，让用户挑位置。
  ///
  /// 桌面端用 file_picker + dart:io；移动端用 file_picker 直接传 bytes
  /// （无需先落临时文件）。成功返回用户指定的绝对路径，取消返回 null。
  Future<String?> _saveJson({
    required List<int> bytes,
    required String fileName,
  }) async {
    if (PlatformHelper.isMobile) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存 DSP 配置',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(bytes),
      );
      return path;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存 DSP 配置',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return null;
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// 让用户挑一个 .json，回传原始字符串。失败 / 取消返回 null。
  ///
  /// 桌面端拿真实路径后再读，移动端直接用 bytes（不经过临时文件）。
  Future<String?> _pickJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: '选择 DSP 配置文件',
      withData: PlatformHelper.isMobile,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (PlatformHelper.isMobile) {
      final bytes = file.bytes;
      if (bytes == null) return null;
      return utf8.decode(bytes);
    }
    final path = file.path;
    if (path == null) return null;
    return File(path).readAsString();
  }

  /// 整套 import 是不可逆覆盖：先让用户走一道确认弹窗。
  Future<bool> _confirmDangerous({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 在 SnackBar 上报告一条结果，同时给点视觉反馈。
  void _finish(ScaffoldMessengerState messenger, String message) {
    if (!mounted) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 文件名加上时间戳，便于多人导出时区分。
  String _fileName(String prefix) {
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${prefix}_$ts.json';
  }
}

enum _DspIoKind { export, import }
