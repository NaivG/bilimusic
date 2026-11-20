import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/sections/bm_page_header.dart';
import 'package:bilimusic/shared/ui/settings/bm_settings_group.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:bilimusic/shared/utils/title_meta_filter.dart';

/// 标题过滤规则（设置 → 播放 → 标题元数据过滤 → 标题过滤规则）。
class TitleFilterRulesPage extends ConsumerStatefulWidget {
  const TitleFilterRulesPage({super.key});

  /// 预览用样例。
  static const List<String> samples = [
    '【 作者 / MV 】Starlight【中字】',
    '郭静《心墙》百万豪装录音棚大声听',
    '在百万豪装录音棚大声听 林忆莲《词不达意》【Hi-res】',
    'MV / 打上花火【自翻】',
  ];

  @override
  ConsumerState<TitleFilterRulesPage> createState() =>
      _TitleFilterRulesPageState();
}

class _TitleFilterRulesPageState extends ConsumerState<TitleFilterRulesPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isLandscape = LandscapeBreakpoints.shouldUseLandscapeLayout(context);
    final inset = isLandscape ? BmTokens.contentInset : BmTokens.pageInsetWide;

    return Scaffold(
      backgroundColor: context.bmColors.bg.withValues(alpha: 0),
      body: SafeArea(
        top: !isLandscape,
        bottom: false,
        left: false,
        right: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BmPageHeader(
                title: '标题过滤规则',
                subtitle: '正则表达式 · 只影响新拉取的标题，已保存的不回溯修改',
                padding: EdgeInsets.fromLTRB(
                  inset,
                  isLandscape ? BmTokens.contentInsetTop : BmTokens.s4,
                  inset,
                  0,
                ),
              ),
              _buildBuiltinGroup(context),
              _buildUserGroup(context, settings),
              _buildPreviewGroup(context),
              const SizedBox(height: BmTokens.s6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBuiltinGroup(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return BmSettingsGroup(
      title: '内置规则',
      footer:
          '括号内规则只在括号里生效，命中即删掉文字（Hi-Res / 杜比这类音质段除外）；'
          '全标题规则在整条标题上生效。',
      children: [
        for (final rule in TitleMetaFilter.builtinRules)
          BmSettingsRow(
            title: rule.kind == TitleRuleKind.bracket ? '括号内' : '全标题',
            subtitle: rule.source,
            icon: rule.kind == TitleRuleKind.bracket
                ? Icons.data_object_outlined
                : Icons.title_outlined,
            trailing: Text(
              '内置',
              style: type.micro.copyWith(color: colors.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _buildUserGroup(BuildContext context, SettingsState settings) {
    final colors = context.bmColors;
    final type = context.bmType;
    final notifier = ref.read(settingsProvider.notifier);
    return BmSettingsGroup(
      title: '自定义规则',
      footer:
          '按正则表达式匹配，大小写不敏感、全角自动折成半角，命中片段会从标题里删掉。'
          '错误规则会被自动跳过。',
      children: [
        for (final source in settings.titleFilterRules)
          _RuleRow(
            source: source,
            onDelete: () => notifier.removeTitleFilterRule(source),
          ),
        BmSettingsValueRow(
          title: '添加规则',
          subtitle: '写一条正则表达式',
          icon: Icons.add_circle_outline,
          onTap: _addRule,
        ),
        if (settings.titleFilterRules.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BmTokens.s4,
              BmTokens.s2,
              BmTokens.s4,
              BmTokens.s3,
            ),
            child: Text(
              '还没有自定义规则，当前只应用内置规则。',
              style: type.caption.copyWith(color: colors.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewGroup(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    // watch 一下 settings：规则变了预览要跟着重算（过滤器的规则是静态的）。
    ref.watch(settingsProvider);
    return BmSettingsGroup(
      title: '示例预览',
      footer: '预览始终按当前全部规则计算，与启用状态无关。',
      children: [
        for (final sample in TitleFilterRulesPage.samples)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BmTokens.s4,
              BmTokens.s2 + 1,
              BmTokens.s4,
              BmTokens.s2 + 1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sample,
                  style: type.label.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: BmTokens.s1 / 2),
                Text(
                  '→ ${TitleMetaFilter.clean(sample).cleaned}',
                  style: type.label.copyWith(color: colors.accentDeep),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addRule() async {
    final source = await showBmDialog<String>(
      context: context,
      builder: (_) => const _AddRuleDialog(),
    );
    if (source == null || source.isEmpty) return;
    await ref.read(settingsProvider.notifier).addTitleFilterRule(source);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已添加规则')));
  }
}

/// 一条自定义规则：源码 + 实时有效性标记 + 删除。
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.source, required this.onDelete});

  final String source;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final rule = TitleFilterRule(source: source);
    final valid = rule.isValid;
    return BmSettingsRow(
      title: source,
      subtitle: valid ? '正则表达式' : '正则表达式有语法错误，已跳过',
      icon: valid ? Icons.code_outlined : Icons.error_outline,
      danger: !valid,
      trailing: BmIconButton(
        icon: Icons.delete_outline,
        tooltip: '删除规则',
        danger: true,
        size: BmIconButtonSize.sm,
        onPressed: onDelete,
      ),
    );
  }
}

/// 添加规则对话框：输入即校验，非法正则不给提交。
class _AddRuleDialog extends StatefulWidget {
  const _AddRuleDialog();

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final source = _controller.text.trim();
    if (source.isEmpty) return false;
    return TitleFilterRule(source: source).isValid;
  }

  void _submit() {
    final source = _controller.text.trim();
    if (source.isEmpty) return;
    if (!TitleFilterRule(source: source).isValid) {
      setState(() => _error = '正则表达式语法有误');
      return;
    }
    Navigator.of(context).pop(source);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return BmDialog(
      title: '添加过滤规则',
      hasFields: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '写一段正则表达式，命中的文字会从标题里删掉。例如：',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: BmTokens.s1),
          Text(
            r'百万豪装录音棚|【?\s*翻自[:：][^】]*】?',
            style: type.micro.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: BmTokens.s2),
          BmField(
            controller: _controller,
            hintText: '百万豪装录音棚',
            autofocus: true,
            errorText: _error,
            textInputAction: TextInputAction.done,
            // 每次输入都要 setState：`_valid` 决定「添加」按钮的可用态，
            // 只在清错误时 setState 会让按钮一直停在禁用上。
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        BmDialogAction(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BmDialogAction(label: '添加', enabled: _valid, onPressed: _submit),
      ],
    );
  }
}
