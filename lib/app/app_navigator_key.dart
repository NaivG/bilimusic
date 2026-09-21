import 'package:flutter/material.dart';

/// 全局导航 Key：给没有 BuildContext 的场景用，
/// 例如桌面端窗口监听器在关闭时弹出「关闭行为」确认框。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
