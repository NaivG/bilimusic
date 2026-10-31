import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/search_suggest.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_empty_state.dart';

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
        padding: const EdgeInsets.symmetric(vertical: 16),
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
        padding: const EdgeInsets.symmetric(vertical: 28),
        children: const [_PanelHint(loading: true)],
      );
    }

    if (suggest.items.isEmpty) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 32),
        children: const [_PanelHint(text: '没有相关搜索')],
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: suggest.items.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 0.5,
        indent: 48,
        endIndent: 16,
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
      ),
      itemBuilder: (context, index) {
        final item = suggest.items[index];
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(
            Icons.search,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.7),
          ),
          title: _buildTitle(context, item, suggest.term),
          onTap: () => onSelected(item.value),
        );
      },
    );
  }

  /// 在剥掉标签的展示文本里重新标出用户输入的部分。
  Widget _buildTitle(BuildContext context, SearchSuggest item, String term) {
    final start = item.name.toLowerCase().indexOf(term.toLowerCase());
    if (start < 0 || term.isEmpty) {
      return Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final end = start + term.length;
    // 大小写转换在个别字符上会改变长度，越界时退回纯文本。
    if (end > item.name.length) {
      return Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final highlight = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
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
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
            const SizedBox(width: 10),
            Text('正在搜索…', style: TextStyle(fontSize: 13, color: color)),
          ] else
            Text(text ?? '', style: TextStyle(fontSize: 14, color: color)),
        ],
      ),
    );
  }
}
