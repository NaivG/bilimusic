import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/search_suggest.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_empty_state.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 搜索中间态的联想面板：只有列表，没有输入框。
///
/// 竖屏由 [SearchEntryPage] 的输入框驱动，横屏由标题栏搜索框驱动；
/// 输入为空时展示热门搜索，有输入时展示接口联想词。
class SearchSuggestPanel extends ConsumerWidget {
  /// 选中一条联想（或热门搜索）时回调，参数是要搜索的关键词。
  final ValueChanged<String> onSelected;

  const SearchSuggestPanel({super.key, required this.onSelected});

  /// 输入为空时的热门搜索。
  static const List<String> hotSearches = ['周杰伦', '林俊杰', '五月天', '陈奕迅', '邓紫棋'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggest = ref.watch(searchSuggestProvider);

    if (suggest.term.isEmpty) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: BmTokens.s4),
        children: [
          HotSearchSuggestions(
            suggestions: hotSearches,
            onSuggestionTap: onSelected,
          ),
        ],
      );
    }

    if (suggest.isLoading) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: BmTokens.s5),
        children: const [_PanelHint(loading: true)],
      );
    }

    if (suggest.items.isEmpty) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: BmTokens.s6),
        children: const [_PanelHint(text: '没有相关搜索')],
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: BmTokens.s1),
      itemCount: suggest.items.length,
      itemBuilder: (context, index) {
        final item = suggest.items[index];
        return BmPressable(
          onTap: () => onSelected(item.value),
          borderRadius: BmTokens.r10All,
          semanticLabel: item.name,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BmTokens.pageInset,
              vertical: BmTokens.s2,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: BmTokens.iconMenu,
                  color: context.bmColors.textTertiary,
                ),
                const SizedBox(width: BmTokens.s3),
                Expanded(child: _buildTitle(context, item, suggest.term)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 在剥掉标签的展示文本里重新标出用户输入的部分。
  Widget _buildTitle(BuildContext context, SearchSuggest item, String term) {
    final colors = context.bmColors;
    final type = context.bmType;
    final baseStyle = type.body.copyWith(color: colors.textPrimary);
    final start = item.name.toLowerCase().indexOf(term.toLowerCase());
    if (start < 0 || term.isEmpty) {
      return Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    final end = start + term.length;
    // 大小写转换在个别字符上会改变长度，越界时退回纯文本。
    if (end > item.name.length) {
      return Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    final highlight = baseStyle.copyWith(
      color: colors.accent,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: item.name.substring(0, start)),
          TextSpan(text: item.name.substring(start, end), style: highlight),
          TextSpan(text: item.name.substring(end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 联想列表的加载中 / 空结果提示。
class _PanelHint extends StatelessWidget {
  final String? text;
  final bool loading;

  const _PanelHint({this.text, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            SizedBox(
              width: BmTokens.s4,
              height: BmTokens.s4,
              child: CircularProgressIndicator(
                strokeWidth: BmTokens.s1 / 2,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(width: BmTokens.s2),
            Text(
              '正在搜索…',
              style: type.label.copyWith(color: colors.textSecondary),
            ),
          ] else
            Text(
              text ?? '',
              style: type.body.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}
