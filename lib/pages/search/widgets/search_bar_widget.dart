import 'package:flutter/material.dart';
import 'package:bilimusic/utils/responsive.dart';

/// 搜索栏组件
class SearchBarWidget extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSearch;
  final VoidCallback? onClear;
  final bool autoFocus;
  final String hintText;
  final bool showBackButton;

  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.onSearch,
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

  @override
  Widget build(BuildContext context) {
    final screenSize = ResponsiveHelper.getScreenSize(context);
    final isDesktop = screenSize == ScreenSize.desktop;

    if (isDesktop) {
      return _buildDesktopSearchBar(context);
    } else {
      return _buildMobileSearchBar(context);
    }
  }

  Widget _buildDesktopSearchBar(BuildContext context) {
    return Container(
      height: 40,
      constraints: const BoxConstraints(maxWidth: 500),
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autoFocus,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onClear?.call();
                  },
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onSubmitted: widget.onSearch,
        onChanged: (value) {
          if (value.isEmpty) {
            widget.onClear?.call();
          }
        },
      ),
    );
  }

  Widget _buildMobileSearchBar(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autoFocus,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: widget.showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                )
              : Icon(Icons.search, color: Colors.grey.shade600),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onClear?.call();
                  },
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onSubmitted: widget.onSearch,
        onChanged: (value) {
          if (value.isEmpty) {
            widget.onClear?.call();
          }
        },
      ),
    );
  }
}
