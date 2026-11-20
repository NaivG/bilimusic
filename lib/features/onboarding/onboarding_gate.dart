import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/onboarding/onboarding_launch.dart';
import 'package:bilimusic/features/onboarding/onboarding_provider.dart';
import 'package:bilimusic/features/onboarding/ui/onboarding_content.dart';
import 'package:bilimusic/features/onboarding/ui/onboarding_page.dart';
import 'package:bilimusic/shared/motion/motion.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/utils/app_version.dart';

/// 启动时的引导门控。
///
/// 只做两件事：
/// 1. 盘上没有 `last_boot_version` → 盖一层完整引导页（首启，或第一次运行
///    带这个标记的版本；老用户也因此会看到一次，这是刻意的）。
/// 2. 版本号比上次大 → 弹一个「已升级至 x.y.z」的轻量弹窗，给一个更新日志
///    入口。引导页本身不按版本重写，后续版本继续复用同一套页面。
///
/// 判断放在首帧之后、读的是磁盘值，因此不会出现「老用户先闪一下引导页再
/// 消失」的时序问题。引导页是盖在 [child] 上的一层，而不是独立路由：
/// 底下的壳层照常装配，关掉之后页面状态不会丢；也避免和更新弹窗、PiP 等
/// 路由抢 Navigator。
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({
    super.key,
    required this.child,
    this.currentVersion = appVersion,
  });

  final Widget child;

  /// 当前版本；默认取 [appVersion]，测试里可以覆盖。
  final String currentVersion;

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// CurvedAnimation 会向 parent 挂 status listener，必须建一次并 dispose；
  /// 放在 build 里每帧 new 一个会持续泄漏监听。
  late final CurvedAnimation _fade;

  bool _visible = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BmMotion.xlarge,
      reverseDuration: BmMotion.large,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: BmMotion.emphasized,
      reverseCurve: BmMotion.exit,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeReveal());
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _maybeReveal() async {
    String? last;
    try {
      last = await ref.read(lastBootVersionProvider.future);
    } catch (error) {
      // 读盘失败时不打扰用户：宁可少弹一次，也不要每次启动都弹。
      debugPrint(
        '[BiliMusic/onboarding] read last boot version failed: $error',
      );
      return;
    }
    if (!mounted) return;

    final decision = decideOnboardingLaunch(
      currentVersion: widget.currentVersion,
      lastBootVersion: last,
    );

    // 先落盘再展示：用户中途关掉应用，下次启动不会把同一次升级再弹一遍。
    try {
      await recordBootVersion(ref, widget.currentVersion);
    } catch (error) {
      debugPrint('[BiliMusic/onboarding] write boot version failed: $error');
    }
    if (!mounted) return;

    switch (decision) {
      case OnboardingLaunch.none:
        return;
      case OnboardingLaunch.upgradeDialog:
        unawaited(_showUpgradeDialog());
        return;
      case OnboardingLaunch.onboarding:
        setState(() => _visible = true);
        if (reduceMotionOf(context)) {
          _controller.value = 1;
        } else {
          _controller.forward();
        }
    }
  }

  Future<void> _showUpgradeDialog() async {
    final openChangelog = await showBmDialog<bool>(
      context: context,
      builder: (dialogContext) => BmDialog(
        title: '已升级至 ${widget.currentVersion}',
        message: '看看这次更新了什么。',
        actions: <BmDialogAction>[
          BmDialogAction(
            label: '稍后',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          BmDialogAction(
            label: '查看更新日志',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (!mounted || openChangelog != true) return;
    ShellPageManager.instance.push(ShellPage.changelog);
  }

  Future<void> _dismiss() async {
    if (_dismissing || !_visible) return;
    setState(() => _dismissing = true);
    if (reduceMotionOf(context)) {
      _controller.value = 0;
    } else {
      await _controller.reverse();
    }
    if (!mounted) return;
    setState(() {
      _visible = false;
      _dismissing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) unawaited(_dismiss());
          },
          child: FadeTransition(
            opacity: _fade,
            child: OnboardingPage(
              pages: onboardingPages,
              onDone: () => unawaited(_dismiss()),
              onSkip: () => unawaited(_dismiss()),
            ),
          ),
        ),
      ],
    );
  }
}
