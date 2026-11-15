import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';

// iPhone Duo 有竖栏时（合上、展开横拿），二级页导航栏上的返回键和操作按钮
// 放进竖栏顶端（摄像头和状态栏下面），不再占用页面顶部；页面顶部只留标题。
// 竖栏里只放图标按钮，没有图标的按钮留在页面里。
//
// 页面通过 [VerticalBarToolbarItems] 登记按钮，外壳用 [VerticalBarToolbar]
// 把当前页面登记的按钮画在竖栏里。

/// 当前页面登记到竖栏的按钮。外壳持有一个，经 [VerticalBarToolbarScope] 传下去。
class VerticalBarToolbarController extends ChangeNotifier {
  Object? _owner;
  List<Widget> _items = const [];

  /// 当前要画在竖栏里的按钮。
  List<Widget> get items => _items;

  void _set(Object owner, List<Widget> items) {
    _owner = owner;
    _items = items;
    notifyListeners();
  }

  void _clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _items = const [];
    notifyListeners();
  }
}

/// 告诉页面「导航栏按钮要放进竖栏」。没有竖栏时 [controller] 为 null，
/// 页面照常把按钮画在自己的导航栏里。
class VerticalBarToolbarScope extends InheritedWidget {
  const VerticalBarToolbarScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final VerticalBarToolbarController? controller;

  /// 按钮要放进竖栏时返回控制器，否则返回 null。
  static VerticalBarToolbarController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VerticalBarToolbarScope>()
      ?.controller;

  /// 能放进竖栏的按钮：图标按钮。只有文字的按钮系统也不会放进竖栏。
  static bool fitsInBar(Widget widget) =>
      widget is IconButton || widget is BmIconButton;

  @override
  bool updateShouldNotify(VerticalBarToolbarScope oldWidget) =>
      controller != oldWidget.controller;
}

/// 把 [items] 登记到竖栏，自身显示 [child]。离开页面时撤销登记。
class VerticalBarToolbarItems extends StatefulWidget {
  const VerticalBarToolbarItems({
    super.key,
    required this.items,
    required this.child,
  });

  final List<Widget> items;
  final Widget child;

  @override
  State<VerticalBarToolbarItems> createState() =>
      _VerticalBarToolbarItemsState();
}

class _VerticalBarToolbarItemsState extends State<VerticalBarToolbarItems> {
  VerticalBarToolbarController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = VerticalBarToolbarScope.of(context);
    if (!identical(controller, _controller)) {
      _controller?._clear(this);
      _controller = controller;
    }
    _register();
  }

  @override
  void didUpdateWidget(covariant VerticalBarToolbarItems oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  /// 构建期间不能通知外壳重建，等这一帧结束再登记。
  void _register() {
    final controller = _controller;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(controller, _controller)) {
        controller._set(this, widget.items);
      }
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      // 撤销也放到帧后：这时外壳可能正在构建。
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller._clear(this),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 竖栏里画按钮的那一段：竖排、每个按钮占一格，宽度等于竖栏。
class VerticalBarToolbar extends StatelessWidget {
  const VerticalBarToolbar({
    super.key,
    required this.controller,
    required this.width,
  });

  final VerticalBarToolbarController controller;
  final double width;

  /// 每个按钮占的高度。
  static const double itemExtent = 48;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in controller.items)
            SizedBox(
              width: width,
              height: itemExtent,
              child: Center(child: item),
            ),
        ],
      ),
    );
  }
}
