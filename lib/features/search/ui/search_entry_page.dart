import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_bar_widget.dart';
import 'package:bilimusic/features/search/ui/search_suggest_panel.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 竖屏搜索中间态：输入框 + 联想面板。
///
/// 不占导航 Tab；从首页搜索入口压栈进入，提交后直接把搜索结果压在上面，
/// 返回时仍回到这里继续改关键词。横屏不使用本页，由标题栏驱动
/// [SearchSuggestPanel]。
class SearchEntryPage extends ConsumerStatefulWidget {
  const SearchEntryPage({super.key});

  @override
  ConsumerState<SearchEntryPage> createState() => _SearchEntryPageState();
}

class _SearchEntryPageState extends ConsumerState<SearchEntryPage> {
  late final TextEditingController _controller;
  late final bool _autoFocus;

  @override
  void initState() {
    super.initState();
    final term = ref.read(searchSuggestProvider).term;
    _controller = TextEditingController(text: term);
    // 从结果页返回时保留关键词，但不再自动弹键盘。
    _autoFocus = term.isEmpty;
    if (term.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(searchSuggestProvider.notifier).update(term);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(searchSuggestProvider.notifier).update(value);
  }

  void _submit(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;

    if (_controller.text != query) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    FocusScope.of(context).unfocus();
    // 搜索在入口发起、结果存进应用级 Provider；结果页只订阅状态。
    // 这样从分P歌单 / UP 主页返回时页面重建不会重新搜索。
    ref.read(searchSuggestProvider.notifier).remember(query);
    ref.read(searchResultsProvider.notifier).search(query);
    ShellPageManager.instance.push(
      ShellPage.searchResults,
      args: {'query': query},
    );
  }

  @override
  Widget build(BuildContext context) {
    // 横屏不使用本页：标题栏是唯一输入口。AppShell 会在转屏后把它弹掉，
    // 这里先让出一帧，避免和标题栏搜索框同屏。
    if (LandscapeBreakpoints.shouldUseLandscapeLayout(context)) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                    ),
                    onPressed: () => ShellPageManager.instance.pop(),
                  ),
                  Expanded(
                    child: SearchBarWidget(
                      controller: _controller,
                      autoFocus: _autoFocus,
                      hintText: '搜索音乐、视频、用户...',
                      onSearch: _submit,
                      onChanged: _onChanged,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: SearchSuggestPanel(onSelected: _submit)),
          ],
        ),
      ),
    );
  }
}
