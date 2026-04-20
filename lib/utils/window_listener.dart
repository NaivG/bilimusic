import 'package:window_manager/window_manager.dart';

class BilimusicWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.destroy();
  }

  @override
  void onWindowMinimize() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}
}
