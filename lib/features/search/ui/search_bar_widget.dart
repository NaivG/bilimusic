import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 搜索栏组件：40 高胶囊，`surfaceRaised` 底 + `hairline` 描边。
class SearchBarWidget extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSearch;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final bool autoFocus;
  final String hintText;
  final bool showBackButton;

  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.onSearch,
    this.onChanged,
    this.onClear,
    this.autoFocus = false,
    this.hintText = '输入音乐名称、艺术家或BV/AV号',
    this.showBackButton = false,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final isDesktop =
        ResponsiveHelper.getScreenSize(context) == ScreenSize.desktop;

    return Container(
      height: BmTokens.controlLg,
      constraints: isDesktop ? const BoxConstraints(maxWidth: 500) : null,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BmTokens.r12All,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autoFocus,
        textInputAction: TextInputAction.search,
        style: type.body.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: type.body.copyWith(color: colors.textTertiary),
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s3,
            vertical: BmTokens.s2,
          ),
          prefixIcon: widget.showBackButton
              ? BmIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: '返回',
                  size: BmIconButtonSize.sm,
                  onPressed: () => Navigator.pop(context),
                )
              : Icon(
                  Icons.search_rounded,
                  size: BmTokens.icon,
                  color: colors.textSecondary,
                ),
          suffixIcon: _hasText
              ? BmIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '清除',
                  size: BmIconButtonSize.sm,
                  onPressed: _clear,
                )
              : null,
          prefixIconConstraints: const BoxConstraints(
            minWidth: BmTokens.controlLg,
            minHeight: BmTokens.controlLg,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: BmTokens.controlLg,
            minHeight: BmTokens.controlLg,
          ),
        ),
        onSubmitted: widget.onSearch,
        onChanged: (value) {
          widget.onChanged?.call(value);
          if (value.isEmpty) {
            widget.onClear?.call();
          }
        },
      ),
    );
  }
}
